import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../domain/entities/cart_item.dart';
import '../../domain/entities/cart_totals.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/product_filter.dart';
import '../models/address_model.dart';
import '../models/cart_item_model.dart';
import '../models/category_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/user_model.dart';

/// Mutable runtime conditions the mock server applies to incoming requests.
///
/// A reviewer (or a test) can flip these to *experience* the app's error,
/// timeout, malformed-response and checkout-conflict states without touching
/// infrastructure. Everything is deterministic — no `DateTime.now`, no
/// unseeded randomness. Call [reset] to return to the defaults.
class BackendConditions {
  /// Minimum artificial latency per request (default 150ms).
  int latencyMinMs = 150;

  /// Maximum artificial latency per request (default 300ms).
  int latencyMaxMs = 300;

  /// When `true`, the **next** request answers HTTP 200 with a body that is
  /// not valid JSON (one-shot: consumed by the server).
  bool malformedNext = false;

  /// When `true`, every checkout answers 409 listing the requested product
  /// ids as out of stock — regardless of real stock.
  bool failCheckoutWithOutOfStock = false;

  int _forcedStatusRemaining = 0;
  int _forcedStatusCode = 500;

  /// Forces the next [count] requests to answer with HTTP [code]
  /// (e.g. `forceStatusNext(2, 500)`).
  void forceStatusNext(int count, int code) {
    _forcedStatusRemaining = count;
    _forcedStatusCode = code;
  }

  /// Clears any pending forced-status count without issuing one.
  void clearForcedStatus() => _forcedStatusRemaining = 0;

  /// `true` when no condition will alter request behavior.
  bool get isHealthy =>
      latencyMinMs == 150 &&
      latencyMaxMs == 300 &&
      !malformedNext &&
      !failCheckoutWithOutOfStock &&
      _forcedStatusRemaining == 0;

  /// Restores every condition to its default value.
  void reset() {
    latencyMinMs = 150;
    latencyMaxMs = 300;
    malformedNext = false;
    failCheckoutWithOutOfStock = false;
    _forcedStatusRemaining = 0;
    _forcedStatusCode = 500;
  }

  int? _consumeForcedStatus() {
    if (_forcedStatusRemaining <= 0) return null;
    _forcedStatusRemaining--;
    return _forcedStatusCode;
  }
}

/// Deterministic in-process marketplace API.
///
/// A real `dart:io` [HttpServer] bound to `127.0.0.1` on an **ephemeral**
/// port — the app's Dio client talks to it over genuine HTTP, so timeouts,
/// interceptors, cancellation and error mapping are all exercised for real.
///
/// Contract:
/// * success responses use the envelope `{"data": ...}`;
/// * failures use `{"error": {"code": ..., "message": ...}}` and may add
///   `errors: {field: [messages]}` (422) or `items: [ids]` (409);
/// * the catalog is seeded deterministically (66 products, 6 categories);
/// * the demo account `demo@marketflow.dev` / `Password123` is pre-registered
///   with favorites and two historical orders;
/// * runtime failure injection is available through [conditions];
/// * the catalog, users, favorites and orders live in memory only.
///
/// Swap the app to a production backend by changing `AppConfig.baseUrl` —
/// the wire contract is identical.
class MockMarketplaceServer {
  MockMarketplaceServer({Random? seedRandom})
    : _random = seedRandom ?? Random(20260101) {
    _seed();
  }

  /// Injectable failure conditions — mutate freely from tests or a debug UI.
  final BackendConditions conditions = BackendConditions();

  HttpServer? _server;
  int _requestCounter = 0;

  /// Total requests handled since the last reset — lets tests assert how
  /// many network calls a controller actually made (debounce/cancellation).
  int get handledRequestCount => _requestCounter;

  // -----------------------------------------------------------------------
  // Lifecycle
  // -----------------------------------------------------------------------

  /// Binds the server to `127.0.0.1` on an ephemeral port. Idempotent.
  Future<void> start() async {
    final existing = _server;
    if (existing != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      (request) {
        unawaited(_handleSafely(request));
      },
      onError: (Object error) {
        // Transport-level hiccups must not kill the server; individual
        // request failures are answered per-request.
        stderr.writeln('MockMarketplaceServer: stream error: $error');
      },
    );
  }

  /// Stops the server and releases the port. Safe to call twice.
  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  /// The bound port, or `null` while stopped.
  int? get port => _server?.port;

  /// `true` between [start] and [close].
  bool get isRunning => _server != null;

  /// Resets all in-memory state (catalog stock, users, favorites, orders,
  /// id/time sequences) back to the seeded defaults — the [conditions] are
  /// reset too. Use between tests.
  void resetData() {
    conditions.reset();
    _seed();
  }

  // -----------------------------------------------------------------------
  // Seeded state
  // -----------------------------------------------------------------------

