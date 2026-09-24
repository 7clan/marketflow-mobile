import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/product.dart';
import '../../providers/favorite_products_provider.dart';
import '../../providers/favorites_controller.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/price_text.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/skeleton.dart';

/// The favorites tab: saved products with swipe-to-remove (optimistic, with
/// undo) and pull-to-refresh (server sync + snapshot reload).
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesControllerProvider);
    final products = ref.watch(favoriteProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        actions: [
          IconButton(
            tooltip: 'Refresh favorites',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _refresh(ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _body(context, ref, favorites, products),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    await ref.read(favoritesControllerProvider.notifier).syncFromServer();
    await ref.read(favoriteProductsProvider.notifier).reload();
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    FavoritesState favorites,
    List<Product> products,
  ) {
    if (favorites.isLoading && products.isEmpty) {
      return SkeletonAnnouncer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SkeletonPulse(
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: SkeletonTile(),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (products.isEmpty) {
      final syncFailed = favorites.error != null;
      return Column(
        children: [
          if (syncFailed) _SyncErrorBanner(message: favorites.error!.message),
          Expanded(
            child: EmptyView(
              icon: Icons.favorite_border_rounded,
              title: syncFailed
                  ? 'We could not load your favorites'
                  : 'No favorites yet',
              message: syncFailed
                  ? 'Pull to refresh once you are back online.'
                  : 'Tap the heart on any product to save it here.',
              actionLabel: syncFailed ? 'Browse products' : 'Start shopping',
              onAction: () => context.go('/shop'),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: products.length + (favorites.error != null ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == products.length) {
            return _SyncErrorBanner(message: favorites.error!.message);
          }
          final product = products[index];
          return _FavoriteRow(
            product: product,
            isFavorite: favorites.isFavorite(product.id),
          );
        },
      ),
    );
  }
}

/// Non-blocking banner for a failed sync (the cached list stays usable).
class _SyncErrorBanner extends ConsumerWidget {
  const _SyncErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Dismiss error',
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onErrorContainer,
                ),
                onPressed: () =>
                    ref.read(favoritesControllerProvider.notifier).clearError(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One saved product: swipe (or heart) removes it — optimistically, with
/// undo.
class _FavoriteRow extends ConsumerWidget {
  const _FavoriteRow({required this.product, required this.isFavorite});

  final Product product;
  final bool isFavorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('favorite-${product.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onErrorContainer,
          semanticLabel: 'Remove from favorites',
        ),
      ),
      onDismissed: (_) => _remove(context, ref),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}', extra: product),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CachedNetworkImage(
                    imageUrl: product.imageUrls.first,
                    fit: BoxFit.cover,
                    memCacheWidth: 220,
                    placeholder: (_, _) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_, _, _) => ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                        semanticLabel: 'Image unavailable',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    RatingStars(
                      rating: product.rating,
                      reviewCount: product.reviewCount,
                      starSize: 14,
                    ),
                    const SizedBox(height: 4),
                    PriceText(
                      price: product.price,
                      compareAtPrice: product.compareAtPrice,
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Semantics(
                label: 'Remove ${product.title} from favorites',
                button: true,
                child: IconButton(
                  tooltip: 'Remove from favorites',
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () => _remove(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _remove(BuildContext context, WidgetRef ref) {
    // Optimistic: the list updates immediately; the controller rolls back
    // if the server rejects.
    ref.read(favoritesControllerProvider.notifier).removeFavorite(product.id);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${product.title} removed from favorites'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => ref
                .read(favoritesControllerProvider.notifier)
                .addFavorite(product.id),
          ),
        ),
      );
  }
}
