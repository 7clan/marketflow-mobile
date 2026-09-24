import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../data/datasources/cart_local_data_source.dart';
import '../../data/datasources/favorites_cache.dart';
import '../../data/datasources/market_api_host.dart';
import '../../data/datasources/secure_session_local_data_source.dart';
import '../../data/datasources/session_local_data_source.dart';
import '../../data/datasources/shared_preferences_cart_local_data_source.dart';
import '../../data/datasources/shared_preferences_favorites_cache.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/cart_repository_impl.dart';
import '../../data/repositories/favorites_repository_impl.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/cart_repository.dart';
import '../../domain/repositories/favorites_repository.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/repositories/product_repository.dart';

/// Overridden in `main()` after `SharedPreferences.getInstance()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main()',
  );
});

/// The in-process mock API host.
///
/// `main()` starts the host before `runApp` and overrides this provider with
/// the started instance (stopping it when the scope is disposed). Tests do
/// the same with [startMockApiHost]. Production builds override
/// [appConfigProvider] with a real backend URL instead and never use this.
final mockApiHostProvider = Provider<MarketApiHost>((ref) {
  throw UnimplementedError(
    'mockApiHostProvider must be overridden with a started host — '
    'see main.dart (or use startMockApiHost() in tests)',
  );
});

/// Resolved HTTP configuration. The default points at the in-process mock
/// server; a production build overrides this provider with
/// `const AppConfig(baseUrl: 'https://api.marketflow.dev/v1')`.
final appConfigProvider = Provider<AppConfig>((ref) {
  final host = ref.watch(mockApiHostProvider);
  return AppConfig.localServer(port: host.port!);
});

/// Session storage — swap with [InMemorySessionLocalDataSource] in tests.
final sessionLocalDataSourceProvider = Provider<SessionLocalDataSource>((ref) {
  return SecureSessionLocalDataSource();
});

/// The app's single typed HTTP surface.
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final sessionLocal = ref.watch(sessionLocalDataSourceProvider);
  final client = ApiClient(
    config: config,
    tokenProvider: () async => (await sessionLocal.read())?.token,
  );
  ref.onDispose(client.close);
  return client;
});

/// Cart persistence — SharedPreferences in production, in-memory in tests.
final cartLocalDataSourceProvider = Provider<CartLocalDataSource>((ref) {
  return SharedPreferencesCartLocalDataSource(
    preferences: ref.watch(sharedPreferencesProvider),
  );
});

/// Favorites id cache — SharedPreferences in production, in-memory in tests.
final favoritesCacheProvider = Provider<FavoritesCache>((ref) {
  return SharedPreferencesFavoritesCache(
    preferences: ref.watch(sharedPreferencesProvider),
  );
});

// ---------------------------------------------------------------------------
// Repositories (all overridable in tests)
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  final local = ref.watch(sessionLocalDataSourceProvider);
  final repository = AuthRepositoryImpl(apiClient: api, local: local);
  // Session-expiry wiring: a 401 with an attached token anywhere outside the
  // auth endpoints discards the session. The repository (the session owner)
  // reacts through its own interceptor on the shared client — wiring this
  // from [apiClientProvider] would create a provider initializer cycle, and
  // reading the auth controller from there can deadlock session restore.
  // App state updates flow through the repository's userChanges stream.
  final sessionExpiry = InterceptorsWrapper(
    onError: (error, handler) {
      final status = error.response?.statusCode;
      final hadToken = error.requestOptions.headers['Authorization'] != null;
      if (status == 401 && hadToken) {
        unawaited(repository.discardLocalSession());
      }
      handler.next(error);
    },
  );
  api.dio.interceptors.add(sessionExpiry);
  ref.onDispose(() => api.dio.interceptors.remove(sessionExpiry));
  ref.onDispose(repository.dispose);
  return repository;
});

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepositoryImpl(apiClient: ref.watch(apiClientProvider)),
);

final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepositoryImpl(
    apiClient: ref.watch(apiClientProvider),
    cache: ref.watch(favoritesCacheProvider),
  ),
);

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepositoryImpl(local: ref.watch(cartLocalDataSourceProvider)),
);

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepositoryImpl(apiClient: ref.watch(apiClientProvider)),
);
