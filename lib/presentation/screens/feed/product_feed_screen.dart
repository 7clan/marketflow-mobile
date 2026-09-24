import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/category.dart';
import '../../providers/categories_provider.dart';
import '../../providers/favorites_controller.dart';
import '../../providers/filter_controller.dart';
import '../../providers/product_feed_controller.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/product_card.dart';
import '../../widgets/skeleton.dart';
import 'feed_filter_sheet.dart';

/// The shop tab: paginated product feed.
///
/// * pull-to-refresh restarts page 1 with the active filters;
/// * infinite scroll appends pages from a scroll-position listener (the
///   controller itself guards concurrent and stale requests);
/// * load-more failures render as an in-list retry footer, not a
///   full-screen error;
/// * first-page failures render as a full-screen error + retry.
class ProductFeedScreen extends ConsumerStatefulWidget {
  const ProductFeedScreen({super.key});

  @override
  ConsumerState<ProductFeedScreen> createState() => _ProductFeedScreenState();
}

class _ProductFeedScreenState extends ConsumerState<ProductFeedScreen> {
  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(productFeedProvider);
    final filters = ref.watch(filterControllerProvider);
    final controller = ref.read(productFeedProvider.notifier);

    // Announce optimistic favorite rollbacks: the controller has already
    // restored the previous state — the user needs to know why.
    ref.listen(favoritesControllerProvider.select((state) => state.error), (
      previous,
      next,
    ) {
      if (next != null) {
        ref.read(favoritesControllerProvider.notifier).clearError();
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('MarketFlow'),
        actions: [
          IconButton(
            tooltip: 'Search products',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            tooltip: 'Filters and sorting',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const FeedFilterSheet(),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: switch (feed) {
        // First page in flight (no previous data yet) — skeleton grid.
        AsyncValue(hasValue: false) => const _FeedSkeleton(),
        AsyncError(:final error) => ErrorView(
          message: switch (error) {
            AppException exception => exception.message,
            _ => 'Something went wrong. Please try again.',
          },
          title: 'We could not load the feed',
          onRetry: controller.refresh,
        ),
        AsyncValue(:final value!) => _FeedContent(
          state: value,
          filtersActive: !filters.isEmpty,
          onRefresh: controller.refresh,
          onLoadMore: controller.loadNextPage,
          onClearFilters: () =>
              ref.read(filterControllerProvider.notifier).clear(),
        ),
      },
    );
  }
}

/// Skeleton grid shown while the first page loads.
class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonAnnouncer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SkeletonPulse(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
            ),
            itemCount: 6,
            itemBuilder: (context, index) => const Card(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: SkeletonProductCard(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The loaded feed: filter-chip header + grid + pagination footer.
class _FeedContent extends StatelessWidget {
  const _FeedContent({
    required this.state,
    required this.filtersActive,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onClearFilters,
  });

  static const _preloadExtent = 600.0;

  final ProductFeedState state;
  final bool filtersActive;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    if (state.isEmpty) {
      return EmptyView(
        icon: Icons.search_off_rounded,
        title: filtersActive
            ? 'Nothing matches your filters'
            : 'No products right now',
        message: filtersActive
            ? 'Try widening the price range or clearing the filters.'
            : 'The marketplace is restocking. Pull to refresh in a moment.',
        actionLabel: filtersActive ? 'Clear filters' : null,
        onAction: filtersActive ? onClearFilters : null,
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (notification.depth == 0 &&
            metrics.pixels >= metrics.maxScrollExtent - _preloadExtent) {
          onLoadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _FilterHeader(totalItems: state.totalItems),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.72,
                ),
                itemCount: state.items.length,
                itemBuilder: (context, index) =>
                    ProductCard(product: state.items[index]),
              ),
            ),
            SliverToBoxAdapter(
              child: _LoadMoreFooter(state: state, onRetry: onLoadMore),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result count + chips for the active filters (category / stock / price).
class _FilterHeader extends ConsumerWidget {
  const _FilterHeader({required this.totalItems});

  final int totalItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final filters = ref.watch(filterControllerProvider);
    final categories = ref.watch(categoriesProvider).value;

    String? categoryName;
    if (filters.categoryId != null) {
      for (final category in categories ?? const <Category>[]) {
        if (category.id == filters.categoryId) categoryName = category.name;
      }
    }

    final chips = <Widget>[
      if (filters.categoryId != null)
        InputChip(
          avatar: const Icon(Icons.category_outlined, size: 18),
          label: Text(categoryName ?? 'Category'),
          onDeleted: () =>
              ref.read(filterControllerProvider.notifier).setCategory(null),
          tooltip: 'Clear category filter',
        ),
      if (filters.inStockOnly)
        const InputChip(
          avatar: Icon(Icons.inventory_2_outlined, size: 18),
          label: Text('In stock'),
        ),
      if (filters.minPrice != null || filters.maxPrice != null)
        InputChip(
          avatar: const Icon(Icons.payments_outlined, size: 18),
          label: Text(priceLabel(filters)),
          onDeleted: () {
            final controller = ref.read(filterControllerProvider.notifier);
            controller.setMinPrice(null);
            controller.setMaxPrice(null);
          },
          tooltip: 'Clear price filter',
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
          const SizedBox(width: 8),
          Text(
            '$totalItems items',
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

  static String priceLabel(FilterState filters) {
    final min = filters.minPrice;
    final max = filters.maxPrice;
    if (min != null && max != null) {
      return '${Formatters.compactCurrency(min)} – '
          '${Formatters.compactCurrency(max)}';
    }
    if (min != null) return 'From ${Formatters.compactCurrency(min)}';
    return 'Up to ${Formatters.compactCurrency(max ?? 0)}';
  }
}

/// Pagination footer: progress, retry or the end-of-list note.
class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.state, required this.onRetry});

  final ProductFeedState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            height: 26,
            width: 26,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }

    final error = state.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!state.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            "You've reached the end of the catalog",
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // More pages exist: the scroll listener loads them as the user nears
    // the bottom; a light hint renders meanwhile.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          'Keep scrolling for more',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
