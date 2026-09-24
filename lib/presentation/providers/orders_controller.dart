import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/order.dart';
import 'infrastructure_providers.dart';

/// The signed-in user's order history (newest first).
///
/// Rebuilt (re-fetched) whenever the orders screen is (re-)entered — order
/// status and history should always be fresh; pull-to-refresh is also
/// available via [refresh].
final ordersControllerProvider =
    AsyncNotifierProvider<OrdersController, List<Order>>(OrdersController.new);

class OrdersController extends AsyncNotifier<List<Order>> {
  @override
  Future<List<Order>> build() {
    return ref.watch(orderRepositoryProvider).getOrders();
  }

  /// Pull-to-refresh: re-fetches the list.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}

/// Full detail of a single order (per-id, auto-disposed with its listener).
final orderDetailProvider = FutureProvider.family<Order, String>((ref, id) {
  return ref.watch(orderRepositoryProvider).getOrder(id);
});