  final Random _random;

  final Map<String, ProductModel> _productsById = {};
  final Map<String, DateTime> _listedAtById = {};
  final List<CategoryModel> _categories = [];
  final Map<String, _MockUser> _usersByEmail = {};
  final Map<String, _MockUser> _usersByToken = {};
  final Map<String, Set<String>> _favoritesByEmail = {};
  final Map<String, List<OrderModel>> _ordersByEmail = {};

  int _userIdSeq = 10;
  int _tokenSeq = 10;
  int _orderIdSeq = 1003;
  int _orderTimeSeq = 0;

  static final _orderTimeEpoch = DateTime.utc(2026, 1, 15, 10);

  DateTime _nextOrderPlacedAt() =>
      _orderTimeEpoch.add(Duration(minutes: 7 * ++_orderTimeSeq));

  void _seed() {
    _productsById.clear();
    _listedAtById.clear();
    _categories.clear();
    _usersByEmail.clear();
    _usersByToken.clear();
    _favoritesByEmail.clear();
    _ordersByEmail.clear();
    _userIdSeq = 10;
    _tokenSeq = 10;
    _orderIdSeq = 1003;
    _orderTimeSeq = 0;
    _requestCounter = 0;

    _buildCatalog();

    final demo = _MockUser(
      model: UserModel(
        id: 'u1',
        name: 'Dana Mercado',
        email: 'demo@marketflow.dev',
        memberSince: DateTime.utc(2025, 3, 12),
      ),
      password: 'Password123',
      token: 'tok-demo-1',
    );
    _usersByEmail[demo.model.email] = demo;
    _usersByToken[demo.token] = demo;
    _favoritesByEmail[demo.model.email] = {'p05', 'p12', 'p27'};

    const demoAddress = AddressModel(
      fullName: 'Dana Mercado',
      street: '482 Harbor Lane',
      city: 'Portland',
      state: 'OR',
      zip: '97201',
      country: 'United States',
      phone: '+1 503 555 0148',
    );

    _ordersByEmail[demo.model.email] = [
      _buildSeedOrder(
        id: 'o1001',
        status: OrderStatus.delivered,
        address: demoAddress,
        entries: const [('p03', 1), ('p10', 2)],
        placedAt: DateTime.utc(2026, 1, 2, 10),
      ),
      _buildSeedOrder(
        id: 'o1002',
        status: OrderStatus.shipped,
        address: demoAddress,
        entries: const [('p15', 1)],
        placedAt: DateTime.utc(2026, 1, 9, 14, 30),
      ),
    ];
  }

  OrderModel _buildSeedOrder({
    required String id,
    required OrderStatus status,
    required AddressModel address,
    required List<(String, int)> entries,
    required DateTime placedAt,
  }) {
    final items = [
      for (final (productId, quantity) in entries)
        CartItem(
          product: _productsById[productId]!.toDomain(),
          quantity: quantity,
        ),
    ];
    final totals = computeCartTotals(items);
    return OrderModel(
      id: id,
      status: status,
      items: [for (final item in items) CartItemModel.fromDomain(item)],
      subtotal: totals.subtotal,
      shipping: totals.shipping,
      tax: totals.tax,
      total: totals.total,
      address: address,
      placedAt: placedAt,
      estimatedDelivery: placedAt.add(const Duration(days: 4, hours: 6)),
    );
  }

  // -----------------------------------------------------------------------
  // Catalog
  // -----------------------------------------------------------------------

  void _buildCatalog() {
    var index = 0;
    for (final spec in _catalogSpecs) {
      for (final item in spec.items) {
        index++;
        final id = 'p${index.toString().padLeft(2, '0')}';
        final jitter = _random.nextDouble() * 0.16 - 0.08; // ±8%
        final price = _round2(
          (item.basePrice * (1 + jitter)).clamp(4.99, 2000),
        );
        final hasCompareAt = _random.nextDouble() < 0.35;
        final compareAtPrice = hasCompareAt
            ? _round2(price * 1.18 + 1.5)
            : null;
        final stock = index % 17 == 4 ? 0 : 1 + _random.nextInt(140);
        final sellers =
            _sellersByCategory[spec.id] ?? const ['MarketFlow Direct'];
        final sellerName = sellers[_random.nextInt(sellers.length)];
        final description = _descriptions[_random.nextInt(_descriptions.length)]
            .replaceAll('{title}', item.title)
            .replaceAll('{seller}', sellerName);

        _productsById[id] = ProductModel(
          id: id,
          title: item.title,
          description: description,
          price: price,
          compareAtPrice: compareAtPrice,
          imageUrls: [
            'https://picsum.photos/seed/mf-$id/600/600',
            'https://picsum.photos/seed/mf-${id}b/600/600',
            'https://picsum.photos/seed/mf-${id}c/600/600',
          ],
          rating: _round1(3.0 + _random.nextDouble() * 1.9),
          reviewCount: 3 + _random.nextInt(2800),
          stock: stock,
          categoryId: spec.id,
          sellerName: sellerName,
          isAvailable: stock > 0 && index % 31 != 2,
        );
        _listedAtById[id] = DateTime.utc(
          2025,
          10,
          1,
        ).add(Duration(hours: 6 * (index - 1)));
      }
    }

    for (final spec in _catalogSpecs) {
      final count = _productsById.values
          .where((product) => product.categoryId == spec.id)
          .length;
      _categories.add(
        CategoryModel(id: spec.id, name: spec.name, productCount: count),
      );
    }
  }

