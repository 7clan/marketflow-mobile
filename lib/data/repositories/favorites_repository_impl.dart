import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../datasources/favorites_cache.dart';
import '../models/product_model.dart';

/// Favorites repository: server-backed, with a local id cache written
/// through after every sync so the UI can hydrate instantly on cold start.
class FavoritesRepositoryImpl implements FavoritesRepository {
  FavoritesRepositoryImpl({required this.apiClient, required this.cache});

  final ApiClient apiClient;

  /// Local id cache (write-through).
  final FavoritesCache cache;

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
  Future<List<Product>> listFavorites({CancelToken? cancelToken}) {
    return _guard(() async {
      final payload = await apiClient.getArray(
        '/favorites',
        cancelToken: cancelToken,
      );
      final products = <Product>[];
      for (final entry in payload) {
        if (entry is Map<String, dynamic>) {
          products.add(ProductModel.fromJson(entry).toDomain());
        }
      }
      return products;
    });
  }

  @override
  Future<void> addFavorite(String productId, {CancelToken? cancelToken}) {
    return _guard(
      () => apiClient.postObject(
        '/favorites/$productId',
        cancelToken: cancelToken,
      ),
    );
  }

  @override
  Future<void> removeFavorite(String productId, {CancelToken? cancelToken}) {
    return _guard(
      () => apiClient.deleteObject(
        '/favorites/$productId',
        cancelToken: cancelToken,
      ),
    );
  }

  @override
  Future<Set<String>> cachedFavoriteIds() {
    return _guard(cache.readIds);
  }

  @override
  Future<void> saveFavoriteIds(Set<String> ids) async {
    // Best-effort: a cache write failure must never fail a user action that
    // already succeeded server-side.
    try {
      await cache.writeIds(ids);
    } on CacheException {
      // Swallowed on purpose — see comment above.
    }
  }
}
