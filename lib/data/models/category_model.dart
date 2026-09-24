import '../../domain/entities/category.dart';
import 'json_reader.dart';

/// Wire representation of a product category.
class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    this.productCount = 0,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: JsonReader.requireString(json, 'id'),
      name: JsonReader.requireString(json, 'name'),
      productCount: JsonReader.optionalInt(json, 'productCount') ?? 0,
    );
  }

  final String id;
  final String name;
  final int productCount;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'productCount': productCount,
  };

  Category toDomain() =>
      Category(id: id, name: name, productCount: productCount);
}
