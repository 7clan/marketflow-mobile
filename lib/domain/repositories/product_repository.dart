import 'package:dio/dio.dart';

import '../entities/category.dart';
import '../entities/paginated_result.dart';
import '../entities/product.dart';
import '../entities/product_filter.dart';

/// Product catalog access contract (feed, search, filters, details).
abstract interface class ProductRepository {
  /// Fetches one page of products matching [filter], ordered by [sort],
  /// optionally narrowed by a free-text [query].
  Future<PaginatedResult<Product>> getProducts({
    required int page,
    required int pageSize,
    ProductFilter? filter,
    ProductSort sort = ProductSort.relevance,
    String? query,
    CancelToken? cancelToken,
  });

  /// Fetches a single product.
  ///
  /// Throws [NotFoundException] for unknown ids.
  Future<Product> getProduct(String id, {CancelToken? cancelToken});

  /// Fetches the category list.
  Future<List<Category>> getCategories({CancelToken? cancelToken});
}
