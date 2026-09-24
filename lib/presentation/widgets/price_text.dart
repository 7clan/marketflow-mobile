import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// Price with an optional strike-through compare-at price.
///
/// Rendered inside a [Wrap] so large text scales wrap the compare-at price
/// to the next line instead of overflowing the row.
class PriceText extends StatelessWidget {
  const PriceText({
    super.key,
    required this.price,
    this.compareAtPrice,
    this.style,
  });

  final double price;
  final double? compareAtPrice;

  /// Style of the current price; the compare-at price derives its own
  /// smaller, de-emphasized style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ?? theme.textTheme.titleMedium;
    final hasCompareAt = compareAtPrice != null && compareAtPrice! > price;

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          Formatters.currency(price),
          style: base?.copyWith(
            fontWeight: FontWeight.w700,
            color: hasCompareAt ? theme.colorScheme.primary : base.color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasCompareAt)
          Text(
            Formatters.currency(compareAtPrice!),
            style: theme.textTheme.bodySmall?.copyWith(
              decoration: TextDecoration.lineThrough,
              decorationThickness: 2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}
