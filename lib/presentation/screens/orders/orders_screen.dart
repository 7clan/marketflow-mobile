import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/order.dart';
import '../../providers/orders_controller.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';

/// Order history: newest first, status chips, pull-to-refresh.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Orders')),
      body: switch (orders) {
        AsyncValue(hasValue: false) => SkeletonAnnouncer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SkeletonPulse(
              child: Column(
                children: [
                  for (var i = 0; i < 6; i++)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: SkeletonTile(),
                    ),
                ],
              ),
            ),
          ),
        ),
        AsyncError(:final error) => ErrorView(
          message: switch (error) {
            AppException exception => exception.message,
            _ => 'Something went wrong. Please try again.',
          },
          title: 'We could not load your orders',
          onRetry: () => ref.read(ordersControllerProvider.notifier).refresh(),
        ),
        AsyncValue(:final value!) =>
          value.isEmpty
              ? EmptyView(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders yet',
                  message:
                      'Your placed orders will show up here with live status.',
                  actionLabel: 'Start shopping',
                  onAction: () => context.go('/shop'),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(ordersControllerProvider.notifier).refresh(),
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: value.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final order = value[index];
                      return _OrderTile(order: order);
                    },
                  ),
                ),
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: () => context.push('/orders/${order.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: theme.colorScheme.onSecondaryContainer,
                  semanticLabel: 'Order',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${order.id}',
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.dateTime(order.placedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusChip(status: order.status),
                        Text(
                          '${order.itemCount} items',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.currency(order.total),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    semanticLabel: 'View order details',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
