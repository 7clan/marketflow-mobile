import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/presentation/providers/cart_controller.dart';
import 'package:marketflow/presentation/screens/cart/cart_screen.dart';

import '../helpers/app_container.dart' show stubProduct;
import '../helpers/fake_repositories.dart';

void main() {
  late ProviderContainer container;

  Future<void> pumpCart(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CartScreen()),
      ),
    );
    // Let the cart restore + network image error placeholders settle.
    await tester.pump(const Duration(milliseconds: 120));
  }

  setUp(() async {
    container = await createFakeRepositoryContainer();
  });

  group('CartScreen — empty state', () {
    testWidgets('an empty cart shows the empty view, not the checkout button', (
      tester,
    ) async {
      await pumpCart(tester);

      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(
        find.text('Checkout'),
        findsNothing,
        reason: 'an empty cart must not offer checkout',
      );
      expect(find.text('Browse products'), findsOneWidget);
    });
  });

  group('CartScreen — line items', () {
    testWidgets('renders title, unit price, quantity and totals', (
      tester,
    ) async {
      container
          .read(cartControllerProvider.notifier)
          .addToCart(stubProduct('p01', price: 10.0), quantity: 2);
      container
          .read(cartControllerProvider.notifier)
          .addToCart(stubProduct('p02', price: 42.0), quantity: 1);
      await pumpCart(tester);

      expect(find.text('Product p01'), findsOneWidget);
      expect(find.text('Product p02'), findsOneWidget);
      expect(
        find.text(r'$10.00 each'),
        findsOneWidget,
        reason: 'the unit price is shown for the line',
      );
      expect(find.text(r'$42.00 each'), findsOneWidget);
      expect(
        find.text(r'$20.00'),
        findsOneWidget,
        reason: 'line total for p01 (2 x \$10)',
      );

      // Totals footer.
      expect(find.text('Subtotal'), findsOneWidget);
      expect(find.text(r'$62.00'), findsOneWidget);
      expect(find.text('Shipping'), findsOneWidget);
      expect(find.text(r'$8.99'), findsOneWidget);
      expect(find.text('Tax (8.5%)'), findsOneWidget);
      expect(find.text(r'$5.27'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(
        find.text(r'$76.26'),
        findsOneWidget,
        reason: '62.00 + 8.99 shipping + 5.27 tax',
      );
    });

    testWidgets('plus tap increments, minus at 1 stays disabled', (
      tester,
    ) async {
      container
          .read(cartControllerProvider.notifier)
          .addToCart(stubProduct('p01', price: 10.0), quantity: 1);
      await pumpCart(tester);

      final minusButton = find.ancestor(
        of: find.byIcon(Icons.remove_rounded),
        matching: find.byType(IconButton),
      );

      // Minus is disabled at the minimum quantity of 1.
      expect(
        (tester.widget(minusButton) as IconButton).onPressed,
        isNull,
        reason: 'quantity must never drop below 1',
      );
      expect(find.text('1'), findsOneWidget);

      // Plus increments to 2.
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(container.read(cartControllerProvider).items.first.quantity, 2);
      expect(find.text('2'), findsOneWidget);

      // Now minus is enabled and decrements back to 1.
      expect((tester.widget(minusButton) as IconButton).onPressed, isNotNull);
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(container.read(cartControllerProvider).items.first.quantity, 1);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('removing the last item empties the cart', (tester) async {
      container
          .read(cartControllerProvider.notifier)
          .addToCart(stubProduct('p01', price: 10.0), quantity: 3);
      await pumpCart(tester);

      await tester.tap(find.byTooltip('Remove from cart'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(container.read(cartControllerProvider).isEmpty, isTrue);
      expect(find.text('Your cart is empty'), findsOneWidget);
      expect(find.text('Checkout'), findsNothing);
    });
  });
}
