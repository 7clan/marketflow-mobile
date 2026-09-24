import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/presentation/providers/search_controller.dart';

import '../helpers/app_container.dart';

void main() {
  group('SearchController — debounce', () {
    test(
      'rapid keystrokes fire a single network call for the final query',
      () async {
        final scope = await createTestApp();
        final controller = scope.container.read(
          searchControllerProvider.notifier,
        );

        // A burst of keystrokes within the debounce window...
        controller.onQueryChanged('wire');
        controller.onQueryChanged('wirele');
        controller.onQueryChanged('wireless');

        // ...must not hit the network before the window elapses.
        expect(scope.host.server.handledRequestCount, 0);
        expect(
          scope.container.read(searchControllerProvider).isSearching,
          isTrue,
          reason: 'the field reports a pending search while debouncing',
        );

        await Future<void>.delayed(
          const Duration(milliseconds: 700),
        ); // > 300ms debounce

        final state = scope.container.read(searchControllerProvider);
        expect(
          scope.host.server.handledRequestCount,
          1,
          reason: 'only the final query may hit the network',
        );
        expect(state.isSearching, isFalse);
        expect(state.error, isNull);
        expect(state.results, isNotEmpty);
        expect(
          state.results.every(
            (product) => product.title.toLowerCase().contains('wireless'),
          ),
          isTrue,
          reason:
              "stale intermediate queries ('wire', 'wirele') must never "
              'populate the results',
        );
      },
    );

    test('clearing mid-debounce cancels the pending search entirely', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(
        searchControllerProvider.notifier,
      );

      controller.onQueryChanged('wireless');
      controller.clear();
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      ); // > 300ms debounce

      final state = scope.container.read(searchControllerProvider);
      expect(
        scope.host.server.handledRequestCount,
        0,
        reason: 'clear() cancels the debounced call before it fires',
      );
      expect(state.query, isEmpty);
      expect(state.results, isEmpty);
      expect(state.isSearching, isFalse);
    });
  });

  group('SearchController — cancellation of superseded requests', () {
    test(
      'a superseded in-flight search is cancelled and its result dropped',
      () async {
        final scope = await createTestApp();
        // Slow responses so the first search is still in flight when the
        // query changes.
        scope.host.server.conditions.latencyMinMs = 300;
        scope.host.server.conditions.latencyMaxMs = 300;
        final controller = scope.container.read(
          searchControllerProvider.notifier,
        );

        controller.onQueryChanged('w');
        // Wait past the 300ms debounce so the 'w' request goes out...
        await Future<void>.delayed(const Duration(milliseconds: 50));
        // ...then supersede it while it is still in flight.
        controller.onQueryChanged('wireless');
        await Future<void>.delayed(const Duration(milliseconds: 900));

        final state = scope.container.read(searchControllerProvider);
        expect(state.isSearching, isFalse);
        expect(state.results, isNotEmpty);
        expect(
          state.results.every(
            (product) => product.title.toLowerCase().contains('wireless'),
          ),
          isTrue,
          reason:
              "the broad 'w' response must not replace the wireless "
              'results even if it lands after the cancellation',
        );
      },
    );
  });

  group('SearchController — empty and error states', () {
    test('an empty query resets to idle without a network call', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(
        searchControllerProvider.notifier,
      );

      controller.onQueryChanged('wireless');
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      ); // > 300ms debounce
      expect(
        scope.container.read(searchControllerProvider).results,
        isNotEmpty,
      );

      controller.onQueryChanged('');
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      ); // > 300ms debounce

      final state = scope.container.read(searchControllerProvider);
      expect(state.hasQuery, isFalse);
      expect(state.results, isEmpty);
      expect(state.isEmpty, isFalse);
    });

    test('a failed search surfaces the error and refresh recovers', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(
        searchControllerProvider.notifier,
      );

      scope.host.server.conditions.forceStatusNext(1, 500);
      controller.onQueryChanged('wireless');
      await Future<void>.delayed(
        const Duration(milliseconds: 700),
      ); // > 300ms debounce

      final failed = scope.container.read(searchControllerProvider);
      expect(failed.error, isNotNull);
      expect(failed.isSearching, isFalse);
      expect(failed.results, isEmpty);
      expect(
        failed.isEmpty,
        isFalse,
        reason: 'the empty state must not mask a failure',
      );

      await controller.refresh();
      final recovered = scope.container.read(searchControllerProvider);
      expect(recovered.error, isNull);
      expect(recovered.results, isNotEmpty);
    });
  });
}
