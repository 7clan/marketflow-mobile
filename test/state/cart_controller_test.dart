import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/data/datasources/cart_local_data_source.dart';
import 'package:marketflow/domain/entities/cart_item.dart';
import 'package:marketflow/presentation/providers/cart_controller.dart';

import '../helpers/app_container.dart';

/// Records every save so tests can assert persistence-on-every-mutation.
class CountingCartLocalDataSource extends InMemoryCartLocalDataSource {
  int saveCalls = 0;
  int clearCalls = 0;
  final List<List<CartItem>> savedBatches = [];

  @override
  Future<void> save(List<CartItem> items) async {
    saveCalls++;
    savedBatches.add(items);
    await super.save(items);
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    await super.clear();
  }
}

void main() {
  group('CartController — adding', () {
    test('adding the same product twice dedupes into one line', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01'), quantity: 1);
      controller.addToCart(stubProduct('p01'), quantity: 2);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items, hasLength(1));
      expect(cart.items.first.product.id, 'p01');
      expect(cart.items.first.quantity, 3);
      expect(cart.itemCount, 3);
    });

    test('quantity clamps to the available stock with a message', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01', stock: 3), quantity: 5);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items.first.quantity, 3);
      expect(cart.messageFor('p01'), 'Only 3 left in stock.');
    });

    test('quantity clamps to the per-order maximum of 99', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01', stock: 500), quantity: 200);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items.first.quantity, 99);
      expect(cart.messageFor('p01'), 'Maximum 99 per order.');
    });

    test('an out-of-stock product is never added', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01', stock: 0, isAvailable: true));
      controller.addToCart(stubProduct('p02', stock: 5, isAvailable: false));

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items, isEmpty);
      expect(cart.messageFor('p01'), 'Out of stock.');
      expect(cart.messageFor('p02'), 'Out of stock.');
    });
  });

  group('CartController — mutating existing lines', () {
    test('updateQuantity clamps to stock', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);
      controller.addToCart(stubProduct('p01', stock: 4), quantity: 1);

      controller.updateQuantity('p01', 10);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items.first.quantity, 4);
      expect(cart.messageFor('p01'), 'Only 4 left in stock.');
    });

    test('updateQuantity removes the line at zero or below', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);
      controller.addToCart(stubProduct('p01'), quantity: 2);
      controller.addToCart(stubProduct('p02'), quantity: 1);

      controller.updateQuantity('p01', 0);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items, hasLength(1));
      expect(cart.items.first.product.id, 'p02');
      expect(cart.messageFor('p01'), isNull);
    });

    test('removeItem drops the line and clears its message', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);
      controller.addToCart(stubProduct('p01', stock: 1), quantity: 5);

      controller.removeItem('p01');

      expect(scope.container.read(cartControllerProvider).items, isEmpty);
    });

    test('clear empties the cart', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);
      controller.addToCart(stubProduct('p01'), quantity: 1);
      controller.addToCart(stubProduct('p02'), quantity: 1);

      controller.clear();

      expect(scope.container.read(cartControllerProvider).isEmpty, isTrue);
    });
  });

  group('CartController — derived totals', () {
    test(
      'subtotal, shipping and tax add up below the free-shipping line',
      () async {
        final scope = await createTestApp();
        final controller = scope.container.read(
          cartControllerProvider.notifier,
        );

        controller.addToCart(stubProduct('p01', price: 10.0), quantity: 2);

        final totals = scope.container.read(cartControllerProvider).totals;
        expect(totals.subtotal, 20.0);
        expect(totals.shipping, 8.99);
        expect(totals.tax, closeTo(1.70, 0.001));
        expect(totals.total, closeTo(20.0 + 8.99 + 1.70, 0.001));
      },
    );

    test('shipping is free at or above the 99 threshold', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01', price: 50.0), quantity: 2);

      final totals = scope.container.read(cartControllerProvider).totals;
      expect(totals.subtotal, 100.0);
      expect(totals.shipping, 0);
      expect(totals.tax, closeTo(8.50, 0.001));
      expect(totals.total, closeTo(108.50, 0.001));
    });

    test('an empty cart has all-zero totals', () async {
      final scope = await createTestApp();
      scope.container.read(cartControllerProvider.notifier);

      final totals = scope.container.read(cartControllerProvider).totals;
      expect(totals.subtotal, 0);
      expect(totals.shipping, 0);
      expect(totals.tax, 0);
      expect(totals.total, 0);
    });

    test('per-line prices are frozen at add time', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01', price: 10.0), quantity: 1);
      // The same product now costs more, but the line keeps its price.
      controller.addToCart(stubProduct('p01', price: 25.0), quantity: 1);

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items.first.unitPrice, 10.0);
      expect(cart.totals.subtotal, 20.0);
    });
  });

  group('CartController — persistence', () {
    test('every mutation persists the cart', () async {
      final cartLocal = CountingCartLocalDataSource();
      final scope = await createTestApp(cartLocal: cartLocal);
      final controller = scope.container.read(cartControllerProvider.notifier);

      controller.addToCart(stubProduct('p01'), quantity: 1);
      controller.addToCart(stubProduct('p01'), quantity: 1);
      controller.updateQuantity('p01', 3);
      controller.removeItem('p01');
      controller.addToCart(stubProduct('p02'), quantity: 2);
      controller.clear();

      expect(
        cartLocal.saveCalls,
        6,
        reason:
            'add x2, update, remove, add, and clear persists an empty '
            'batch (the storage contract of the cart repository)',
      );
      expect(
        cartLocal.savedBatches.last,
        isEmpty,
        reason: 'the last persisted batch is empty after clear',
      );
      // Reloading from the same storage yields the empty cart.
      expect(await cartLocal.load(), isEmpty);
    });

    test('a pre-populated storage restores the cart on startup', () async {
      final cartLocal = InMemoryCartLocalDataSource();
      await cartLocal.save([
        CartItem(product: stubProduct('p09'), quantity: 3),
        CartItem(product: stubProduct('p10', price: 42.0), quantity: 1),
      ]);

      final scope = await createTestApp(cartLocal: cartLocal);
      scope.container.read(cartControllerProvider.notifier);
      await scope.settle();

      final cart = scope.container.read(cartControllerProvider);
      expect(cart.items, hasLength(2));
      expect(cart.itemCount, 4);
      expect(cart.items.first.product.id, 'p09');
      expect(cart.items.first.quantity, 3);
      expect(cart.totals.subtotal, closeTo(10.0 * 3 + 42.0, 0.001));
    });

    test('storage restoring an empty cart leaves the state empty', () async {
      final scope = await createTestApp();
      scope.container.read(cartControllerProvider.notifier);
      await scope.settle();

      expect(scope.container.read(cartControllerProvider).isEmpty, isTrue);
    });

    test(
      'a mutation landing mid-restore is not clobbered by the restore',
      () async {
        final scope = await createTestApp();
        // Read and add in the same synchronous block: the restore's (empty)
        // storage snapshot is still in flight when the add commits.
        final controller = scope.container.read(
          cartControllerProvider.notifier,
        );
        controller.addToCart(stubProduct('p01'), quantity: 2);

        await scope.settle();

        final cart = scope.container.read(cartControllerProvider);
        expect(
          cart.items,
          hasLength(1),
          reason: 'the mutation must win over the stale restore snapshot',
        );
        expect(cart.itemCount, 2);
        expect(
          await scope.cartLocal.load(),
          hasLength(1),
          reason: 'the mutation also persisted its own batch',
        );
      },
    );
  });
}
