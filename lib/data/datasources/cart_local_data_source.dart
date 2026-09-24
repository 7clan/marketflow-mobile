import '../../domain/entities/cart_item.dart';

/// Persistence seam for the shopping cart.
///
/// Each entry stores the full product snapshot, the quantity and the unit
/// price captured when the item was added, so the cart renders instantly on
/// a cold start without a network round-trip. (The product id + quantity +
/// price snapshot IS the entry; the extra product fields are cached for
/// offline rendering.)
abstract interface class CartLocalDataSource {
  /// Restores the persisted entries.
  Future<List<CartItem>> load();

  /// Persists the entries.
  Future<void> save(List<CartItem> items);

  /// Removes the persisted cart.
  Future<void> clear();
}

/// Fully in-memory variant for tests and previews.
class InMemoryCartLocalDataSource implements CartLocalDataSource {
  List<CartItem> _items = const <CartItem>[];

  @override
  Future<List<CartItem>> load() async => List<CartItem>.unmodifiable(_items);

  @override
  Future<void> save(List<CartItem> items) async =>
      _items = List<CartItem>.unmodifiable(items);

  @override
  Future<void> clear() async => _items = const <CartItem>[];
}