  static double _round2(double value) => (value * 100).round() / 100;

  static double _round1(double value) => (value * 10).round() / 10;

  // -----------------------------------------------------------------------
  // Request pipeline
  // -----------------------------------------------------------------------

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handleRequest(request);
    } on _ApiError catch (error) {
      await _fail(
        request,
        status: error.status,
        code: error.code,
        message: error.message,
        errors: error.errors,
        items: error.items,
      );
    } catch (error, stackTrace) {
      stderr.writeln(
        'MockMarketplaceServer: unhandled error for '
        '${request.method} ${request.uri.path}: $error\n$stackTrace',
      );
      try {
        await _fail(
          request,
          status: 500,
          code: 'internal',
          message: 'The mock backend hit an unexpected error.',
        );
      } catch (_) {
        // Headers were already on the wire; nothing left to do.
      }
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _requestCounter++;
    await _applyLatency();

    final forced = conditions._consumeForcedStatus();
    if (forced != null) {
      throw _ApiError(
        forced,
        'forced_status',
        'Simulated backend failure (HTTP $forced).',
      );
    }
    if (conditions.malformedNext) {
      conditions.malformedNext = false; // one-shot
      await _writeMalformed(request);
      return;
    }

    final segments = request.uri.path
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList();

    if (segments.isEmpty) {
      throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
    switch (segments.first) {
      case 'auth':
        return _handleAuth(request, segments);
      case 'categories':
        return _handleCategories(request);
      case 'products':
        return _handleProducts(request, segments);
      case 'favorites':
        return _handleFavorites(request, segments);
      case 'checkout':
        return _handleCheckout(request);
      case 'orders':
        return _handleOrders(request, segments);
      default:
        throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
  }

  /// Deterministic 150–300ms latency, cycling through six steps so repeated
  /// requests observe the whole range without any randomness.
  Future<void> _applyLatency() {
    final min = conditions.latencyMinMs;
    final max = conditions.latencyMaxMs;
    if (min <= 0 && max <= 0) return Future.value();
    final span = max - min;
    if (span <= 0) return Future.delayed(Duration(milliseconds: min));
    final step = _requestCounter % 6;
    final delay = min + (span * step / 5).round();
    return Future.delayed(Duration(milliseconds: delay));
  }

  // -----------------------------------------------------------------------
  // Handlers — auth
  // -----------------------------------------------------------------------

  Future<void> _handleAuth(HttpRequest request, List<String> segments) async {
    if (segments.length != 2) {
      throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
    switch (segments[1]) {
      case 'register':
        if (request.method == 'POST') return _handleRegister(request);
        break;
      case 'login':
        if (request.method == 'POST') return _handleLogin(request);
        break;
      case 'me':
        if (request.method == 'GET') {
          final user = _requireUser(request);
          await _ok(request, data: user.model.toJson());
          return;
        }
        break;
      default:
        break;
    }
    throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
  }

  Future<void> _handleRegister(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final name = body['name'];
    final email = body['email'];
    final password = body['password'];

    final fieldErrors = <String, List<String>>{};
    if (name is! String || name.trim().length < 2) {
      fieldErrors['name'] = ['Name must be at least 2 characters.'];
    }
    if (email is! String || !_emailRegex.hasMatch(email.trim())) {
      fieldErrors['email'] = ['Enter a valid email address.'];
    }
    if (password is! String || password.length < 8) {
      fieldErrors['password'] = ['Password must be at least 8 characters.'];
    }
    if (fieldErrors.isNotEmpty) {
      throw _ApiError(
        422,
        'validation',
        'Please review the highlighted fields.',
        errors: fieldErrors,
      );
    }

    final normalizedEmail = (email as String).trim().toLowerCase();
    if (_usersByEmail.containsKey(normalizedEmail)) {
      throw _ApiError(
        422,
        'validation',
        'Please review the highlighted fields.',
        errors: {
          'email': ['An account with this email already exists.'],
        },
      );
    }

    final user = _MockUser(
      model: UserModel(
        id: 'u${_userIdSeq++}',
        name: (name as String).trim(),
        email: normalizedEmail,
        memberSince: DateTime.utc(2026, 1, 15),
      ),
      password: password as String,
      token: 'tok-${_tokenSeq++}',
    );
    _usersByEmail[normalizedEmail] = user;
    _usersByToken[user.token] = user;

    await _ok(
      request,
      status: 201,
      data: {'token': user.token, 'user': user.model.toJson()},
    );
  }

  Future<void> _handleLogin(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final email = body['email'];
    final password = body['password'];
    if (email is! String || password is! String) {
      throw const _ApiError(
        400,
        'bad_request',
        'Email and password are required.',
      );
    }
    final user = _usersByEmail[email.trim().toLowerCase()];
    if (user == null || user.password != password) {
      throw const _ApiError(
        401,
        'invalid_credentials',
        'Invalid email or password.',
      );
    }
    await _ok(
      request,
      data: {'token': user.token, 'user': user.model.toJson()},
    );
  }

  // -----------------------------------------------------------------------
  // Handlers — catalog
  // -----------------------------------------------------------------------

  Future<void> _handleCategories(HttpRequest request) async {
    if (request.method != 'GET') {
      throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
    await _ok(request, data: [for (final c in _categories) c.toJson()]);
  }

  Future<void> _handleProducts(
    HttpRequest request,
    List<String> segments,
  ) async {
    if (request.method != 'GET') {
      throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
    if (segments.length == 1) return _handleProductList(request);
    if (segments.length == 2) {
      final product = _productsById[segments[1]];
      if (product == null) {
        throw const _ApiError(404, 'not_found', 'Unknown product.');
      }
      await _ok(request, data: product.toJson());
      return;
    }
    throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
  }

  Future<void> _handleProductList(HttpRequest request) async {
    final params = request.uri.queryParameters;

    final page = _requiredIntParam(params, 'page', defaultValue: 1);
    final pageSize = _requiredIntParam(
      params,
      'pageSize',
      defaultValue: 20,
      max: 100,
    );
    final sortRaw = params['sort'];
    final sort = sortRaw == null || sortRaw.isEmpty
        ? ProductSort.relevance
        : ProductSort.fromWireValue(sortRaw);
    if (sort == null) {
      throw _ApiError(400, 'bad_request', 'Unknown sort option "$sortRaw".');
    }

    final category = params['category'];
    final query = params['q']?.trim().toLowerCase();
    final minPrice = _optionalDoubleParam(params, 'minPrice');
    final maxPrice = _optionalDoubleParam(params, 'maxPrice');
    final inStock = _optionalBoolParam(params, 'inStock');
    if (minPrice != null && maxPrice != null && minPrice > maxPrice) {
      throw const _ApiError(
        400,
        'bad_request',
        'minPrice cannot be greater than maxPrice.',
      );
    }

    var products = _productsById.values.toList();
    if (category != null && category.isNotEmpty) {
      products = products
          .where((product) => product.categoryId == category)
          .toList();
    }
    if (minPrice != null) {
      products = products.where((p) => p.price >= minPrice).toList();
    }
    if (maxPrice != null) {
      products = products.where((p) => p.price <= maxPrice).toList();
    }
    if (inStock == true) {
      products = products.where((p) => p.stock > 0 && p.isAvailable).toList();
    }
    if (query != null && query.isNotEmpty) {
      products = products.where((p) => _matchesQuery(p, query)).toList();
    }

    products.sort(_comparatorFor(sort, query));

    final totalItems = products.length;
    final totalPages = totalItems == 0
        ? 0
        : (totalItems + pageSize - 1) ~/ pageSize;
    final items = products
        .skip((page - 1) * pageSize)
        .take(pageSize)
        .map((product) => product.toJson())
        .toList();

    await _ok(
      request,
      data: {
        'items': items,
        'page': page,
        'pageSize': pageSize,
        'totalPages': totalPages,
        'totalItems': totalItems,
        'hasMore': page < totalPages,
      },
    );
  }

  bool _matchesQuery(ProductModel product, String query) {
    final title = product.title.toLowerCase();
    if (title.contains(query)) return true;
    if (product.description.toLowerCase().contains(query)) return true;
    final categoryName = _categoryNameById(product.categoryId);
    return categoryName != null && categoryName.toLowerCase().contains(query);
  }

  String? _categoryNameById(String categoryId) {
    for (final category in _categories) {
      if (category.id == categoryId) return category.name;
    }
    return null;
  }

  int Function(ProductModel, ProductModel) _comparatorFor(
    ProductSort sort,
    String? query,
  ) {
    switch (sort) {
      case ProductSort.relevance:
        if (query != null && query.isNotEmpty) {
          return (a, b) {
            final scoreA = _textScore(a, query);
            final scoreB = _textScore(b, query);
            if (scoreA != scoreB) return scoreB.compareTo(scoreA);
            return b.id.compareTo(a.id);
          };
        }
        return (a, b) {
          final scoreA = _popularity(a);
          final scoreB = _popularity(b);
          if (scoreA != scoreB) return scoreB.compareTo(scoreA);
          return b.id.compareTo(a.id);
        };
      case ProductSort.newest:
        return (a, b) {
          final timeA = _listedAtById[a.id]!;
          final timeB = _listedAtById[b.id]!;
          if (timeA != timeB) return timeB.compareTo(timeA);
          return b.id.compareTo(a.id);
        };
      case ProductSort.priceAsc:
        return (a, b) {
          if (a.price != b.price) return a.price.compareTo(b.price);
          return a.id.compareTo(b.id);
        };
      case ProductSort.priceDesc:
        return (a, b) {
          if (a.price != b.price) return b.price.compareTo(a.price);
          return a.id.compareTo(b.id);
        };
      case ProductSort.rating:
        return (a, b) {
          if (a.rating != b.rating) return b.rating.compareTo(a.rating);
          if (a.reviewCount != b.reviewCount) {
            return b.reviewCount.compareTo(a.reviewCount);
          }
          return a.id.compareTo(b.id);
        };
    }
  }

  /// Popularity heuristic for the default (queryless) relevance order.
  double _popularity(ProductModel product) =>
      product.rating * log(product.reviewCount + 1);

  double _textScore(ProductModel product, String query) {
    final title = product.title.toLowerCase();
    var score = 0.0;
    if (title.contains(query)) score += 100;
    if (title.startsWith(query)) score += 50;
    if (product.description.toLowerCase().contains(query)) score += 10;
    return score + _popularity(product) * 0.001;
  }

  // -----------------------------------------------------------------------
  // Handlers — favorites
  // -----------------------------------------------------------------------

  Future<void> _handleFavorites(
    HttpRequest request,
    List<String> segments,
  ) async {
    final user = _requireUser(request);
    final favorites = _favoritesByEmail.putIfAbsent(
      user.model.email,
      () => <String>{},
    );

    if (request.method == 'GET' && segments.length == 1) {
      final items = _productsById.values
          .where((product) => favorites.contains(product.id))
          .map((product) => product.toJson())
          .toList();
      await _ok(request, data: items);
      return;
    }

    if ((request.method == 'POST' || request.method == 'DELETE') &&
        segments.length == 2) {
      final productId = segments[1];
      if (!_productsById.containsKey(productId)) {
        throw const _ApiError(404, 'not_found', 'Unknown product.');
      }
      if (request.method == 'POST') {
        favorites.add(productId);
        await _ok(
          request,
          status: 201,
          data: {'productId': productId, 'favorited': true},
        );
      } else {
        favorites.remove(productId);
        await _ok(request, data: {'productId': productId, 'favorited': false});
      }
      return;
    }

    throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
  }

  // -----------------------------------------------------------------------
  // Handlers — checkout & orders
  // -----------------------------------------------------------------------

  Future<void> _handleCheckout(HttpRequest request) async {
    if (request.method != 'POST') {
      throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
    }
    final user = _requireUser(request);
    final body = await _readJsonBody(request);

    final rawItems = body['items'];
    if (rawItems is! List || rawItems.isEmpty) {
      throw _ApiError(
        422,
        'validation',
        'Your cart is empty.',
        errors: {
          'items': ['Your cart is empty.'],
        },
      );
    }

    final rawAddress = body['address'];
    if (rawAddress is! Map<String, dynamic>) {
      throw _ApiError(
        422,
        'validation',
        'A shipping address is required.',
        errors: {
          'address': ['A shipping address is required.'],
        },
      );
    }
    final addressErrors = _validateAddress(rawAddress);
    if (addressErrors.isNotEmpty) {
      throw _ApiError(
        422,
        'validation',
        'Please review the highlighted fields.',
        errors: addressErrors,
      );
    }

    final paymentRaw = body['paymentMethod'];
    final payment = paymentRaw is String
        ? PaymentMethod.fromWireName(paymentRaw)
        : null;
    if (payment == null) {
      throw const _ApiError(
        400,
        'bad_payment_method',
        'Unsupported payment method.',
      );
    }

    final entries = <(String, int)>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) {
        throw const _ApiError(
          400,
          'bad_request',
          'Each cart item must be an object.',
        );
      }
      final productId = raw['productId'];
      if (productId is! String || !_productsById.containsKey(productId)) {
        throw const _ApiError(
          400,
          'unknown_product',
          'Your cart contains a product that no longer exists.',
        );
      }
      final quantity = raw['quantity'];
      if (quantity is! num ||
          quantity.toInt() < 1 ||
          quantity.toInt() > CartItem.maxQuantity) {
        throw _ApiError(
          422,
          'validation',
          'Please review the highlighted fields.',
          errors: {
            'items': [
              'Quantities must be between 1 and ${CartItem.maxQuantity}.',
            ],
          },
        );
      }
      entries.add((productId, quantity.toInt()));
    }

    if (conditions.failCheckoutWithOutOfStock) {
      throw _ApiError(
        409,
        'out_of_stock',
        'Some items in your cart are no longer available.',
        items: [for (final (productId, _) in entries) productId],
      );
    }

    final outOfStock = [
      for (final (productId, quantity) in entries)
        if (!_productsById[productId]!.isAvailable ||
            _productsById[productId]!.stock < quantity)
          productId,
    ];
    if (outOfStock.isNotEmpty) {
      throw _ApiError(
        409,
        'out_of_stock',
        'Some items in your cart are no longer available.',
        items: outOfStock,
      );
    }

    final cartItems = [
      for (final (productId, quantity) in entries)
        CartItem(
          product: _productsById[productId]!.toDomain(),
          quantity: quantity,
        ),
    ];
    final totals = computeCartTotals(cartItems);
    final placedAt = _nextOrderPlacedAt();

    final order = OrderModel(
      id: 'o${_orderIdSeq++}',
      status: OrderStatus.pending,
      items: [for (final item in cartItems) CartItemModel.fromDomain(item)],
      subtotal: totals.subtotal,
      shipping: totals.shipping,
      tax: totals.tax,
      total: totals.total,
      address: AddressModel.fromJson(rawAddress),
      placedAt: placedAt,
      estimatedDelivery: placedAt.add(const Duration(days: 4, hours: 6)),
    );
    _ordersByEmail.putIfAbsent(user.model.email, () => []).add(order);

    // Purchased units leave the warehouse.
    for (final (productId, quantity) in entries) {
      final product = _productsById[productId]!;
      _productsById[productId] = ProductModel(
        id: product.id,
        title: product.title,
        description: product.description,
        price: product.price,
        compareAtPrice: product.compareAtPrice,
        imageUrls: product.imageUrls,
        rating: product.rating,
        reviewCount: product.reviewCount,
        stock: product.stock - quantity,
        categoryId: product.categoryId,
        sellerName: product.sellerName,
        isAvailable: product.stock - quantity > 0 && product.isAvailable,
      );
    }

    await _ok(request, status: 201, data: order.toJson());
  }

  Map<String, List<String>> _validateAddress(Map<String, dynamic> address) {
    final errors = <String, List<String>>{};
    void check(String key, String label, int minLength) {
      final value = address[key];
      if (value is! String || value.trim().length < minLength) {
        errors[key] = ['$label is required.'];
      }
    }

    check('fullName', 'Full name', 2);
    check('street', 'Street address', 4);
    check('city', 'City', 2);
    check('state', 'State', 2);
    check('zip', 'ZIP code', 3);
    check('phone', 'Phone number', 7);
    return errors;
  }

  Future<void> _handleOrders(HttpRequest request, List<String> segments) async {
    final user = _requireUser(request);
    final orders = _ordersByEmail[user.model.email] ?? const <OrderModel>[];

    if (request.method == 'GET' && segments.length == 1) {
      final newestFirst = orders.reversed.toList();
      await _ok(
        request,
        data: [for (final order in newestFirst) order.toJson()],
      );
      return;
    }
    if (request.method == 'GET' && segments.length == 2) {
      for (final order in orders) {
        if (order.id == segments[1]) {
          await _ok(request, data: order.toJson());
          return;
        }
      }
      throw const _ApiError(404, 'not_found', 'Unknown order.');
    }
    throw const _ApiError(404, 'not_found', 'Unknown endpoint.');
  }

  // -----------------------------------------------------------------------
  // Helpers — auth, params, responses
  // -----------------------------------------------------------------------

  static final _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  _MockUser _requireUser(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth == null || !auth.startsWith('Bearer ')) {
      throw const _ApiError(401, 'unauthorized', 'Authentication required.');
    }
    final token = auth.substring('Bearer '.length).trim();
    final user = _usersByToken[token];
    if (user == null) {
      throw const _ApiError(401, 'unauthorized', 'Authentication required.');
    }
    return user;
  }

  int _requiredIntParam(
    Map<String, String> params,
    String key, {
    required int defaultValue,
    int? max,
  }) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) return defaultValue;
    final value = int.tryParse(raw);
    if (value == null || value < 1) {
      throw _ApiError(400, 'bad_request', '"$key" must be a positive integer.');
    }
    if (max != null && value > max) {
      throw _ApiError(400, 'bad_request', '"$key" cannot exceed $max.');
    }
    return value;
  }

  double? _optionalDoubleParam(Map<String, String> params, String key) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) return null;
    final value = double.tryParse(raw);
    if (value == null) {
      throw _ApiError(400, 'bad_request', '"$key" must be a number.');
    }
    return value;
  }

  bool? _optionalBoolParam(Map<String, String> params, String key) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) return null;
    switch (raw.toLowerCase()) {
      case 'true':
      case '1':
        return true;
      case 'false':
      case '0':
        return false;
      default:
        throw _ApiError(400, 'bad_request', '"$key" must be true or false.');
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) {
      throw const _ApiError(400, 'invalid_json', 'Request body must be JSON.');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const _ApiError(
        400,
        'invalid_json',
        'Request body is not valid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const _ApiError(
        400,
        'invalid_json',
        'Request body must be a JSON object.',
      );
    }
    return decoded;
  }

  Future<void> _ok(
    HttpRequest request, {
    int status = 200,
    required Object? data,
  }) {
    return _writeJson(request, status, {'data': data});
  }

  Future<void> _fail(
    HttpRequest request, {
    required int status,
    required String code,
    required String message,
    Map<String, List<String>>? errors,
    List<String>? items,
  }) {
    final error = <String, dynamic>{'code': code, 'message': message};
    if (errors != null && errors.isNotEmpty) error['errors'] = errors;
    if (items != null && items.isNotEmpty) error['items'] = items;
    return _writeJson(request, status, {'error': error});
  }

  /// Answers HTTP 200 with an invalid-JSON body (content-type stays JSON so
  /// the client's decoder is genuinely exercised).
  Future<void> _writeMalformed(HttpRequest request) {
    return _writeRaw(
      request,
      200,
      'not-json: {{{ this payload is intentionally malformed',
    );
  }

  Future<void> _writeJson(HttpRequest request, int status, Object body) {
    return _writeRaw(request, status, jsonEncode(body));
  }

  Future<void> _writeRaw(HttpRequest request, int status, String body) async {
    final response = request.response;
    final bytes = utf8.encode(body);
    response.statusCode = status;
    response.headers.set(
      HttpHeaders.contentTypeHeader,
      'application/json; charset=utf-8',
    );
    response.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
    response.add(bytes);
    await response.close();
  }
}

