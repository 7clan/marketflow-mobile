import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/paginated_result.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_filter.dart';
import '../../domain/repositories/product_repository.dart';
import '../models/category_model.dart';
import '../models/paginated_result_model.dart';
import '../models/product_model.dart';

/// Product catalog repository over the real HTTP pipeline.
///
/// All transport/parse failures are converted to [AppException]s before they
/// can escape.
class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl({required this.apiClient});

  final ApiClient apiClient;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw ErrorMapper.map(error, stackTrace: stackTrace);
    }
  }

  @override
  Future<PaginatedResult<Product>> getProducts({
    required int page,
    required int pageSize,
    ProductFilter? filter,
    ProductSort sort = ProductSort.relevance,
    String? query,
    CancelToken? cancelToken,
  }) {
    return _guard(() async {
      final payload = await apiClient.getObject(
        '/products',
        queryParameters: _buildQuery(
          page: page,
          pageSize: pageSize,
          filter: filter,
          sort: sort,
          query: query,
        ),
        cancelToken: cancelToken,
      );
      return PaginatedResultModel.fromJson(
        payload,
        (json) => ProductModel.fromJson(json).toDomain(),
      ).toDomain();
    });
  }

  @override
  Future<Product> getProduct(String id, {CancelToken? cancelToken}) {
    return _guard(() async {
      final payload = await apiClient.getObject(
        '/products/$id',
        cancelToken: cancelToken,
      );
      return ProductModel.fromJson(payload).toDomain();
    });
  }

  @override
  Future<List<Category>> getCategories({CancelToken? cancelToken}) {
    return _guard(() async {
      final payload = await apiClient.getArray(
        '/categories',
        cancelToken: cancelToken,
      );
      return [
        for (final entry in payload)
          if (entry is Map<String, dynamic>)
            CategoryModel.fromJson(entry).toDomain(),
      ];
    });
  }

  static Map<String, dynamic> _buildQuery({
    required int page,
    required int pageSize,
    required ProductFilter? filter,
    required ProductSort sort,
    required String? query,
  }) {
    final queryParameters = <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
      'sort': sort.wireValue,
    };
    final trimmedQuery = query?.trim();
    if (trimmedQuery != null && trimmedQuery.isNotEmpty) {
      queryParameters['q'] = trimmedQuery;
    }
    if (filter == null) return queryParameters;
    final categoryId = filter.categoryId;
    if (categoryId != null && categoryId.isNotEmpty) {
      queryParameters['category'] = categoryId;
    }
    final minPrice = filter.minPrice;
    if (minPrice != null) queryParameters['minPrice'] = minPrice;
    final maxPrice = filter.maxPrice;
    if (maxPrice != null) queryParameters['maxPrice'] = maxPrice;
    if (filter.inStockOnly) queryParameters['inStock'] = 'true';
    return queryParameters;
  }
}
