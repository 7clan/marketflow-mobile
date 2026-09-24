import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/repositories/product_repository_impl.dart';
import 'package:marketflow/domain/entities/product_filter.dart';

import '../helpers/mock_api.dart';

void main() {
  late MockApiHarness api;
  late ProductRepositoryImpl repository;

  setUp(() async {
    api = await startMockApi();
    addTearDown(api.dispose);
    repository = ProductRepositoryImpl(apiClient: api.apiClient);
  });

  group('pagination', () {
    test('page 1 returns the first chunk with paging metadata', () async {
      final page = await repository.getProducts(page: 1, pageSize: 20);

      expect(page.page, 1);
      expect(page.items, hasLength(20));
      expect(page.totalItems, 66, reason: 'the seeded catalog has 66 products');
      expect(page.totalPages, 4);
      expect(page.hasMore, isTrue);
    });

    test('page 2 returns a different slice of the catalog', () async {
      final first = await repository.getProducts(page: 1, pageSize: 20);
      final second = await repository.getProducts(page: 2, pageSize: 20);

      expect(second.page, 2);
      expect(second.items, hasLength(20));
      final firstIds = first.items.map((product) => product.id).toSet();
      final secondIds = second.items.map((product) => product.id).toSet();
      expect(
        firstIds.intersection(secondIds),
        isEmpty,
        reason: 'pages must not repeat products',
      );
      expect(secondIds.difference(firstIds), hasLength(20));
    });

    test('the final page returns the remainder and stops paging', () async {
      final page = await repository.getProducts(page: 4, pageSize: 20);

      expect(page.items, hasLength(6));
      expect(page.hasMore, isFalse);
      expect(page.totalPages, 4);
    });

    test('a page beyond the end is empty', () async {
      final page = await repository.getProducts(page: 5, pageSize: 20);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('filters', () {
    test('a category filter narrows results to that category', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 100,
        filter: const ProductFilter(categoryId: 'c1'),
      );

      expect(page.totalItems, 11);
      expect(
        page.items.map((product) => product.categoryId),
        everyElement('c1'),
      );
    });

    test(
      'a price range keeps every returned price inside the bounds',
      () async {
        final page = await repository.getProducts(
          page: 1,
          pageSize: 100,
          filter: const ProductFilter(minPrice: 50, maxPrice: 100),
        );

        expect(page.items, isNotEmpty);
        expect(page.items, isNotEmpty);
        expect(
          page.items.map((product) => product.price),
          everyElement(allOf(greaterThanOrEqualTo(50), lessThanOrEqualTo(100))),
        );
        // The unfiltered count must be strictly larger.
        final all = await repository.getProducts(page: 1, pageSize: 100);
        expect(page.totalItems, lessThan(all.totalItems));
      },
    );

    test('inStockOnly hides zero-stock and unavailable products', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 100,
        filter: const ProductFilter(inStockOnly: true),
      );

      expect(page.items, isNotEmpty);
      expect(
        page.items.map((product) => product.isOutOfStock),
        everyElement(isFalse),
      );
      expect(page.totalItems, lessThan(66));
    });

    test(
      'an inverted price range is rejected as BadRequestException',
      () async {
        await expectLater(
          repository.getProducts(
            page: 1,
            pageSize: 20,
            filter: const ProductFilter(minPrice: 100, maxPrice: 10),
          ),
          throwsA(isA<BadRequestException>()),
        );
      },
    );
  });

  group('sorts', () {
    test('priceAsc returns the catalog in ascending price order', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 100,
        sort: ProductSort.priceAsc,
      );

      final prices = page.items.map((product) => product.price).toList();
      final sorted = [...prices]..sort();
      expect(prices, sorted, reason: 'prices must be non-decreasing');
      expect(page.items.first.price, prices.first);
    });

    test('priceDesc returns the catalog in descending price order', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 100,
        sort: ProductSort.priceDesc,
      );

      final prices = page.items.map((product) => product.price).toList();
      final sorted = ([...prices]..sort()).reversed.toList();
      expect(prices, sorted);
    });

    test('rating sorts by descending rating', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 100,
        sort: ProductSort.rating,
      );

      final ratings = page.items.map((product) => product.rating).toList();
      for (var i = 1; i < ratings.length; i++) {
        expect(ratings[i - 1], greaterThanOrEqualTo(ratings[i]));
      }
    });
  });

  group('search', () {
    test("query 'wireless' matches only the two wireless products", () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 20,
        query: 'wireless',
      );

      expect(page.totalItems, 2);
      expect(
        page.items.map((product) => product.title),
        everyElement(contains('Wireless')),
      );
    });

    test('an unknown term returns an empty page', () async {
      final page = await repository.getProducts(
        page: 1,
        pageSize: 20,
        query: 'zzz-no-such-product',
      );
      expect(page.items, isEmpty);
      expect(page.totalItems, 0);
      expect(page.hasMore, isFalse);
    });
  });

  group('detail', () {
    test('fetches a single product by id', () async {
      final product = await repository.getProduct('p01');

      expect(product.id, 'p01');
      expect(product.title, 'Aurora Wireless Noise-Cancelling Earbuds');
      expect(product.categoryId, 'c1');
      expect(product.imageUrls, isNotEmpty);
    });

    test('an unknown product id surfaces NotFoundException', () async {
      await expectLater(
        repository.getProduct('p-nope'),
        throwsA(isA<NotFoundException>()),
      );
    });

    test('a malformed body surfaces MalformedResponseException', () async {
      api.server.conditions.malformedNext = true;
      await expectLater(
        repository.getProduct('p01'),
        throwsA(isA<MalformedResponseException>()),
      );
    });
  });

  group('categories', () {
    test('returns the six seeded categories with counts', () async {
      final categories = await repository.getCategories();

      expect(categories, hasLength(6));
      final electronics = categories.firstWhere((c) => c.id == 'c1');
      expect(electronics.name, 'Electronics');
      expect(electronics.productCount, 11);
    });
  });
}
