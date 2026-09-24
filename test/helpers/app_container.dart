import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/data/datasources/cart_local_data_source.dart';
import 'package:marketflow/data/datasources/favorites_cache.dart';
import 'package:marketflow/data/datasources/market_api_host.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/domain/entities/product.dart';
import 'package:marketflow/presentation/providers/infrastructure_providers.dart';

/// A ProviderContainer wired to a live in-process mock API with in-memory
/// persistence seams — the same wiring `main()` uses, but injectable.
class TestAppScope {
  TestAppScope({
    required this.host,
    required this.container,
    required this.sessionLocal,
    required this.cartLocal,
    required this.favoritesCache,
  });

  /// The running in-process backend (with zero latency by default).
  final MarketApiHost host;

  /// The app-wide provider container.
  final ProviderContainer container;

  /// In-memory session storage shared with the container override.
  final InMemorySessionLocalDataSource sessionLocal;

  /// In-memory cart storage shared with the container override.
  final CartLocalDataSource cartLocal;

  /// In-memory favorites cache shared with the container override.
  final InMemoryFavoritesCache favoritesCache;

  /// Yields to the event loop long enough for `unawaited(...)` restore/sync
  /// work (latency is zero, so one frame of real time is plenty).
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));
}

/// Creates a scope with a started server. Disposal is registered with
/// [addTearDown] automatically.
///
/// [retry] configures the container's automatic provider retry (disabled
/// with `(_, _) => null`); defaults to Riverpod's exponential-backoff retry.
Future<TestAppScope> createTestApp({
  InMemorySessionLocalDataSource? sessionLocal,
  CartLocalDataSource? cartLocal,
  Duration? Function(int retryCount, Object error)? retry,
}) async {
  final host = MarketApiHost();
  host.server.conditions.latencyMinMs = 0;
  host.server.conditions.latencyMaxMs = 0;
  await host.start();

  final effectiveSession = sessionLocal ?? InMemorySessionLocalDataSource();
  final effectiveCart = cartLocal ?? InMemoryCartLocalDataSource();
  final favoritesCache = InMemoryFavoritesCache();

  final container = ProviderContainer(
    overrides: [
      mockApiHostProvider.overrideWith((ref) => host),
      sessionLocalDataSourceProvider.overrideWith((ref) => effectiveSession),
      cartLocalDataSourceProvider.overrideWith((ref) => effectiveCart),
      favoritesCacheProvider.overrideWith((ref) => favoritesCache),
    ],
    retry: retry,
  );

  final scope = TestAppScope(
    host: host,
    container: container,
    sessionLocal: effectiveSession,
    cartLocal: effectiveCart,
    favoritesCache: favoritesCache,
  );
  addTearDown(container.dispose);
  addTearDown(host.stop);
  return scope;
}

/// Deterministic product stub for pure-state tests (no network needed).
Product stubProduct(
  String id, {
  double price = 10.0,
  int stock = 5,
  bool isAvailable = true,
}) {
  return Product(
    id: id,
    title: 'Product $id',
    description: 'Description of $id',
    price: price,
    imageUrls: ['https://example.com/$id.jpg'],
    rating: 4.5,
    reviewCount: 42,
    stock: stock,
    categoryId: 'c1',
    sellerName: 'Test Seller',
    isAvailable: isAvailable,
  );
}
