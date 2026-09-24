import 'product.dart';

/// A product placed in the cart or recorded on an order, with the unit
/// price frozen at the moment it was added.
class CartItem {
  CartItem({required this.product, required this.quantity, double? unitPrice})
    : unitPrice = unitPrice ?? product.price;

  /// The product snapshot this line refers to.
  final Product product;

  /// Units of [product] in the cart (always `1..maxQuantity` once valid).
  final int quantity;

  /// Price per unit captured when the item was added — protects the user
  /// from silent price changes while shopping.
  final double unitPrice;

  /// Highest quantity a single cart line may hold (mirrored by the backend).
  static const int maxQuantity = 99;

  /// Cost of this line (`unitPrice × quantity`).
  double get lineTotal => unitPrice * quantity;

  CartItem copyWith({Product? product, int? quantity, double? unitPrice}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CartItem &&
        other.product == product &&
        other.quantity == quantity &&
        other.unitPrice == unitPrice;
  }

  @override
  int get hashCode => Object.hash(product, quantity, unitPrice);

  @override
  String toString() =>
      'CartItem(productId: ${product.id}, quantity: $quantity, '
      'unitPrice: $unitPrice)';
}
