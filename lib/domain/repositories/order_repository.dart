import 'package:dio/dio.dart';

import '../entities/address.dart';
import '../entities/cart_item.dart';
import '../entities/order.dart';

/// Order placement and history contract.
abstract interface class OrderRepository {
  /// Places an order for the cart [items] shipped to [address].
  ///
  /// Throws [ValidationException] when the cart is empty or the address is
  /// incomplete, [BadRequestException] for unknown products and
  /// [ConflictException] when items went out of stock (the conflicting ids
  /// are carried on the exception).
  Future<Order> placeOrder({
    required List<CartItem> items,
    required Address address,
    required PaymentMethod paymentMethod,
  });

  /// Lists the signed-in user's orders, newest first.
  Future<List<Order>> getOrders({CancelToken? cancelToken});

  /// Fetches a single order.
  ///
  /// Throws [NotFoundException] for unknown ids.
  Future<Order> getOrder(String id, {CancelToken? cancelToken});
}
