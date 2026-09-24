import '../entities/cart_item.dart';

/// Local cart persistence contract (no network involved).
abstract interface class CartRepository {
  /// Restores the persisted cart, sanitizing invalid entries.
  Future<List<CartItem>> loadCart();

  /// Persists the cart, enforcing quantity bounds.
  Future<void> saveCart(List<CartItem> items);

  /// Removes the persisted cart.
  Future<void> clear();
}
