import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/presentation/screens/feed/product_feed_screen.dart';
import 'package:marketflow/presentation/widgets/skeleton.dart';

import '../helpers/app_container.dart' show stubProduct;
import '../helpers/fake_repositories.dart';

void main() {
  late FakeProductRepository productRepository;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = await createFakeRepositoryContainer(
      productRepository: productRepository,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProductFeedScreen()),
      ),
    );
    return container;
  }

  setUp(() {
    productRepository = FakeProductRepository(
      products: [stubProduct('p01'), stubProduct('p02')],
    );
  });

  group('ProductFeedScreen — loading state', () {
    testWidgets('the first page renders skeleton cards, not a spinner', (
      tester,
    ) async {
      // Hold page 1 in flight so the screen stays in its loading state.
      productRepository.getProductsGate = Completer<void>();
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 120));

      // The grid is lazy: only the visible cells build (2 in the test
      // viewport), but every one of them is a skeleton card.
      expect(
        find.byType(SkeletonProductCard),
        findsAtLeastNWidgets(2),
        reason: 'the feed grid placeholders match the card layout',
      );
      expect(find.byType(SkeletonPulse), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'loading the feed is a skeleton, not a blocking spinner',
      );

      // The skeleton area announces itself once, politely.
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('completing the load swaps skeletons for real products', (
      tester,
    ) async {
      final gate = Completer<void>();
      productRepository.getProductsGate = gate;
      await pump(tester);
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byType(SkeletonProductCard), findsAtLeastNWidgets(2));

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SkeletonProductCard), findsNothing);
      expect(find.text('Product p01'), findsOneWidget);
      expect(find.text('Product p02'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    });
  });
}
