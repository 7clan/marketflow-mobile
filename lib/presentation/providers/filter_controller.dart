import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/product_filter.dart';

/// Active feed filters and sort order — the single source of truth the
/// product feed derives its query from.
class FilterState {
  const FilterState({
    this.categoryId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.sort = ProductSort.relevance,
  });

  /// Restricts the feed to one category, or `null` for all categories.
  final String? categoryId;

  /// Minimum price (inclusive) in USD.
  final double? minPrice;

  /// Maximum price (inclusive) in USD.
  final double? maxPrice;

  /// Hides out-of-stock products.
  final bool inStockOnly;

  /// Feed sort order.
  final ProductSort sort;

  /// `true` when no restriction is active (the default feed).
  bool get isEmpty =>
      categoryId == null &&
      minPrice == null &&
      maxPrice == null &&
      !inStockOnly;

  /// The domain filter the repository understands.
  ProductFilter get filter => ProductFilter(
    categoryId: categoryId,
    minPrice: minPrice,
    maxPrice: maxPrice,
    inStockOnly: inStockOnly,
  );

  /// Sentinel that lets [copyWith] distinguish "not provided" from
  /// "explicitly clear this field" for the nullable parameters.
  static const _unset = Object();

  FilterState copyWith({
    Object? categoryId = _unset,
    Object? minPrice = _unset,
    Object? maxPrice = _unset,
    bool? inStockOnly,
    ProductSort? sort,
  }) {
    return FilterState(
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      minPrice: identical(minPrice, _unset)
          ? this.minPrice
          : minPrice as double?,
      maxPrice: identical(maxPrice, _unset)
          ? this.maxPrice
          : maxPrice as double?,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FilterState &&
        other.categoryId == categoryId &&
        other.minPrice == minPrice &&
        other.maxPrice == maxPrice &&
        other.inStockOnly == inStockOnly &&
        other.sort == sort;
  }

  @override
  int get hashCode =>
      Object.hash(categoryId, minPrice, maxPrice, inStockOnly, sort);

  @override
  String toString() =>
      'FilterState(categoryId: $categoryId, minPrice: $minPrice, '
      'maxPrice: $maxPrice, inStockOnly: $inStockOnly, sort: $sort)';
}

/// Feed filters; every change re-runs the product feed (page 1).
final filterControllerProvider =
    NotifierProvider<FilterController, FilterState>(FilterController.new);

class FilterController extends Notifier<FilterState> {
  @override
  FilterState build() {
    // Filters persist while the user browses other tabs and returns.
    ref.keepAlive();
    return const FilterState();
  }

  /// Selects a category (pass `null` for "All").
  void setCategory(String? categoryId) =>
      state = state.copyWith(categoryId: categoryId);

  /// Sets the minimum price (pass `null` to clear).
  void setMinPrice(double? value) => state = state.copyWith(minPrice: value);

  /// Sets the maximum price (pass `null` to clear).
  void setMaxPrice(double? value) => state = state.copyWith(maxPrice: value);

  /// Toggles the in-stock-only filter.
  void setInStockOnly(bool value) => state = state.copyWith(inStockOnly: value);

  /// Changes the sort order.
  void setSort(ProductSort sort) => state = state.copyWith(sort: sort);

  /// Restores the default feed.
  void clear() => state = const FilterState();
}
