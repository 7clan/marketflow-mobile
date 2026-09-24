import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/product.dart';
import '../../providers/recent_searches_provider.dart';
import '../../providers/search_controller.dart';
import '../../widgets/empty_view.dart';
import '../../widgets/error_view.dart';
import '../../widgets/favorite_button.dart';
import '../../widgets/price_text.dart';
import '../../widgets/rating_stars.dart';
import '../../widgets/search_field.dart';
import '../../widgets/skeleton.dart';

/// Full-screen product search.
///
/// * keystrokes stream into the debounced, cancellable search controller;
/// * `isSearching` renders a result-list skeleton;
/// * failures render a retry error state (mapped [AppException] copy);
/// * the idle state shows persisted recent queries;
/// * results are lazy list rows — tapping opens the product detail.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Restore the last committed query into the field.
    final query = ref.read(searchControllerProvider).query;
    if (query.isNotEmpty) _textController.text = query;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    ref.read(searchControllerProvider.notifier).onQueryChanged(value);
  }

  void _onSubmitted(String value) {
    ref.read(searchControllerProvider.notifier).onQueryChanged(value);
    ref.read(recentSearchesProvider.notifier).add(value);
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: SearchField(
          controller: _textController,
          onChanged: _onChanged,
          onSubmitted: _onSubmitted,
          autofocus: true,
        ),
        titleSpacing: 0,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        child: _bodyFor(search),
      ),
    );
  }

  Widget _bodyFor(SearchState search) {
    if (!search.hasQuery) {
      return _RecentSearches(
        onPick: (query) {
          _textController.text = query;
          _onChanged(query);
        },
      );
    }
    if (search.isSearching) {
      return SkeletonAnnouncer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
      );
    }

    final error = search.error;
    if (error != null) {
      return ErrorView(
        key: const ValueKey('search-error'),
        title: 'Search failed',
        message: error.message,
        onRetry: () => ref.read(searchControllerProvider.notifier).refresh(),
      );
    }

    if (search.isEmpty) {
      return EmptyView(
        key: const ValueKey('search-empty'),
        icon: Icons.search_off_rounded,
        title: 'No results',
        message: 'Nothing matched "${search.query}". Try a different term.',
      );
    }

    return ListView.builder(
      key: ValueKey('search-results-${search.query}'),
      itemCount: search.results.length,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemBuilder: (context, index) {
        final product = search.results[index];
        return _SearchResultRow(product: product);
      },
    );
  }
}

/// One search hit: thumbnail, title, rating and price.
class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.push('/product/${product.id}', extra: product),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
            FavoriteButton(product: product),
          ],
        ),
      ),
    );
  }
}

/// Idle state: the persisted recent queries with per-entry removal.
class _RecentSearches extends ConsumerWidget {
  const _RecentSearches({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recents = ref.watch(recentSearchesProvider);

    if (recents.isEmpty) {
      return EmptyView(
        key: const ValueKey('search-idle'),
        icon: Icons.search_rounded,
        title: 'Find it on MarketFlow',
        message:
            'Search by product name, brand or category — results appear '
            'as you type.',
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Recent searches',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(recentSearchesProvider.notifier).clear(),
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        for (final query in recents)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove $query from recent searches',
              icon: const Icon(Icons.close_rounded),
              onPressed: () =>
                  ref.read(recentSearchesProvider.notifier).remove(query),
            ),
            onTap: () => onPick(query),
          ),
      ],
    );
  }
}
