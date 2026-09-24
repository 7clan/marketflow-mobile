import '../../core/errors/app_exception.dart';
import '../../domain/entities/order.dart';
import 'address_model.dart';
import 'cart_item_model.dart';
import 'json_reader.dart';

/// Wire representation of a placed order.
class OrderModel {
  const OrderModel({
    required this.id,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.shipping,
    required this.tax,
    required this.total,
    required this.address,
    required this.placedAt,
    required this.estimatedDelivery,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final status = OrderStatus.fromWireName(
      JsonReader.requireString(json, 'status'),
    );
    if (status == null) {
      throw MalformedResponseException(
        cause: 'Field "status" is not a known order status.',
      );
    }
    final items = <CartItemModel>[];
    for (final raw in JsonReader.requireList(json, 'items')) {
      if (raw is! Map<String, dynamic>) {
        throw MalformedResponseException(
          cause: 'Field "items" must be an array of cart-entry objects.',
        );
      }
      items.add(CartItemModel.fromJson(raw));
    }
    return OrderModel(
      id: JsonReader.requireString(json, 'id'),
      status: status,
      items: items,
      subtotal: JsonReader.requireDouble(json, 'subtotal'),
      shipping: JsonReader.requireDouble(json, 'shipping'),
      tax: JsonReader.requireDouble(json, 'tax'),
      total: JsonReader.requireDouble(json, 'total'),
      address: AddressModel.fromJson(JsonReader.requireMap(json, 'address')),
      placedAt: JsonReader.requireDateTime(json, 'placedAt'),
      estimatedDelivery: JsonReader.requireDateTime(json, 'estimatedDelivery'),
    );
  }

  final String id;
  final OrderStatus status;
  final List<CartItemModel> items;
  final double subtotal;
  final double shipping;
  final double tax;
  final double total;
  final AddressModel address;
  final DateTime placedAt;
  final DateTime estimatedDelivery;

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.wireName,
    'items': [for (final item in items) item.toJson()],
    'subtotal': subtotal,
    'shipping': shipping,
    'tax': tax,
    'total': total,
    'address': address.toJson(),
    'placedAt': placedAt.toIso8601String(),
    'estimatedDelivery': estimatedDelivery.toIso8601String(),
  };

  Order toDomain() => Order(
    id: id,
    status: status,
    items: [for (final item in items) item.toDomain()],
    subtotal: subtotal,
    shipping: shipping,
    tax: tax,
    total: total,
    address: address.toDomain(),
    placedAt: placedAt,
    estimatedDelivery: estimatedDelivery,
  );

  static OrderModel fromDomain(Order order) => OrderModel(
    id: order.id,
    status: order.status,
    items: [for (final item in order.items) CartItemModel.fromDomain(item)],
    subtotal: order.subtotal,
    shipping: order.shipping,
    tax: order.tax,
    total: order.total,
    address: AddressModel.fromDomain(order.address),
    placedAt: order.placedAt,
    estimatedDelivery: order.estimatedDelivery,
  );
}
