/// A product catalog category (e.g. Electronics).
class Category {
  const Category({required this.id, required this.name, this.productCount = 0});

  final String id;
  final String name;

  /// How many products the catalog holds in this category, when known.
  final int productCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Category &&
        other.id == id &&
        other.name == name &&
        other.productCount == productCount;
  }

  @override
  int get hashCode => Object.hash(id, name, productCount);

  @override
  String toString() =>
      'Category(id: $id, name: $name, productCount: $productCount)';
}
