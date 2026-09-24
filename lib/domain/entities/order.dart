import 'address.dart';
import 'cart_item.dart';

/// Lifecycle of a marketplace order.
enum OrderStatus {
  pending('pending'),
  processing('processing'),
  shipped('shipped'),
  delivered('delivered'),
  cancelled('cancelled');

  const OrderStatus(this.wireName);

  /// Value used on the wire (JSON) and by the backend.
  final String wireName;

  /// Parses the wire value; returns `null` for unknown values.
  static OrderStatus? fromWireName(String? value) {
    if (value == null) return null;
    for (final status in OrderStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }
}

/// Simulated payment methods accepted at checkout.
enum PaymentMethod {
  card('card'),
  cashOnDelivery('cod');

  const PaymentMethod(this.wireName);

  /// Value used on the wire (JSON) and by the backend.
  final String wireName;

  /// Parses the wire value; returns `null` for unknown values.
  static PaymentMethod? fromWireName(String? value) {
    if (value == null) return null;
    for (final method in PaymentMethod.values) {
      if (method.wireName == value) return method;
    }
    return null;
  }
}

/// A placed order, with its frozen line items and totals.
class Order {
  const Order({
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

  final String id;
  final OrderStatus status;

  /// Line-item snapshots taken when the order was placed.
  final List<CartItem> items;

  final double subtotal;
  final double shipping;
  final double tax;
  final double total;

  final Address address;
  final DateTime placedAt;
  final DateTime estimatedDelivery;

  /// Number of units across all lines.
  int get itemCount => items.fold<int>(0, (sum, item) => sum + item.quantity);

  Order copyWith({
    String? id,
    OrderStatus? status,
    List<CartItem>? items,
    double? subtotal,
    double? shipping,
    double? tax,
    double? total,
    Address? address,
    DateTime? placedAt,
    DateTime? estimatedDelivery,
  }) {
    return Order(
      id: id ?? this.id,
      status: status ?? this.status,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      shipping: shipping ?? this.shipping,
      tax: tax ?? this.tax,
      total: total ?? this.total,
      address: address ?? this.address,
      placedAt: placedAt ?? this.placedAt,
      estimatedDelivery: estimatedDelivery ?? this.estimatedDelivery,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Order &&
        other.id == id &&
        other.status == status &&
        other.subtotal == subtotal &&
        other.shipping == shipping &&
        other.tax == tax &&
        other.total == total &&
        other.address == address &&
        other.placedAt == placedAt &&
        other.estimatedDelivery == estimatedDelivery &&
        _sameList(other.items, items);
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    Object.hashAll(items),
    subtotal,
    shipping,
    tax,
    total,
    address,
    placedAt,
    estimatedDelivery,
  );

  @override
  String toString() =>
      'Order(id: $id, status: ${status.wireName}, total: $total, '
      'items: ${items.length})';

  static bool _sameList(List<CartItem> a, List<CartItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
