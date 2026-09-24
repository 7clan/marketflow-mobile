// End-to-end smoke check for the MarketFlow data layer.
//
// Boots the in-process mock marketplace server on an ephemeral port and
// drives a real ApiClient (real Dio, real HTTP) through the repository
// implementations — auth, catalog, filters, sorting, search, pagination,
// favorites, checkout and error mapping. Run with:
//
//   dart run tool/server_smoke_check.dart
//
// (The full unit/widget/integration suite lives in test/; this script is a
// fast wiring check for development.)
import 'dart:io';

import 'package:marketflow/core/config/app_config.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/core/network/api_client.dart';
import 'package:marketflow/data/datasources/favorites_cache.dart';
import 'package:marketflow/data/datasources/mock_marketplace_server.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/data/repositories/auth_repository_impl.dart';
import 'package:marketflow/data/repositories/favorites_repository_impl.dart';
import 'package:marketflow/data/repositories/order_repository_impl.dart';
import 'package:marketflow/data/repositories/product_repository_impl.dart';
import 'package:marketflow/domain/entities/address.dart';
import 'package:marketflow/domain/entities/cart_item.dart';
import 'package:marketflow/domain/entities/cart_totals.dart';
import 'package:marketflow/domain/entities/order.dart';
import 'package:marketflow/domain/entities/product_filter.dart';

int _failures = 0;

void check(String name, bool ok) {
  stdout.writeln('${ok ? 'PASS' : 'FAIL'}: $name');
  if (!ok) _failures++;
}

Future<bool> throws<T extends AppException>(
  Future<void> Function() action,
) async {
  try {
    await action();
    return false;
  } on T {
    return true;
  } on AppException catch (error) {
    stdout.writeln('     (unexpected ${error.runtimeType}: ${error.message})');
    return false;
  }
}

