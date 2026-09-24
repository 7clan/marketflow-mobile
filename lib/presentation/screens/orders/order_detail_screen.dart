import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/order.dart';
import '../../providers/orders_controller.dart';
import '../../widgets/error_view.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/status_chip.dart';

/// One order in full: status timeline, items, totals and shipping address.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncOrder = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: switch (asyncOrder) {
        AsyncValue(hasValue: false) => SkeletonAnnouncer(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SkeletonPulse(
              child: Column(
                children: [
                  const SkeletonBlock(height: 72, radius: 12),
                  const SizedBox(height: 16),
                  for (var i = 0; i < 4; i++)
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
          title: 'We could not load this order',
          onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
        ),
        AsyncValue(:final value!) => _OrderDetailBody(order: value),
      },
    );
  }
}

class _OrderDetailBody extends StatelessWidget {
  const _OrderDetailBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OrderHeader(order: order),
        const SizedBox(height: 16),
        if (order.status == OrderStatus.cancelled)
          _CancelledBanner()
        else
          _StatusTimeline(status: order.status),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Items',
          child: Column(
            children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: CachedNetworkImage(
                            imageUrl: item.product.imageUrls.first,
                            fit: BoxFit.cover,
                            memCacheWidth: 150,
                            placeholder: (_, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_, _, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${item.quantity} × ${item.product.title}',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Formatters.currency(item.lineTotal),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _TotalsCard(order: order),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Shipping address',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.address.fullName, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                '${order.address.street}\n'
                '${order.address.city}, ${order.address.state} '
                '${order.address.zip}\n'
                '${order.address.country}\n'
                '${order.address.phone}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _OrderHeader extends StatelessWidget {
  const _OrderHeader({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order ${order.id}',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Placed ${Formatters.dateTime(order.placedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              'Estimated delivery ${Formatters.date(order.estimatedDelivery)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// pending → processing → shipped → delivered, with the reached steps marked.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});

  final OrderStatus status;

  static const _steps = [
    (OrderStatus.pending, 'Placed', Icons.receipt_outlined),
    (OrderStatus.processing, 'Processing', Icons.inventory_2_outlined),
    (OrderStatus.shipped, 'Shipped', Icons.local_shipping_outlined),
    (OrderStatus.delivered, 'Delivered', Icons.mark_email_read_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIndex = status.index;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: i < currentIndex || i == currentIndex
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      i < currentIndex ? Icons.check_rounded : _steps[i].$3,
                      size: 18,
                      color: i <= currentIndex
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                      semanticLabel: _steps[i].$2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _steps[i].$2,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: i == currentIndex ? FontWeight.w700 : null,
                        color: i <= currentIndex
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (i == currentIndex)
                    Text(
                      'Current',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              if (i < _steps.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 17),
                  child: Container(
                    height: 16,
                    width: 2,
                    color: i < currentIndex
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cancel_outlined,
            color: theme.colorScheme.onErrorContainer,
            semanticLabel: 'Cancelled',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This order was cancelled.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _SectionCard(
      title: 'Totals',
      child: Column(
        children: [
          _row(context, 'Subtotal', Formatters.currency(order.subtotal)),
          _row(context, 'Shipping', Formatters.currency(order.shipping)),
          _row(context, 'Tax', Formatters.currency(order.tax)),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: Text('Total', style: theme.textTheme.titleMedium),
              ),
              Text(
                Formatters.currency(order.total),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
