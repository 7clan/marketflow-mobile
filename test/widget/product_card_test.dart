import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/domain/entities/product.dart';
import 'package:marketflow/presentation/providers/favorites_controller.dart';
import 'package:marketflow/presentation/widgets/product_card.dart';

import '../helpers/fake_repositories.dart';

/// A realistic cell: compare-at price + rating + long title.
const _product = Product(
  id: 'p01',
  title: 'Aurora Wireless Noise-Cancelling Earbuds',
  description: 'Immersive sound with adaptive noise cancellation.',
  price: 129.99,
  compareAtPrice: 179.99,
  imageUrls: ['https://example.com/p01.jpg'],
  rating: 4.5,
  reviewCount: 42,
  stock: 12,
  categoryId: 'c1',
  sellerName: 'Test Seller',
  isAvailable: true,
);

void main() {
  late FakeFavoritesRepository favoritesRepository;
  late ProviderContainer container;

  Future<void> pumpCard(
    WidgetTester tester, {
    double width = 360,
    double height = 300,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: const ProductCard(product: _product),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Let the network image fail and settle on its error placeholder.
    await tester.pump(const Duration(milliseconds: 400));
  }

  setUp(() async {
    favoritesRepository = FakeFavoritesRepository();
    container = await createFakeRepositoryContainer(
      favoritesRepository: favoritesRepository,
    );
  });

  group('ProductCard — content', () {
    testWidgets('renders title, price and rating', (tester) async {
      await pumpCard(tester);

      expect(
        find.text('Aurora Wireless Noise-Cancelling Earbuds'),
        findsOneWidget,
      );
      expect(find.text(r'$129.99'), findsOneWidget);
      expect(
        find.text(r'$179.99'),
        findsOneWidget,
        reason: 'the compare-at price renders struck through',
      );
      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('(42)'), findsOneWidget);
      expect(find.text('-28%'), findsOneWidget, reason: 'discount badge');
    });

    testWidgets('exposes a single a11y label covering the card tap target', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(
        find.bySemanticsLabel(
          'Aurora Wireless Noise-Cancelling Earbuds, \$129.99',
        ),
        findsOneWidget,
      );
    });
  });

  group('ProductCard — favorite toggle', () {
    testWidgets('tapping the heart toggles the favorite state', (tester) async {
      await pumpCard(tester);

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(
        container.read(favoritesControllerProvider).isFavorite('p01'),
        isFalse,
      );

      await tester.tap(find.byIcon(Icons.favorite_border_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(
        find.byIcon(Icons.favorite_rounded),
        findsOneWidget,
        reason: 'the optimistic toggle flips the heart immediately',
      );
      expect(
        container.read(favoritesControllerProvider).isFavorite('p01'),
        isTrue,
      );
      expect(favoritesRepository.addCalls, 1);

      // Tapping again removes it.
      await tester.tap(find.byIcon(Icons.favorite_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(favoritesRepository.removeCalls, 1);
    });

    testWidgets('the favorite button meets the 48dp touch target', (
      tester,
    ) async {
      await pumpCard(tester);

      // The accessible tap target is the semantics geometry (the visual
      // IconButton renders 40dp; Material pads the interactive area to 48).
      final handle = tester.ensureSemantics();
      final semantics =
          tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!;
      SemanticsNode? favoriteNode;
      void walk(SemanticsNode node) {
        if (node.label.contains('to favorites')) favoriteNode = node;
        node.visitChildren((child) {
          walk(child);
          return true;
        });
      }

      walk(semantics);
      handle.dispose();

      expect(
        favoriteNode,
        isNotNull,
        reason: 'the heart button must carry a Semantics label',
      );
      final rect = favoriteNode!.rect;
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
    });
  });

  group('ProductCard — responsive layout', () {
    testWidgets('no overflow at logical width 360', (tester) async {
      await pumpCard(tester, width: 360);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the card must fit a 2-column grid cell at 360dp',
      );
    });

    testWidgets('no overflow at width 360 with 2.0x text scale', (
      tester,
    ) async {
      await pumpCard(tester, width: 360, textScaler: TextScaler.linear(2.0));

      expect(
        tester.takeException(),
        isNull,
        reason: 'large text must ellipsize/wrap, never overflow',
      );
    });
  });
}