/// In-memory user record (credentials never leave the server).
class _MockUser {
  _MockUser({required this.model, required this.password, required this.token});

  final UserModel model;
  final String password;
  final String token;
}

/// Internal control-flow exception: handlers throw, the pipeline answers.
class _ApiError implements Exception {
  const _ApiError(
    this.status,
    this.code,
    this.message, {
    this.errors,
    this.items,
  });

  final int status;
  final String code;
  final String message;
  final Map<String, List<String>>? errors;
  final List<String>? items;
}

// ---------------------------------------------------------------------------
// Seeded catalog specification (66 products across 6 categories).
// ---------------------------------------------------------------------------

class _CategorySpec {
  const _CategorySpec(this.id, this.name, this.items);

  final String id;
  final String name;
  final List<_ItemSpec> items;
}

class _ItemSpec {
  const _ItemSpec(this.title, this.basePrice);

  final String title;
  final double basePrice;
}

const List<String> _descriptions = [
  'A dependable everyday pick from {seller}. Built to last, restocked weekly, and backed by a 12-month warranty.',
  'The {title} pairs practical design with careful finishing — a quiet favorite among MarketFlow regulars.',
  'Carefully sourced by {seller}, the {title} balances quality and price for everyday use.',
  'Small details make the difference: the {title} is checked before shipping and rated by verified buyers.',
];

