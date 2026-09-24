import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/domain/entities/product_filter.dart';
import 'package:marketflow/presentation/providers/filter_controller.dart';
import 'package:marketflow/presentation/providers/product_feed_controller.dart';

import '../helpers/app_container.dart';

void main() {
  late TestAppScope scope;

  setUp(() async {
    scope = await createTestApp();
  });

  ProductFeedState feed() =>
      scope.container.read(productFeedProvider).requireValue;

  test('page 1 loads the first 20 products of 66', () async {
    final state = await scope.container.read(productFeedProvider.future);

    expect(state.page, 1);
    expect(state.items, hasLength(20));
    expect(state.totalItems, 66);
    expect(state.hasMore, isTrue);
    expect(state.isLoadingMore, isFalse);
    expect(state.error, isNull);
  });

  test('loadNextPage appends page 2 without repeating products', () async {
    await scope.container.read(productFeedProvider.future);
    final controller = scope.container.read(productFeedProvider.notifier);

    await controller.loadNextPage();

    final state = feed();
    expect(state.page, 2);
    expect(state.items, hasLength(40));
    final ids = state.items.map((product) => product.id).toSet();
    expect(ids, hasLength(40), reason: 'no duplicates across pages');
    expect(state.hasMore, isTrue);
  });

  test('loadNextPage stops once the last page lands', () async {
    // Narrow the feed to one category (11 products, 2 pages at size 20).
    scope.container.read(filterControllerProvider.notifier).setCategory('c1');
    await scope.container.read(productFeedProvider.future);
    final controller = scope.container.read(productFeedProvider.notifier);

    await controller.loadNextPage();
    final atEnd = feed();
    expect(atEnd.items, hasLength(11));
    expect(atEnd.hasMore, isFalse);

    // A further call is a no-op: the page counter must not advance.
    await controller.loadNextPage();
    final unchanged = feed();
    expect(unchanged.page, atEnd.page);
    expect(unchanged.items, hasLength(11));
  });

  test('refresh resets back to page 1', () async {
    await scope.container.read(productFeedProvider.future);
    final controller = scope.container.read(productFeedProvider.notifier);
    await controller.loadNextPage();
    expect(feed().items, hasLength(40));

    await controller.refresh();

    final state = feed();
    expect(state.page, 1);
    expect(state.items, hasLength(20));
    expect(state.totalItems, 66);
  });

  test('changing a filter re-runs page 1 with the narrowed result', () async {
    await scope.container.read(productFeedProvider.future);

    scope.container
        .read(filterControllerProvider.notifier)
        .setInStockOnly(true);
    await scope.container.read(productFeedProvider.future);

    final state = feed();
    expect(state.page, 1);
    expect(
      state.items.map((product) => product.isOutOfStock),
      everyElement(isFalse),
    );
    expect(state.totalItems, lessThan(66));
  });

  test('changing the sort re-runs page 1 in the new order', () async {
    await scope.container.read(productFeedProvider.future);
    final before = feed().items;

    scope.container
        .read(filterControllerProvider.notifier)
        .setSort(ProductSort.priceAsc);
    await scope.container.read(productFeedProvider.future);

    final after = feed().items;
    final prices = after.map((product) => product.price).toList();
    final sorted = [...prices]..sort();
    expect(prices, sorted);
    expect(
      after.first.id,
      isNot(before.first.id),
      reason: 'a different order must reshuffle the first page',
    );
  });

  test('a stale load-more response (filter changed mid-flight) is discarded '
      'instead of corrupting the new results', () async {
    await scope.container.read(productFeedProvider.future);
    final controller = scope.container.read(productFeedProvider.notifier);

    // Fire a slow page-2 append for the unfiltered feed...
    scope.host.server.conditions.latencyMinMs = 400;
    scope.host.server.conditions.latencyMaxMs = 400;
    final staleAppend = controller.loadNextPage();

    // ...then switch to a narrow filter that rebuilds the feed fast.
    scope.host.server.conditions.latencyMinMs = 0;
    scope.host.server.conditions.latencyMaxMs = 0;
    scope.container.read(filterControllerProvider.notifier).setCategory('c1');
    await scope.container.read(productFeedProvider.future);
    final fresh = feed();
    expect(fresh.items, hasLength(11));
    expect(
      fresh.items.map((product) => product.categoryId),
      everyElement('c1'),
    );

    // The slow append lands after the rebuild — it must drop itself.
    await staleAppend;

    final state = feed();
    expect(
      state.items,
      hasLength(11),
      reason: 'the stale page-2 append must not append to the new feed',
    );
    expect(
      state.items.map((product) => product.categoryId),
      everyElement('c1'),
    );
    expect(state.isLoadingMore, isFalse);
  });

  test('a failed load-more keeps the list and surfaces the error', () async {
    await scope.container.read(productFeedProvider.future);
    final controller = scope.container.read(productFeedProvider.notifier);

    scope.host.server.conditions.forceStatusNext(1, 500);
    await controller.loadNextPage();

    final state = feed();
    expect(state.items, hasLength(20), reason: 'the loaded list stays');
    expect(state.isLoadingMore, isFalse);
    expect(state.error, isNotNull);
  });

  test(
    'a transient initial failure self-heals via riverpod auto-retry',
    () async {
      // Riverpod retries providers that throw Exceptions with backoff — a
      // single blip on the first load recovers without user action.
      scope.host.server.conditions.forceStatusNext(1, 500);

      // A live subscription stands in for the UI: riverpod pauses elements
      // nobody listens to, so auto-retry only drives rebuilds while watched.
      final subscription = scope.container.listen(
        productFeedProvider,
        (_, _) {},
      );

      final state = await scope.container.read(productFeedProvider.future);
      subscription.close();

      expect(
        scope.container.read(productFeedProvider),
        isA<AsyncData<ProductFeedState>>(),
      );
      expect(state.items, hasLength(20));
      expect(state.totalItems, 66);
    },
  );

  test(
    'a failed initial load surfaces AsyncError when retries are disabled',
    () async {
      // A dedicated scope with automatic retry disabled: the failure state
      // itself is what the UI must be able to render.
      final noRetry = await createTestApp(
        retry: (int retryCount, Object error) => null,
      );
      noRetry.host.server.conditions.forceStatusNext(1, 500);

      await expectLater(
        noRetry.container.read(productFeedProvider.future),
        throwsA(isA<Exception>()),
      );
      expect(noRetry.container.read(productFeedProvider), isA<AsyncError>());
    },
  );
}
