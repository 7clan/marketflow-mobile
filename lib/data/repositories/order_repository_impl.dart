import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/address.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../models/address_model.dart';
import '../models/order_model.dart';

/// Order repository over the real HTTP pipeline.
///
/// Checkout conflicts (items out of stock) surface as [ConflictException]
/// carrying the conflicting product ids.
class OrderRepositoryImpl implements OrderRepository {
  OrderRepositoryImpl({required this.apiClient});

  final ApiClient apiClient;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw ErrorMapper.map(error, stackTrace: stackTrace);
    }
  }

  @override
  Future<Order> placeOrder({
    required List<CartItem> items,
    required Address address,
    required PaymentMethod paymentMethod,
  }) {
    return _guard(() async {
      final payload = await apiClient.postObject(
        '/checkout',
        data: {
          'items': [
            for (final item in items)
              {'productId': item.product.id, 'quantity': item.quantity},
          ],
          'address': AddressModel.fromDomain(address).toJson(),
          'paymentMethod': paymentMethod.wireName,
        },
      );
      return OrderModel.fromJson(payload).toDomain();
    });
  }

  @override
  Future<List<Order>> getOrders({CancelToken? cancelToken}) {
    return _guard(() async {
      final payload = await apiClient.getArray(
        '/orders',
        cancelToken: cancelToken,
      );
      final orders = <Order>[];
      for (final entry in payload) {
        if (entry is Map<String, dynamic>) {
          orders.add(OrderModel.fromJson(entry).toDomain());
        }
      }
      return orders;
    });
  }

  @override
  Future<Order> getOrder(String id, {CancelToken? cancelToken}) {
    return _guard(() async {
      final payload = await apiClient.getObject(
        '/orders/$id',
        cancelToken: cancelToken,
      );
      return OrderModel.fromJson(payload).toDomain();
    });
  }
}
