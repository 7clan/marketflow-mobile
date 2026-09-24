import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import 'auth_controller.dart';
import 'infrastructure_providers.dart';

/// Rendered state of the favorites feature.
class FavoritesState {
  const FavoritesState({
    this.ids = const <String>{},
    this.isLoading = false,
    this.error,
  });

  /// Favorite product ids (server-backed, cache-hydrated).
  final Set<String> ids;

  /// `true` while syncing the full list from the server.
  final bool isLoading;

  /// Error of the last failed optimistic toggle (rolled back) or sync.
  final AppException? error;

  /// `true` when [productId] is favorited.
  bool isFavorite(String productId) => ids.contains(productId);

  FavoritesState copyWith({
    Set<String>? ids,
    bool? isLoading,
    Object? error = _unset,
  }) {
    return FavoritesState(
      ids: ids ?? this.ids,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as AppException?,
    );
  }

  /// Sentinel for [copyWith]'s nullable clear.
  static const _unset = Object();
}

/// Server-backed favorites with **optimistic** add/remove.
///
/// * cold start renders instantly from the local id cache;
/// * sign-in (or manual refresh) syncs the full list from the server and
///   writes it back through the cache;
/// * toggling a favorite updates the state immediately and **rolls back to
///   the previous state** when the server rejects the change, surfacing the
///   error message.
final favoritesControllerProvider =
    NotifierProvider<FavoritesController, FavoritesState>(
      FavoritesController.new,
    );

class FavoritesController extends Notifier<FavoritesState> {
  @override
  FavoritesState build() {
    // Heart buttons live on many screens; the ids must always be available.
    ref.keepAlive();

    // Instant cold-start hydration, then a server sync once signed in.
    unawaited(_hydrateFromCache());
    ref.listen(authControllerProvider, (previous, next) {
      final authState = next.value;
      if (authState is AuthAuthenticated) {
        unawaited(syncFromServer());
      } else if (authState is AuthUnauthenticated) {
        state = state.copyWith(ids: const <String>{}, error: null);
      }
    });

    return const FavoritesState();
  }

  Future<void> _hydrateFromCache() async {
    final repository = ref.read(favoritesRepositoryProvider);
    try {
      final ids = await repository.cachedFavoriteIds();
      if (ids.isNotEmpty) {
        state = state.copyWith(ids: ids);
      }
    } on CacheException {
      // The cache is an optimization — never a hard dependency.
    }
  }

  /// Fetches the authoritative list from the server (also used by the
  /// pull-to-refresh on the favorites screen).
  Future<void> syncFromServer() async {
    final repository = ref.read(favoritesRepositoryProvider);
    state = state.copyWith(isLoading: true);
    try {
      final products = await repository.listFavorites();
      final ids = {for (final product in products) product.id};
      state = state.copyWith(ids: ids, isLoading: false, error: null);
      unawaited(repository.saveFavoriteIds(ids));
    } on AppException catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// Optimistically favorites [productId]; rolls back on failure.
  Future<void> addFavorite(String productId) async {
    final previous = state;
    if (previous.ids.contains(productId)) return;
    state = previous.copyWith(ids: {...previous.ids, productId}, error: null);
    final repository = ref.read(favoritesRepositoryProvider);
    try {
      await repository.addFavorite(productId);
      unawaited(repository.saveFavoriteIds(state.ids));
    } on AppException catch (error) {
      state = previous.copyWith(error: error);
    }
  }

  /// Optimistically un-favorites [productId]; rolls back on failure.
  Future<void> removeFavorite(String productId) async {
    final previous = state;
    if (!previous.ids.contains(productId)) return;
    state = previous.copyWith(
      ids: {...previous.ids}..remove(productId),
      error: null,
    );
    final repository = ref.read(favoritesRepositoryProvider);
    try {
      await repository.removeFavorite(productId);
      unawaited(repository.saveFavoriteIds(state.ids));
    } on AppException catch (error) {
      state = previous.copyWith(error: error);
    }
  }

  /// Clears the last surfaced error (dismissed banner / retry).
  void clearError() => state = state.copyWith(error: null);
}
