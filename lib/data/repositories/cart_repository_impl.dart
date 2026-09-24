import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/repositories/cart_repository.dart';
import '../datasources/cart_local_data_source.dart';

/// Cart repository: pure local persistence with defensive validation.
///
/// Every mutation that passes through [saveCart] is sanitized so a corrupt
/// or hand-edited cache can never produce an invalid cart:
/// * lines with a quantity below 1 are dropped;
/// * duplicate products collapse to the first occurrence;
/// * quantities are clamped to the per-line bound (`min(stock, 99)` when the
///   product is in stock, otherwise `99`).
class CartRepositoryImpl implements CartRepository {
  CartRepositoryImpl({required this.local});

  final CartLocalDataSource local;

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
  Future<List<CartItem>> loadCart() {
    return _guard(() async => _sanitize(await local.load()));
  }

  @override
  Future<void> saveCart(List<CartItem> items) {
    return _guard(() => local.save(_sanitize(items)));
  }

  @override
  Future<void> clear() => _guard(local.clear);

  /// Enforces the cart invariants (see class docs).
  List<CartItem> _sanitize(List<CartItem> items) {
    final seenProductIds = <String>{};
    final result = <CartItem>[];
    for (final item in items) {
      if (item.quantity < 1) continue;
      if (!seenProductIds.add(item.product.id)) continue;
      final bound = item.product.stock > 0
          ? (item.product.stock < CartItem.maxQuantity
                ? item.product.stock
                : CartItem.maxQuantity)
          : CartItem.maxQuantity;
      final quantity = item.quantity > bound ? bound : item.quantity;
      result.add(
        quantity == item.quantity ? item : item.copyWith(quantity: quantity),
      );
    }
    return result;
  }
}
