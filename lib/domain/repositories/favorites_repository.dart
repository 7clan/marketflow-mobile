import 'package:dio/dio.dart';

import '../entities/product.dart';

/// Server-backed favorites, with a local id cache for instant cold starts.
abstract interface class FavoritesRepository {
  /// Lists the user's favorite products (requires authentication).
  Future<List<Product>> listFavorites({CancelToken? cancelToken});

  /// Marks a product as favorite (requires authentication).
  ///
  /// Throws [NotFoundException] for unknown product ids.
  Future<void> addFavorite(String productId, {CancelToken? cancelToken});

  /// Removes a product from favorites (requires authentication).
  Future<void> removeFavorite(String productId, {CancelToken? cancelToken});

  /// Favorite product ids from the local cache — no network involved.
  Future<Set<String>> cachedFavoriteIds();

  /// Writes the favorite ids through to the local cache.
  Future<void> saveFavoriteIds(Set<String> ids);
}
