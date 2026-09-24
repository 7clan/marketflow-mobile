import '../../domain/entities/cart_item.dart';
import 'json_reader.dart';
import 'product_model.dart';

/// Wire/persistence representation of a cart line: the product snapshot,
/// the quantity, and the unit price captured when the item was added.
class CartItemModel {
  const CartItemModel({
    required this.product,
    required this.quantity,
    required this.unitPrice,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    return CartItemModel(
      product: ProductModel.fromJson(JsonReader.requireMap(json, 'product')),
      quantity: JsonReader.requireInt(json, 'quantity'),
      unitPrice: JsonReader.requireDouble(json, 'unitPrice'),
    );
  }

  final ProductModel product;
  final int quantity;
  final double unitPrice;

  Map<String, dynamic> toJson() => {
    'product': product.toJson(),
    'quantity': quantity,
    'unitPrice': unitPrice,
  };

  CartItem toDomain() => CartItem(
    product: product.toDomain(),
    quantity: quantity,
    unitPrice: unitPrice,
  );

  static CartItemModel fromDomain(CartItem item) => CartItemModel(
    product: ProductModel.fromDomain(item.product),
    quantity: item.quantity,
    unitPrice: item.unitPrice,
  );
}
