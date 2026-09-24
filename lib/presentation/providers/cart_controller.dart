import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_totals.dart';
import '../../domain/entities/product.dart';
import 'infrastructure_providers.dart';

/// Rendered state of the shopping cart.
///
/// Totals are always **derived** (never stored) via [computeCartTotals], so
/// every surface shows the same numbers from the same items.
class CartState {
  const CartState({
    this.items = const <CartItem>[],
    this.validationMessages = const <String, String>{},
    this.error,
  });

  /// Cart lines (deduped by product id, quantities within bounds).
  final List<CartItem> items;

  /// Per-product validation messages (e.g. "Only 3 left in stock") keyed by
  /// product id — surfaced inline under the affected line.
  final Map<String, String> validationMessages;

  /// Persistence error of the last mutation, when saving failed.
  final AppException? error;

  /// Derived monetary summary (subtotal, shipping, tax, total).
  CartTotals get totals => computeCartTotals(items);

  /// Total number of units across all lines.
  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  /// `true` when the cart has no lines.
  bool get isEmpty => items.isEmpty;

  /// The line for [productId], or `null`.
  CartItem? itemFor(String productId) {
    for (final item in items) {
      if (item.product.id == productId) return item;
    }
    return null;
  }

  /// The validation message for [productId], or `null`.
  String? messageFor(String productId) => validationMessages[productId];

  CartState copyWith({
    List<CartItem>? items,
    Map<String, String>? validationMessages,
    Object? error = _unset,
  }) {
    return CartState(
      items: items ?? this.items,
      validationMessages: validationMessages ?? this.validationMessages,
      error: identical(error, _unset) ? this.error : error as AppException?,
    );
  }

  /// Sentinel for [copyWith]'s nullable clear.
  static const _unset = Object();
}

/// The shopping cart.
///
/// * mutations are synchronous and optimistic (local data, no network);
/// * every mutation persists immediately via [CartRepository] (fire and
///   forget — a persistence failure surfaces as [CartState.error] but never
///   reverts the in-memory cart);
/// * the cart is restored from storage on startup;
/// * quantity bounds: deduped by product, `1..min(stock, 99)` when in stock.
final cartControllerProvider = NotifierProvider<CartController, CartState>(
  CartController.new,
);

class CartController extends Notifier<CartState> {
  /// Bumped by every mutating method — lets the async [_restore] detect
  /// that a mutation landed mid-restore and skip its stale snapshot.
  int _mutationSeq = 0;

  @override
  CartState build() {
    // The cart badge must be alive wherever the user navigates.
    ref.keepAlive();
    unawaited(_restore());
    return const CartState();
  }

  Future<void> _restore() async {
    final seqAtStart = _mutationSeq;
    final repository = ref.read(cartRepositoryProvider);
    try {
      final items = await repository.loadCart();
      // A mutation landing mid-restore wins: its own persist has already
      // re-written storage, and applying this stale snapshot would
      // silently revert the user's action.
      if (seqAtStart != _mutationSeq) return;
      state = state.copyWith(items: items);
    } on CacheException catch (error) {
      if (seqAtStart != _mutationSeq) return;
      state = state.copyWith(error: error);
    }
  }

  /// Adds [quantity] units of [product] (deduped by product id).
  void addToCart(Product product, {int quantity = 1}) {
    if (product.isOutOfStock) {
      _mutate(
        state.items,
        messages: {...state.validationMessages, product.id: 'Out of stock.'},
      );
      return;
    }
    final bound = _maxQuantityFor(product);
    final existing = itemIndex(product.id);
    int newQuantity;
    Map<String, String> messages = {...state.validationMessages}
      ..remove(product.id);

    if (existing >= 0) {
      newQuantity = state.items[existing].quantity + quantity;
    } else {
      newQuantity = quantity;
    }

    String? message;
    if (newQuantity > bound) {
      newQuantity = bound;
      message = bound == CartItem.maxQuantity
          ? 'Maximum ${CartItem.maxQuantity} per order.'
          : 'Only $bound left in stock.';
    }
    if (message != null) {
      messages[product.id] = message;
    }

    final List<CartItem> items;
    if (existing >= 0) {
      items = [...state.items];
      items[existing] = state.items[existing].copyWith(quantity: newQuantity);
    } else {
      items = [
        ...state.items,
        CartItem(product: product, quantity: newQuantity),
      ];
    }
    _mutate(items, messages: messages);
  }

  /// Sets the quantity of an existing line (`<= 0` removes the line).
  void updateQuantity(String productId, int quantity) {
    final existing = itemIndex(productId);
    if (existing < 0) return;
    if (quantity <= 0) {
      removeItem(productId);
      return;
    }
    final item = state.items[existing];
    final bound = _maxQuantityFor(item.product);
    var newQuantity = quantity;
    String? message;
    if (newQuantity > bound) {
      newQuantity = bound;
      message = bound == CartItem.maxQuantity
          ? 'Maximum ${CartItem.maxQuantity} per order.'
          : 'Only $bound left in stock.';
    }
    final items = [...state.items];
    items[existing] = item.copyWith(quantity: newQuantity);
    final messages = {...state.validationMessages}..remove(productId);
    if (message != null) messages[productId] = message;
    _mutate(items, messages: messages);
  }

  /// Removes the line for [productId].
  void removeItem(String productId) {
    final items = [
      for (final item in state.items)
        if (item.product.id != productId) item,
    ];
    final messages = {...state.validationMessages}..remove(productId);
    _mutate(items, messages: messages);
  }

  /// Empties the cart.
  void clear() {
    _mutationSeq++;
    unawaited(_persist([], const <String, String>{}));
    state = const CartState();
  }

  /// Clears the last surfaced persistence error.
  void clearError() => state = state.copyWith(error: null);

  int itemIndex(String productId) {
    for (var i = 0; i < state.items.length; i++) {
      if (state.items[i].product.id == productId) return i;
    }
    return -1;
  }

  int _maxQuantityFor(Product product) => product.stock > 0
      ? (product.stock < CartItem.maxQuantity
            ? product.stock
            : CartItem.maxQuantity)
      : CartItem.maxQuantity;

  void _mutate(
    List<CartItem> items, {
    Map<String, String> messages = const {},
  }) {
    _mutationSeq++;
    state = state.copyWith(items: items, validationMessages: messages);
    unawaited(_persist(items, messages));
  }

  Future<void> _persist(
    List<CartItem> items,
    Map<String, String> messages,
  ) async {
    final repository = ref.read(cartRepositoryProvider);
    try {
      await repository.saveCart(items);
    } on CacheException catch (error) {
      state = state.copyWith(
        items: items,
        validationMessages: messages,
        error: error,
      );
    }
  }
}
