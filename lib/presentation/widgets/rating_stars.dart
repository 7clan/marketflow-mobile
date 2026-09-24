import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';

/// Five-star rating row: filled/half/empty stars, average and review count.
///
/// A single [Semantics] label summarizes the whole row ("Rated 4.6 out of 5,
/// 128 reviews") instead of announcing six separate widgets.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.reviewCount,
    this.showValue = true,
    this.starSize = 16,
  });

  /// Average rating, 0–5 (values outside are clamped for rendering).
  final double rating;

  final int? reviewCount;

  /// `false` renders the stars alone (e.g. inside dense list rows).
  final bool showValue;

  final double starSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clamped = rating.clamp(0.0, 5.0);
    final reviews = reviewCount;

    return Semantics(
      label: reviews == null
          ? 'Rated ${Formatters.rating(clamped)} out of 5'
          : 'Rated ${Formatters.rating(clamped)} out of 5, '
                '$reviews reviews',
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        runSpacing: 2,
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              _iconFor(clamped - i),
              size: starSize,
              color: theme.colorScheme.tertiary,
              semanticLabel: '', // the row-level label covers the stars
            ),
          if (showValue)
            Text(
              Formatters.rating(clamped),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (showValue && reviews != null)
            Text(
              '($reviews)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }

  IconData _iconFor(double remaining) {
    if (remaining >= 0.75) return Icons.star_rounded;
    if (remaining >= 0.25) return Icons.star_half_rounded;
    return Icons.star_outline_rounded;
  }
}
