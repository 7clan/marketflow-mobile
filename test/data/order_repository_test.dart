import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/repositories/order_repository_impl.dart';
import 'package:marketflow/data/repositories/product_repository_impl.dart';
import 'package:marketflow/domain/entities/address.dart';
import 'package:marketflow/domain/entities/cart_item.dart';
import 'package:marketflow/domain/entities/order.dart';
import 'package:marketflow/domain/entities/product.dart';

import '../helpers/mock_api.dart';

const _demoToken = 'tok-demo-1';

Address _address() => const Address(
  fullName: 'Dana Mercado',
  street: '482 Harbor Lane',
  city: 'Portland',
  state: 'OR',
  zip: '97201',
  phone: '+1 503 555 0148',
);

Product _product() => const Product(
  id: 'p01',
  title: 'Aurora Wireless Noise-Cancelling Earbuds',
  description: 'A dependable everyday pick.',
  price: 129.99,
  imageUrls: ['https://example.com/1.jpg'],
  rating: 4.6,
  reviewCount: 321,
  stock: 42,
  categoryId: 'c1',
  sellerName: 'Northgate Audio',
  isAvailable: true,
);

void main() {
  late MockApiHarness api;
  late OrderRepositoryImpl repository;

  setUp(() async {
    api = await startMockApi(token: _demoToken);
    addTearDown(api.dispose);
    repository = OrderRepositoryImpl(apiClient: api.apiClient);
  });

  group('placeOrder', () {
    test('an empty cart is rejected with ValidationException', () async {
      await expectLater(
        repository.placeOrder(
          items: const <CartItem>[],
          address: _address(),
          paymentMethod: PaymentMethod.card,
        ),
        throwsA(
          isA<ValidationException>().having(
            (error) => error.fieldErrors['items'],
            'fieldErrors[items]',
            ['Your cart is empty.'],
          ),
        ),
      );
    });

    test('a successful checkout creates a pending order with server-priced '
        'totals', () async {
      // The backend re-prices the order from its own catalog, so the expected
      // totals derive from the server's current price for p01.
      final products = ProductRepositoryImpl(apiClient: api.apiClient);
      final catalogProduct = await products.getProduct('p01');

      final order = await repository.placeOrder(
        items: [CartItem(product: catalogProduct, quantity: 2)],
        address: _address(),
        paymentMethod: PaymentMethod.card,
      );

      expect(order.id, 'o1003');
      expect(order.status, OrderStatus.pending);
      expect(order.itemCount, 2);
      expect(order.items, hasLength(1));
      expect(order.items.first.quantity, 2);
      expect(order.subtotal, closeTo(catalogProduct.price * 2, 0.01));
      expect(
        order.total,
        closeTo(order.subtotal + order.shipping + order.tax, 0.01),
      );
      expect(order.address.city, 'Portland');
      expect(order.placedAt, isNotNull);
      expect(order.estimatedDelivery.isAfter(order.placedAt), isTrue);
    });

    test('the placed order immediately appears in the order history', () async {
      await repository.placeOrder(
        items: [CartItem(product: _product(), quantity: 1)],
        address: _address(),
        paymentMethod: PaymentMethod.card,
      );

      final orders = await repository.getOrders();

      expect(orders, hasLength(3), reason: '2 seeded + 1 new order');
      expect(orders.first.id, 'o1003', reason: 'history is newest-first');
      expect(orders.map((order) => order.id), containsAll(['o1001', 'o1002']));
    });

    test('checkout decrements the purchased stock server-side', () async {
      final products = ProductRepositoryImpl(apiClient: api.apiClient);
      final before = await products.getProduct('p01');

      await repository.placeOrder(
        items: [CartItem(product: _product(), quantity: 3)],
        address: _address(),
        paymentMethod: PaymentMethod.card,
      );

      final after = await products.getProduct('p01');
      expect(after.stock, before.stock - 3);
    });

    test(
      'a forced 500 surfaces ServerException with the status code',
      () async {
        api.server.conditions.forceStatusNext(1, 500);

        await expectLater(
          repository.placeOrder(
            items: [CartItem(product: _product(), quantity: 1)],
            address: _address(),
            paymentMethod: PaymentMethod.card,
          ),
          throwsA(
            isA<ServerException>().having(
              (error) => error.statusCode,
              'statusCode',
              500,
            ),
          ),
        );
      },
    );

    test(
      'a forced out-of-stock conflict surfaces ConflictException with ids',
      () async {
        api.server.conditions.failCheckoutWithOutOfStock = true;

        await expectLater(
          repository.placeOrder(
            items: [CartItem(product: _product(), quantity: 1)],
            address: _address(),
            paymentMethod: PaymentMethod.card,
          ),
          throwsA(
            isA<ConflictException>()
                .having(
                  (error) => error.conflictingItems,
                  'conflictingItems',
                  contains('p01'),
                )
                .having(
                  (error) => error.message,
                  'message',
                  'Some items in your cart are no longer available.',
                ),
          ),
        );
      },
    );

    test('a malformed response surfaces MalformedResponseException', () async {
      api.server.conditions.malformedNext = true;

      await expectLater(
        repository.placeOrder(
          items: [CartItem(product: _product(), quantity: 1)],
          address: _address(),
          paymentMethod: PaymentMethod.card,
        ),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('a response slower than receiveTimeout surfaces TimeoutException '
        'without hanging', () async {
      // Dedicated harness: 2500ms server latency vs a 600ms client timeout.
      final slowApi = await startMockApi(
        token: _demoToken,
        receiveTimeout: const Duration(milliseconds: 600),
      );
      addTearDown(slowApi.dispose);
      slowApi.server.conditions.latencyMinMs = 2500;
      slowApi.server.conditions.latencyMaxMs = 2500;
      final slowRepository = OrderRepositoryImpl(apiClient: slowApi.apiClient);

      await expectLater(
        slowRepository.getOrders(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'requests without a token are rejected as UnauthorizedException',
      () async {
        final anonymous = await startMockApi();
        addTearDown(anonymous.dispose);
        final anonymousRepository = OrderRepositoryImpl(
          apiClient: anonymous.apiClient,
        );

        await expectLater(
          anonymousRepository.getOrders(),
          throwsA(
            isA<UnauthorizedException>().having(
              (error) => error.message,
              'message',
              'Authentication required.',
            ),
          ),
        );
      },
    );
  });

  group('getOrders / getOrder', () {
    test('the demo account lists its two seeded orders newest-first', () async {
      final orders = await repository.getOrders();

      expect(orders, hasLength(2));
      expect(orders.first.id, 'o1002');
      expect(orders.first.status, OrderStatus.shipped);
      expect(orders.last.id, 'o1001');
      expect(orders.last.status, OrderStatus.delivered);
    });

    test('a single order is fetched by id', () async {
      final order = await repository.getOrder('o1001');

      expect(order.id, 'o1001');
      expect(order.items, isNotEmpty);
      expect(order.address, isNotNull);
    });

    test('an unknown order id surfaces NotFoundException', () async {
      await expectLater(
        repository.getOrder('o9999'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
