import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/config/app_config.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/datasources/cart_local_data_source.dart';
import 'package:marketflow/domain/entities/address.dart';
import 'package:marketflow/domain/entities/auth_session.dart';
import 'package:marketflow/domain/entities/cart_item.dart';
import 'package:marketflow/domain/entities/category.dart';
import 'package:marketflow/domain/entities/order.dart';
import 'package:marketflow/domain/entities/paginated_result.dart';
import 'package:marketflow/domain/entities/product.dart';
import 'package:marketflow/domain/entities/product_filter.dart';
import 'package:marketflow/domain/entities/user.dart';
import 'package:marketflow/domain/repositories/auth_repository.dart';
import 'package:marketflow/domain/repositories/cart_repository.dart';
import 'package:marketflow/domain/repositories/favorites_repository.dart';
import 'package:marketflow/domain/repositories/order_repository.dart';
import 'package:marketflow/domain/repositories/product_repository.dart';
import 'package:marketflow/presentation/providers/infrastructure_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-test doubles: complete in-memory repositories, no HTTP at all.
///
/// Every fake records the calls it receives so widget tests can assert that a
/// tap actually reached the domain layer.

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Deterministic auth fake. Successful credentials:
/// `demo@marketflow.dev` / `Password123`.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({User? initialUser, this.loginGate}) : _user = initialUser;

  /// When set, [login] stays in flight until the test completes it.
  final Completer<void>? loginGate;

  User? _user;
  int loginCalls = 0;
  int logoutCalls = 0;
  int restoreCalls = 0;

  final StreamController<User?> _userChanges = StreamController.broadcast();

  @override
  Stream<User?> get userChanges => _userChanges.stream;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    await loginGate?.future;
    if (email != 'demo@marketflow.dev' || password != 'Password123') {
      throw UnauthorizedException(serverMessage: 'Invalid email or password.');
    }
    _user = const User(
      id: 'u1',
      name: 'Dana Mercado',
      email: 'demo@marketflow.dev',
      memberSince: null,
    );
    _userChanges.add(_user);
    return AuthSession(token: 'tok-fake-1', user: _user!);
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _user = User(id: 'u2', name: name, email: email, memberSince: null);
    _userChanges.add(_user);
    return AuthSession(token: 'tok-fake-2', user: _user!);
  }

  @override
  Future<AuthSession?> restoreSession() async {
    restoreCalls++;
    return _user == null
        ? null
        : AuthSession(token: 'tok-fake-1', user: _user!);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    _user = null;
    _userChanges.add(null);
  }

  @override
  Future<User?> currentUser() async => _user;

  @override
  Future<void> discardLocalSession() async {
    _user = null;
    _userChanges.add(null);
  }

  Future<void> dispose() => _userChanges.close();
}

/// Catalog fake holding a fixed list; serves any page slice of it.
class FakeProductRepository implements ProductRepository {
  FakeProductRepository({this.products = const <Product>[]});

  final List<Product> products;
  final List<String> productCalls = [];

  /// When set, [getProducts] stays in flight until the test completes it —
  /// used to hold screens in their loading state deterministically.
  Completer<void>? getProductsGate;

  @override
  Future<PaginatedResult<Product>> getProducts({
    required int page,
    required int pageSize,
    ProductFilter? filter,
    ProductSort sort = ProductSort.relevance,
    String? query,
    CancelToken? cancelToken,
  }) async {
    productCalls.add('page:$page');
    await getProductsGate?.future;
    var items = products;
    if (query != null && query.trim().isNotEmpty) {
      final needle = query.trim().toLowerCase();
      items = items
          .where((product) => product.title.toLowerCase().contains(needle))
          .toList();
    }
    final start = (page - 1) * pageSize;
    if (start >= items.length) {
      return PaginatedResult(
        items: const <Product>[],
        page: page,
        totalPages: 1,
        totalItems: items.length,
        hasMore: false,
      );
    }
    final slice = items.skip(start).take(pageSize).toList();
    return PaginatedResult(
      items: slice,
      page: page,
      totalPages: (items.length / pageSize).ceil(),
      totalItems: items.length,
      hasMore: start + pageSize < items.length,
    );
  }

  @override
  Future<Product> getProduct(String id, {CancelToken? cancelToken}) async {
    for (final product in products) {
      if (product.id == id) return product;
    }
    throw NotFoundException(serverMessage: 'Product not found.');
  }

