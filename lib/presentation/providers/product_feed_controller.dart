import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/product.dart';
import 'filter_controller.dart';
import 'infrastructure_providers.dart';

/// Rendered state of the product feed.
class ProductFeedState {
  const ProductFeedState({
    required this.items,
    required this.page,
    required this.hasMore,
    required this.totalItems,
    this.isLoadingMore = false,
    this.error,
  });

  /// Products loaded so far (page 1 + appended pages).
  final List<Product> items;

  /// Last loaded page number (1-based).
  final int page;

  /// `true` when at least one more page exists.
  final bool hasMore;

  /// Total products matching the active filters (server-side count).
  final int totalItems;

  /// `true` while the next page is being appended.
  final bool isLoadingMore;

  /// Error of the last **load-more** attempt — the list stays visible with a
  /// retry footer instead of being replaced by a full-screen error.
  /// Refresh errors surface as the provider's `AsyncError` instead.
  final AppException? error;

  /// `true` for the "no results" empty state (only when nothing failed).
  bool get isEmpty => items.isEmpty && error == null;

  ProductFeedState copyWith({
    List<Product>? items,
    int? page,
    bool? hasMore,
    int? totalItems,
    bool? isLoadingMore,
    Object? error = _unset,
  }) {
    return ProductFeedState(
      items: items ?? this.items,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      totalItems: totalItems ?? this.totalItems,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: identical(error, _unset) ? this.error : error as AppException?,
    );
  }

  /// Sentinel for [copyWith]'s nullable clear.
  static const _unset = Object();
}

/// The product feed: page 1 + appended pages + retry states.
///
/// The feed derives from [filterControllerProvider] — any filter/sort change
/// re-runs page 1. Stale in-flight responses (filter changed mid-request)
/// drop themselves via a request sequence number.
final productFeedProvider =
    AsyncNotifierProvider<ProductFeedController, ProductFeedState>(
      ProductFeedController.new,
    );

class ProductFeedController extends AsyncNotifier<ProductFeedState> {
  /// Incremented whenever the feed restarts; lets in-flight "load more"
  /// responses detect that they belong to an outdated query and drop
  /// themselves instead of corrupting the new results.
  int _requestSeq = 0;

  @override
  Future<ProductFeedState> build() async {
    _requestSeq++;
    final filters = ref.watch(filterControllerProvider);
    final repository = ref.read(productRepositoryProvider);
    final pageSize = ref.read(appConfigProvider).pageSize;
    final result = await repository.getProducts(
      page: 1,
      pageSize: pageSize,
      filter: filters.filter,
      sort: filters.sort,
    );
    return ProductFeedState(
      items: result.items,
      page: result.page,
      hasMore: result.hasMore,
      totalItems: result.totalItems,
    );
  }

  /// Pull-to-refresh: restart from page 1 with the active filters.
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Appends the next page (guards: no more pages, already loading, no
  /// successful first page yet).
  Future<void> loadNextPage() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;

    final seq = _requestSeq;
    final filters = ref.read(filterControllerProvider);
    final repository = ref.read(productRepositoryProvider);
    final pageSize = ref.read(appConfigProvider).pageSize;
    final nextPage = current.page + 1;

    state = AsyncData(current.copyWith(isLoadingMore: true, error: null));
    try {
      final result = await repository.getProducts(
        page: nextPage,
        pageSize: pageSize,
        filter: filters.filter,
        sort: filters.sort,
      );
      if (seq != _requestSeq) return; // filters changed mid-flight
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...result.items],
          page: result.page,
          hasMore: result.hasMore,
          totalItems: result.totalItems,
          isLoadingMore: false,
          error: null,
        ),
      );
    } on AppException catch (error) {
      if (seq != _requestSeq) return;
      state = AsyncData(current.copyWith(isLoadingMore: false, error: error));
    }
  }
}
