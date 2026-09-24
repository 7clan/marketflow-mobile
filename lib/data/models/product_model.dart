import '../../domain/entities/product.dart';
import 'json_reader.dart';

/// Wire representation of a catalog product.
class ProductModel {
  const ProductModel({
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

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: JsonReader.requireString(json, 'id'),
      title: JsonReader.requireString(json, 'title'),
      description: JsonReader.requireString(json, 'description'),
      price: JsonReader.requireDouble(json, 'price'),
      compareAtPrice: JsonReader.optionalDouble(json, 'compareAtPrice'),
      imageUrls: JsonReader.requireStringList(json, 'imageUrls'),
      rating: JsonReader.requireDouble(json, 'rating'),
      reviewCount: JsonReader.requireInt(json, 'reviewCount'),
      stock: JsonReader.requireInt(json, 'stock'),
      categoryId: JsonReader.requireString(json, 'categoryId'),
      sellerName: JsonReader.requireString(json, 'sellerName'),
      isAvailable: JsonReader.requireBool(json, 'isAvailable'),
    );
  }

  final String id;
  final String title;
  final String description;

  /// Current selling price in USD.
  final double price;
  final double? compareAtPrice;
  final List<String> imageUrls;
  final double rating;
  final int reviewCount;
  final int stock;
  final String categoryId;
  final String sellerName;
  final bool isAvailable;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'price': price,
    'compareAtPrice': compareAtPrice,
    'imageUrls': imageUrls,
    'rating': rating,
    'reviewCount': reviewCount,
    'stock': stock,
    'categoryId': categoryId,
    'sellerName': sellerName,
    'isAvailable': isAvailable,
  };

  Product toDomain() => Product(
    id: id,
    title: title,
    description: description,
    price: price,
    compareAtPrice: compareAtPrice,
    imageUrls: List<String>.unmodifiable(imageUrls),
    rating: rating,
    reviewCount: reviewCount,
    stock: stock,
    categoryId: categoryId,
    sellerName: sellerName,
    isAvailable: isAvailable,
  );

  static ProductModel fromDomain(Product product) => ProductModel(
    id: product.id,
    title: product.title,
    description: product.description,
    price: product.price,
    compareAtPrice: product.compareAtPrice,
    imageUrls: product.imageUrls,
    rating: product.rating,
    reviewCount: product.reviewCount,
    stock: product.stock,
    categoryId: product.categoryId,
    sellerName: product.sellerName,
    isAvailable: product.isAvailable,
  );
}