  @override
  Future<List<Category>> getCategories({CancelToken? cancelToken}) async {
    return const [Category(id: 'c1', name: 'Electronics', productCount: 3)];
  }
}

/// Favorites fake: a mutable id set, no failures by default.
class FakeFavoritesRepository implements FavoritesRepository {
  final Set<String> _ids = <String>{};
  final Set<String> _cachedIds = <String>{};

  int addCalls = 0;
  int removeCalls = 0;

  @override
  Future<List<Product>> listFavorites({CancelToken? cancelToken}) async =>
      const <Product>[];

  @override
  Future<void> addFavorite(String productId, {CancelToken? cancelToken}) async {
    addCalls++;
    _ids.add(productId);
  }

  @override
  Future<void> removeFavorite(
    String productId, {
    CancelToken? cancelToken,
  }) async {
    removeCalls++;
    _ids.remove(productId);
  }

  @override
  Future<Set<String>> cachedFavoriteIds() async => Set.of(_cachedIds);

  @override
  Future<void> saveFavoriteIds(Set<String> ids) async {
    _cachedIds
      ..clear()
      ..addAll(ids);
  }
}

/// Order fake: records placed orders in memory.
class FakeOrderRepository implements OrderRepository {
  final List<Order> orders = [];

  @override
  Future<Order> placeOrder({
    required List<CartItem> items,
    required Address address,
    required PaymentMethod paymentMethod,
  }) async {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.lineTotal);
    const shipping = 8.99;
    final tax = subtotal * 0.085;
    final order = Order(
      id: 'ord-fake-${orders.length + 1}',
      status: OrderStatus.pending,
      items: items,
      subtotal: subtotal,
      shipping: shipping,
      tax: tax,
      total: subtotal + shipping + tax,
      address: address,
      placedAt: DateTime.utc(2026, 1, 1),
      estimatedDelivery: DateTime.utc(2026, 1, 8),
    );
    orders.add(order);
    return order;
  }

  @override
  Future<List<Order>> getOrders({CancelToken? cancelToken}) async =>
      List.of(orders);

  @override
  Future<Order> getOrder(String id, {CancelToken? cancelToken}) async {
    for (final order in orders) {
      if (order.id == id) return order;
    }
    throw NotFoundException(serverMessage: 'Order not found.');
  }
}

/// Cart persistence fake backed by the shared in-memory data source.
class FakeCartRepository implements CartRepository {
  FakeCartRepository([CartLocalDataSource? local]) : _local = local;

  final CartLocalDataSource? _local;
  final List<List<CartItem>> savedBatches = [];

  @override
  Future<List<CartItem>> loadCart() async =>
      _local == null ? const <CartItem>[] : await _local.load();

  @override
  Future<void> saveCart(List<CartItem> items) async {
    savedBatches.add(items);
    await _local?.save(items);
  }

  @override
  Future<void> clear() async => _local?.clear();
}

// ---------------------------------------------------------------------------
// Container
// ---------------------------------------------------------------------------

/// Builds a [ProviderContainer] whose every repository is an in-memory fake
/// — the entire widget tree runs without any network.
Future<ProviderContainer> createFakeRepositoryContainer({
  FakeAuthRepository? authRepository,
  FakeProductRepository? productRepository,
  FakeFavoritesRepository? favoritesRepository,
  FakeOrderRepository? orderRepository,
  FakeCartRepository? cartRepository,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final preferences = await SharedPreferences.getInstance();

  final auth = authRepository ?? FakeAuthRepository();
  final cartLocal = InMemoryCartLocalDataSource();

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWith((ref) => auth),
      productRepositoryProvider.overrideWith(
        (ref) => productRepository ?? FakeProductRepository(),
      ),
      favoritesRepositoryProvider.overrideWith(
        (ref) => favoritesRepository ?? FakeFavoritesRepository(),
      ),
      orderRepositoryProvider.overrideWith(
        (ref) => orderRepository ?? FakeOrderRepository(),
      ),
      cartRepositoryProvider.overrideWith(
        (ref) => cartRepository ?? FakeCartRepository(cartLocal),
      ),
      sharedPreferencesProvider.overrideWithValue(preferences),
      // Feed/search read the page size off the config; the default provider
      // requires the (overridden) mock host, so pin a plain value instead.
      appConfigProvider.overrideWith((ref) {
        return AppConfig.localServer(port: 0);
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