Future<void> main() async {
  final server = MockMarketplaceServer();
  // Keep the smoke check fast; latency behavior is covered by the test suite.
  server.conditions.latencyMinMs = 0;
  server.conditions.latencyMaxMs = 0;
  await server.start();

  var token = '';
  final apiClient = ApiClient(
    config: AppConfig.localServer(port: server.port!),
    tokenProvider: () async => token.isEmpty ? null : token,
  );
  final sessionLocal = InMemorySessionLocalDataSource();
  final favoritesCache = InMemoryFavoritesCache();

  final authRepository = AuthRepositoryImpl(
    apiClient: apiClient,
    local: sessionLocal,
  );
  final productRepository = ProductRepositoryImpl(apiClient: apiClient);
  final favoritesRepository = FavoritesRepositoryImpl(
    apiClient: apiClient,
    cache: favoritesCache,
  );
  final orderRepository = OrderRepositoryImpl(apiClient: apiClient);

  try {
    // ---------------------------------------------------------------------
    // Auth
    // ---------------------------------------------------------------------
    check(
      'wrong credentials → UnauthorizedException',
      await throws<UnauthorizedException>(
        () => authRepository.login(
          email: 'demo@marketflow.dev',
          password: 'nope',
        ),
      ),
    );
    final session = await authRepository.login(
      email: 'demo@marketflow.dev',
      password: 'Password123',
    );
    token = session.token;
    check(
      'demo login returns Dana Mercado',
      session.user.name == 'Dana Mercado',
    );
    check(
      'demo login has seeded favorites',
      (await favoritesRepository.listFavorites()).length == 3,
    );
    check(
      'register with weak fields → ValidationException',
      await throws<ValidationException>(
        () =>
            authRepository.register(name: 'x', email: 'bad', password: 'short'),
      ),
    );

    final registered = await authRepository.register(
      name: 'Sofia Archer',
      email: 'sofia@example.com',
      password: 'Password123',
    );
    check(
      'register returns a session',
      registered.user.email == 'sofia@example.com',
    );
    check(
      'duplicate email → ValidationException',
      await throws<ValidationException>(
        () => authRepository.register(
          name: 'Sofia Again',
          email: 'sofia@example.com',
          password: 'Password123',
        ),
      ),
    );

    final restored = await authRepository.restoreSession();
    check(
      'restoreSession rehydrates the demo user',
      restored != null && restored.user.email == 'demo@marketflow.dev',
    );

    // ---------------------------------------------------------------------
    // Catalog
    // ---------------------------------------------------------------------
    final categories = await productRepository.getCategories();
    check('six categories', categories.length == 6);
    check(
      'category product counts sum to 66',
      categories.fold<int>(0, (sum, c) => sum + c.productCount) == 66,
    );

    final page1 = await productRepository.getProducts(page: 1, pageSize: 20);
    check('page 1 has 20 items', page1.items.length == 20);
    check(
      'page 1 metadata',
      page1.totalItems == 66 && page1.totalPages == 4 && page1.hasMore,
    );
    final page4 = await productRepository.getProducts(page: 4, pageSize: 20);
    check(
      'page 4 has 6 items and no more',
      page4.items.length == 6 && !page4.hasMore,
    );

    final product = await productRepository.getProduct('p01');
    check(
      'image URLs follow the picsum seed contract',
      product.imageUrls.first == 'https://picsum.photos/seed/mf-p01/600/600',
    );
    check('product has rating populated', product.rating > 0);

    check(
      'unknown product → NotFoundException',
      await throws<NotFoundException>(
        () => productRepository.getProduct('p999'),
      ),
    );

    final electronics = await productRepository.getProducts(
      page: 1,
      pageSize: 50,
      filter: const ProductFilter(categoryId: 'c1'),
    );
    check(
      'category filter only returns Electronics',
      electronics.items.every((p) => p.categoryId == 'c1') &&
          electronics.items.length == 11,
    );

    final cheapFirst = await productRepository.getProducts(
      page: 1,
      pageSize: 66,
      sort: ProductSort.priceAsc,
    );
    final prices = cheapFirst.items.map((p) => p.price).toList();
    final sortedPrices = [...prices]..sort();
    check(
      'price_asc ordering',
      prices.length == 66 &&
          prices.first <= prices.last &&
          prices[0] == sortedPrices[0] &&
          prices[65] == sortedPrices[65],
    );

    final inStock = await productRepository.getProducts(
      page: 1,
      pageSize: 66,
      filter: const ProductFilter(inStockOnly: true),
    );
    check(
      'inStockOnly hides out-of-stock/unavailable',
      inStock.items.every((p) => p.stock > 0 && p.isAvailable),
    );

    final priceBand = await productRepository.getProducts(
      page: 1,
      pageSize: 66,
      filter: const ProductFilter(minPrice: 50, maxPrice: 120),
    );
    check(
      'min/max price filter bounds prices',
      priceBand.items.every((p) => p.price >= 50 && p.price <= 120),
    );

    final camera = await productRepository.getProducts(
      page: 1,
      pageSize: 10,
      query: 'camera',
    );
    check(
      'search "camera" finds camera products',
      camera.items.isNotEmpty &&
          camera.items.first.title.toLowerCase().contains('camera'),
    );

    // ---------------------------------------------------------------------
    // Favorites
    // ---------------------------------------------------------------------
    await favoritesRepository.addFavorite('p02');
    final favorites = await favoritesRepository.listFavorites();
    check(
      'favorites list grew after add',
      favorites.any((p) => p.id == 'p02') && favorites.length == 4,
    );
    await favoritesRepository.removeFavorite('p02');
    check(
      'favorites list shrank after remove',
      (await favoritesRepository.listFavorites()).length == 3,
    );
    check(
      'unknown favorite → NotFoundException',
      await throws<NotFoundException>(
        () => favoritesRepository.addFavorite('p999'),
      ),
    );

    // ---------------------------------------------------------------------
    // Checkout & orders
    // ---------------------------------------------------------------------
    const address = Address(
      fullName: 'Dana Mercado',
      street: '482 Harbor Lane',
      city: 'Portland',
      state: 'OR',
      zip: '97201',
      phone: '+1 503 555 0148',
    );

    check(
      'empty cart checkout → ValidationException',
      await throws<ValidationException>(
        () => orderRepository.placeOrder(
          items: const <CartItem>[],
          address: address,
          paymentMethod: PaymentMethod.card,
        ),
      ),
    );

    final outOfStockProduct = await productRepository.getProduct('p04');
    ConflictException? conflict;
    try {
      await orderRepository.placeOrder(
        items: [CartItem(product: outOfStockProduct, quantity: 1)],
        address: address,
        paymentMethod: PaymentMethod.cashOnDelivery,
      );
    } on ConflictException catch (error) {
      conflict = error;
    }
    check(
      'out-of-stock checkout → ConflictException carrying ids',
      conflict != null && conflict.conflictingItems.contains('p04'),
    );

    final buyable = await productRepository.getProduct('p05');
    final order = await orderRepository.placeOrder(
      items: [CartItem(product: buyable, quantity: 2)],
      address: address,
      paymentMethod: PaymentMethod.card,
    );
    final expectedTotals = computeCartTotals([
      CartItem(product: buyable, quantity: 2),
    ]);
    check(
      'order totals mirror domain pricing rules',
      order.total == expectedTotals.total &&
          order.subtotal == expectedTotals.subtotal &&
          order.tax == expectedTotals.tax &&
          order.shipping == expectedTotals.shipping,
    );
    check('order starts as pending', order.status == OrderStatus.pending);

    final orders = await orderRepository.getOrders();
    check(
      'order history contains the new order first',
      orders.first.id == order.id && orders.length == 3,
    );
    final detail = await orderRepository.getOrder(order.id);
    check(
      'order detail round-trips',
      detail.id == order.id && detail.itemCount == 2,
    );
    check(
      'unknown order → NotFoundException',
      await throws<NotFoundException>(() => orderRepository.getOrder('o999')),
    );

    // ---------------------------------------------------------------------
    // Failure injection
    // ---------------------------------------------------------------------
    server.conditions.malformedNext = true;
    check(
      'malformedNext → MalformedResponseException',
      await throws<MalformedResponseException>(
        () => productRepository.getCategories(),
      ),
    );

    server.conditions.forceStatusNext(1, 500);
    check(
      'forced 500 → ServerException',
      await throws<ServerException>(() => productRepository.getCategories()),
    );

    token = 'invalid-token';
    check(
      'stale token → UnauthorizedException on favorites',
      await throws<UnauthorizedException>(
        () => favoritesRepository.listFavorites(),
      ),
    );

    token = session.token;
  } finally {
    await server.close();
    apiClient.close();
  }

  stdout.writeln('----');
  stdout.writeln(
    _failures == 0
        ? 'All smoke checks passed.'
        : '$_failures smoke check(s) FAILED.',
  );
  exit(_failures == 0 ? 0 : 1);
}