const Map<String, List<String>> _sellersByCategory = {
  'c1': ['Northgate Audio', 'Voltaic Labs', 'Pixel & Byte'],
  'c2': ['Ember Home Goods', 'Hearth & Grain', 'Nordic Kitchen Co.'],
  'c3': ['Summit Outfitters', 'PeakForm Athletics', 'Trailhead Supply'],
  'c4': ['Loom & Thread', 'Meridian Apparel', 'Harbor Textiles'],
  'c5': ['Foxglove Press', 'Paper Lantern Books', 'Inkwright House'],
  'c6': ['Petal Botanics', 'Bloom Skin Lab', 'Meadow Beauty Co.'],
};

const List<_CategorySpec> _catalogSpecs = [
  _CategorySpec('c1', 'Electronics', [
    _ItemSpec('Aurora Wireless Noise-Cancelling Earbuds', 129.99),
    _ItemSpec('Nimbus 10-inch Tablet', 279.0),
    _ItemSpec('Volt Pro Smartwatch', 199.5),
    _ItemSpec('Lumen 4K Action Camera', 249.99),
    _ItemSpec('Pulse Bluetooth Speaker', 59.99),
    _ItemSpec('Vertex Mechanical Keyboard', 119.0),
    _ItemSpec('Halo Wireless Charging Pad', 34.99),
    _ItemSpec('Circuit USB-C Docking Station', 89.5),
    _ItemSpec('Echo Studio Over-Ear Headphones', 179.99),
    _ItemSpec('Photon Mirrorless Camera', 1899.0),
    _ItemSpec('Grid Portable Power Bank 20000mAh', 45.99),
  ]),
  _CategorySpec('c2', 'Home & Kitchen', [
    _ItemSpec('Ember Cast Iron Skillet 12 inch', 49.95),
    _ItemSpec('Cascade Pour-Over Coffee Set', 42.5),
    _ItemSpec('Nordic Ceramic Dinner Set', 89.99),
    _ItemSpec('Verde Chef Knife 8 inch', 69.0),
    _ItemSpec('Solace Memory Foam Pillow 2-Pack', 39.99),
    _ItemSpec('Terra Stainless Cookware Set', 229.0),
    _ItemSpec('Brew Ritual French Press', 32.5),
    _ItemSpec('Fjord Linen Duvet Cover', 119.0),
    _ItemSpec('Alpine Air Purifier', 179.5),
    _ItemSpec('Meadow Hand-Blown Glass Vase', 27.99),
    _ItemSpec('Copper Ritual Kettle', 58.0),
  ]),
  _CategorySpec('c3', 'Sports', [
    _ItemSpec('Summit Trail Running Shoes', 139.99),
    _ItemSpec('Apex Adjustable Dumbbells 55 lb', 349.0),
    _ItemSpec('Zen Pro Yoga Mat', 38.5),
    _ItemSpec('Cascade Carbon Trekking Poles', 79.99),
    _ItemSpec('Velocity Road Bike Helmet', 65.0),
    _ItemSpec('Ridge Insulated Water Bottle', 24.99),
    _ItemSpec('Flex Resistance Band Set', 19.99),
    _ItemSpec('Stratosphere Camping Tent 4P', 299.0),
    _ItemSpec('Torque Indoor Cycling Trainer', 279.5),
    _ItemSpec('Aqua Glide Swim Goggles', 18.99),
    _ItemSpec('Peak Climbing Chalk Bag', 14.99),
  ]),
  _CategorySpec('c4', 'Fashion', [
    _ItemSpec('Meridian Wool Overcoat', 349.0),
    _ItemSpec('Atlas Leather Weekender Bag', 289.99),
    _ItemSpec('Cove Linen Summer Dress', 89.5),
    _ItemSpec('Rowan Cashmere Sweater', 159.0),
    _ItemSpec('Drift Canvas Sneakers', 74.99),
    _ItemSpec('Horizon Silk Scarf', 48.0),
    _ItemSpec('Sterling Minimal Watch', 199.99),
    _ItemSpec('Harbor Rain Jacket', 129.5),
    _ItemSpec('Loom Raw Denim Jacket', 118.0),
    _ItemSpec('Vela Polarized Sunglasses', 84.99),
    _ItemSpec('Northside Leather Belt', 39.5),
  ]),
  _CategorySpec('c5', 'Books', [
    _ItemSpec('The Architecture of Everyday Things', 24.99),
    _ItemSpec('Midnight in the Archive', 18.99),
    _ItemSpec('Recipes from the Ember Kitchen', 32.5),
    _ItemSpec('The Quiet Algorithm', 21.99),
    _ItemSpec('Atlas of Forgotten Coastlines', 39.99),
    _ItemSpec('Gardening by Moonlight', 16.99),
    _ItemSpec('The Last Cartographer', 26.0),
    _ItemSpec('Threads of the Silk Road', 22.5),
    _ItemSpec('Small Habits, Deep Roots', 19.99),
    _ItemSpec('The Ocean Between Us', 15.99),
    _ItemSpec('Notes from a Slow City', 23.0),
  ]),
  _CategorySpec('c6', 'Beauty', [
    _ItemSpec('Petal Hydrating Serum', 34.99),
    _ItemSpec('Clay Ritual Face Mask', 21.5),
    _ItemSpec('Bloom Vitamin C Cream', 42.0),
    _ItemSpec('Silk Argan Hair Oil', 26.99),
    _ItemSpec('Dawn SPF 50 Sunscreen', 18.99),
    _ItemSpec('Meadow Botanical Body Lotion', 14.99),
    _ItemSpec('Luxe 12-Piece Brush Set', 59.5),
    _ItemSpec('Amber Perfume Rollerball', 48.0),
    _ItemSpec('Gentle Foaming Cleanser', 17.99),
    _ItemSpec('Rose Water Facial Mist', 12.99),
    _ItemSpec('Cocoa Shea Body Butter', 9.99),
  ]),
];
