import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/product.dart';
import '../providers/favorites_controller.dart';

/// Optimistic favorite heart toggle.
///
/// * reads only the membership bit for [product] (one [Provider.select]),
///   so a feed of hundreds of cards rebuilds at most one heart per toggle;
/// * toggling updates the UI instantly — the controller rolls back and
///   surfaces `FavoritesState.error` when the server rejects it (announced
///   by the hosting screen via SnackBar);
/// * 48dp touch target with an explicit Semantics label.
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({super.key, required this.product, this.color});

  final Product product;

  /// Overrides the icon color (e.g. white on top of imagery).
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFavorite = ref.watch(
      favoritesControllerProvider.select(
        (state) => state.isFavorite(product.id),
      ),
    );

    final iconColor = color ?? (isFavorite ? theme.colorScheme.primary : null);

    return Semantics(
      label: isFavorite
          ? 'Remove ${product.title} from favorites'
          : 'Add ${product.title} to favorites',
      button: true,
      child: IconButton(
        tooltip: isFavorite ? 'Remove from favorites' : 'Add to favorites',
        onPressed: () {
          final controller = ref.read(favoritesControllerProvider.notifier);
          if (isFavorite) {
            controller.removeFavorite(product.id);
          } else {
            controller.addFavorite(product.id);
          }
        },
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.88),
        ),
        icon: Icon(
          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: iconColor,
        ),
      ),
    );
  }
}
