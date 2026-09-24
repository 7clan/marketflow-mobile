import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/domain/entities/address.dart';
import 'package:marketflow/presentation/providers/auth_controller.dart';
import 'package:marketflow/presentation/providers/cart_controller.dart';
import 'package:marketflow/presentation/providers/checkout_controller.dart';
import 'package:marketflow/presentation/providers/orders_controller.dart';

import '../helpers/app_container.dart';

const _validAddress = Address(
  fullName: 'Dana Mercado',
  street: '123 Market Street',
  city: 'San Francisco',
  state: 'California',
  zip: '94103',
  country: 'United States',
  phone: '+1 415 555 0100',
);

void main() {
  /// Checkout is an auto-dispose flow: hold a subscription so the controller
  /// survives the whole test (the UI's Consumer stands in for it).
  late TestAppScope scope;
  late ProviderSubscription<CheckoutState> checkoutSub;

  setUp(() async {
    scope = await createTestApp();
    checkoutSub = scope.container.listen(checkoutControllerProvider, (_, _) {});
  });

  tearDown(() {
    checkoutSub.close();
  });

  CheckoutState checkout() => scope.container.read(checkoutControllerProvider);

  Future<void> signInAndFillCart() async {
    await scope.container
        .read(authControllerProvider.notifier)
        .login(email: 'demo@marketflow.dev', password: 'Password123');
    scope.container
        .read(cartControllerProvider.notifier)
        .addToCart(stubProduct('p01', price: 10.0), quantity: 2);
  }

  group('CheckoutController — address validation', () {
    test('an invalid address blocks the flow with per-field errors', () async {
      await signInAndFillCart();
      final controller = scope.container.read(
        checkoutControllerProvider.notifier,
      );

      controller.submitAddress(
        const Address(
          fullName: '',
          street: 'x',
          city: '',
          state: '',
          zip: '1',
          phone: 'abc',
        ),
      );

      final state = checkout();
      expect(
        state.step,
        CheckoutStep.editingAddress,
        reason: 'invalid input must not advance to review',
      );
      expect(state.fieldErrors['fullName'], 'Name is required.');
      expect(state.fieldErrors['street'], 'Enter a complete street address.');
      expect(state.fieldErrors['city'], 'City is required.');
      expect(state.fieldErrors['state'], 'State is required.');
      expect(state.fieldErrors['zip'], 'Enter a valid ZIP code.');
      expect(state.fieldErrors['phone'], 'Enter a valid phone number.');
      expect(
        state.address,
        isNotNull,
        reason: 'the typed values are kept for correction',
      );
    });

    test(
      'a valid address advances to the review step with no errors',
      () async {
        await signInAndFillCart();
        final controller = scope.container.read(
          checkoutControllerProvider.notifier,
        );

        controller.submitAddress(_validAddress);

        final state = checkout();
        expect(state.step, CheckoutStep.reviewing);
        expect(state.fieldErrors, isEmpty);
        expect(state.address, _validAddress);
      },
    );

    test('backToEditing returns to the form and clears the errors', () async {
      await signInAndFillCart();
      final controller = scope.container.read(
        checkoutControllerProvider.notifier,
      );
      controller.submitAddress(_validAddress);

      controller.backToEditing();

      expect(checkout().step, CheckoutStep.editingAddress);
      expect(checkout().fieldErrors, isEmpty);
      expect(
        checkout().address,
        _validAddress,
        reason: 'the entered address survives the round-trip',
      );
    });
  });

  group('CheckoutController — placing the order', () {
    test(
      'the happy path places the order, exposes the id and clears the cart',
      () async {
        await signInAndFillCart();
        final controller = scope.container.read(
          checkoutControllerProvider.notifier,
        );
        controller.submitAddress(_validAddress);

        await controller.confirmAndPlaceOrder();

        final state = checkout();
        expect(state.step, CheckoutStep.success);
        expect(state.orderId, isNotNull);
        expect(state.error, isNull);
        expect(
          scope.container.read(cartControllerProvider).isEmpty,
          isTrue,
          reason: 'a placed order must empty the cart',
        );

        // And the order is retrievable through the orders controller.
        final ordersSub = scope.container.listen(
          ordersControllerProvider,
          (_, _) {},
        );
        final orders = await scope.container.read(
          ordersControllerProvider.future,
        );
        ordersSub.close();
        expect(orders.map((order) => order.id), contains(state.orderId));
      },
    );

    test('an empty cart cannot check out', () async {
      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      final controller = scope.container.read(
        checkoutControllerProvider.notifier,
      );
      controller.submitAddress(_validAddress);

      await controller.confirmAndPlaceOrder();

      final state = checkout();
      expect(state.step, CheckoutStep.failure);
      expect(state.error, isA<ValidationException>());
      expect(state.failureStep, CheckoutStep.reviewing);
    });

    test(
      'a server failure lands on the failure step and retry recovers',
      () async {
        await signInAndFillCart();
        final controller = scope.container.read(
          checkoutControllerProvider.notifier,
        );
        controller.submitAddress(_validAddress);

        scope.host.server.conditions.forceStatusNext(1, 500);
        await controller.confirmAndPlaceOrder();

        var state = checkout();
        expect(state.step, CheckoutStep.failure);
        expect(state.error, isA<ServerException>());
        expect(state.failureStep, CheckoutStep.reviewing);

        // The cart survived the failure so a retry can succeed.
        expect(scope.container.read(cartControllerProvider).isEmpty, isFalse);

        await controller.retry();
        state = checkout();
        expect(state.step, CheckoutStep.success);
        expect(state.orderId, isNotNull);
        expect(scope.container.read(cartControllerProvider).isEmpty, isTrue);
      },
    );
  });
}
