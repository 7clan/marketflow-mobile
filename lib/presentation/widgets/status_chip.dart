import 'package:flutter/material.dart';

import '../../../domain/entities/order.dart';

/// Order status chip with per-status color and an explicit Semantics label.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final (label, background, foreground) = switch (status) {
      OrderStatus.pending => (
        'Pending',
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      OrderStatus.processing => (
        'Processing',
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      OrderStatus.shipped => (
        'Shipped',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      OrderStatus.delivered => ('Delivered', scheme.primary, scheme.onPrimary),
      OrderStatus.cancelled => (
        'Cancelled',
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };

    return Semantics(
      label: 'Order status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
