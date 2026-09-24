/// Feed narrowing criteria (everything except sort order).
class ProductFilter {
  const ProductFilter({
    this.categoryId,
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
  });

  /// Restricts results to one category, or `null` for all categories.
  final String? categoryId;

  /// Minimum price (inclusive), in USD.
  final double? minPrice;

  /// Maximum price (inclusive), in USD.
  final double? maxPrice;

  /// When `true`, hides out-of-stock products.
  final bool inStockOnly;

  /// `true` when nothing is restricted (the default feed).
  bool get isEmpty =>
      categoryId == null &&
      minPrice == null &&
      maxPrice == null &&
      !inStockOnly;

  ProductFilter copyWith({
    Object? categoryId = _unset,
    Object? minPrice = _unset,
    Object? maxPrice = _unset,
    bool? inStockOnly,
  }) {
    return ProductFilter(
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
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProductFilter &&
        other.categoryId == categoryId &&
        other.minPrice == minPrice &&
        other.maxPrice == maxPrice &&
        other.inStockOnly == inStockOnly;
  }

  @override
  int get hashCode => Object.hash(categoryId, minPrice, maxPrice, inStockOnly);

  @override
  String toString() =>
      'ProductFilter(categoryId: $categoryId, minPrice: $minPrice, '
      'maxPrice: $maxPrice, inStockOnly: $inStockOnly)';

  /// Sentinel that lets [copyWith] distinguish "not provided" from
  /// "explicitly clear this field" for the nullable parameters.
  static const _unset = Object();
}

/// Feed sort orders understood by the backend.
enum ProductSort {
  relevance('relevance'),
  newest('newest'),
  priceAsc('price_asc'),
  priceDesc('price_desc'),
  rating('rating');

  const ProductSort(this.wireValue);

  /// Value used on the wire (query parameter `sort`).
  final String wireValue;

  /// Parses the wire value; returns `null` for unknown values.
  static ProductSort? fromWireValue(String? value) {
    if (value == null) return null;
    for (final sort in ProductSort.values) {
      if (sort.wireValue == value) return sort;
    }
    return null;
  }
}
