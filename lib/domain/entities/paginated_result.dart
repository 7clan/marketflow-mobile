/// One page of a server-side paginated collection.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalItems,
    required this.hasMore,
  });

  final List<T> items;

  /// 1-based page number this result represents.
  final int page;
  final int totalPages;
  final int totalItems;

  /// `true` when at least one more page exists.
  final bool hasMore;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PaginatedResult<T> &&
        other.page == page &&
        other.totalPages == totalPages &&
        other.totalItems == totalItems &&
        other.hasMore == hasMore &&
        _sameList(other.items, items);
  }

  @override
  int get hashCode =>
      Object.hash(page, totalPages, totalItems, hasMore, Object.hashAll(items));

  @override
  String toString() =>
      'PaginatedResult(page: $page, totalPages: $totalPages, '
      'totalItems: $totalItems, items: ${items.length})';

  static bool _sameList<E>(List<E> a, List<E> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
