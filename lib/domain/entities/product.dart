/// A catalog product as shown in the feed, search results and detail pages.
class Product {
  const Product({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.compareAtPrice,
    required this.imageUrls,
    required this.rating,
    required this.reviewCount,
    required this.stock,
    required this.categoryId,
    required this.sellerName,
    required this.isAvailable,
  });

  final String id;
  final String title;
  final String description;

  /// Current selling price in USD.
  final double price;

  /// Original price when the product is discounted, otherwise `null`.
  final double? compareAtPrice;

  /// At least one image URL (guaranteed by construction from trusted data).
  final List<String> imageUrls;

  /// Average rating, 0–5.
  final double rating;
  final int reviewCount;

  /// Units currently in stock (`0` → out of stock).
  final int stock;

  final String categoryId;
  final String sellerName;

  /// Whether the product can be purchased right now.
  final bool isAvailable;

  /// `true` when a compare-at price is set above the current price.
  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  /// Whole-percent discount versus the compare-at price, when discounted.
  int? get discountPercent {
    if (!hasDiscount || compareAtPrice! <= 0) return null;
    return ((1 - price / compareAtPrice!) * 100).round();
  }

  /// `true` when the item cannot be added to the cart.
  bool get isOutOfStock => stock <= 0 || !isAvailable;

  Product copyWith({
    String? id,
    String? title,
    String? description,
    double? price,
    double? compareAtPrice,
    List<String>? imageUrls,
    double? rating,
    int? reviewCount,
    int? stock,
    String? categoryId,
    String? sellerName,
    bool? isAvailable,
  }) {
    return Product(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      compareAtPrice: compareAtPrice ?? this.compareAtPrice,
      imageUrls: imageUrls ?? this.imageUrls,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      stock: stock ?? this.stock,
      categoryId: categoryId ?? this.categoryId,
      sellerName: sellerName ?? this.sellerName,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Product &&
        other.id == id &&
        other.title == title &&
        other.description == description &&
        other.price == price &&
        other.compareAtPrice == compareAtPrice &&
        other.rating == rating &&
        other.reviewCount == reviewCount &&
        other.stock == stock &&
        other.categoryId == categoryId &&
        other.sellerName == sellerName &&
        other.isAvailable == isAvailable &&
        _sameList(other.imageUrls, imageUrls);
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    price,
    compareAtPrice,
    Object.hashAll(imageUrls),
    rating,
    reviewCount,
    stock,
    categoryId,
    sellerName,
    isAvailable,
  );

  @override
  String toString() =>
      'Product(id: $id, title: $title, price: $price, stock: $stock)';

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
