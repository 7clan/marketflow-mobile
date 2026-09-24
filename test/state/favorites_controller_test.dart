import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/domain/entities/auth_session.dart';
import 'package:marketflow/domain/entities/user.dart';
import 'package:marketflow/presentation/providers/auth_controller.dart';
import 'package:marketflow/presentation/providers/favorites_controller.dart';

import '../helpers/app_container.dart';

void main() {
  group('FavoritesController — server sync', () {
    test(
      'signing in syncs the demo account favorites from the server',
      () async {
        final scope = await createTestApp();
        // Initialize favorites BEFORE login so its auth listener is active.
        scope.container.read(favoritesControllerProvider.notifier);

        await scope.container
            .read(authControllerProvider.notifier)
            .login(email: 'demo@marketflow.dev', password: 'Password123');
        await scope.settle();

        final favorites = scope.container.read(favoritesControllerProvider);
        expect(favorites.ids, {'p05', 'p12', 'p27'});
        expect(favorites.error, isNull);
        expect(await scope.favoritesCache.readIds(), {
          'p05',
          'p12',
          'p27',
        }, reason: 'the synced ids are written through to the cache');
      },
    );

    test('signing out clears the favorite ids', () async {
      final scope = await createTestApp();
      scope.container.read(favoritesControllerProvider.notifier);

      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      await scope.settle();
      await scope.container.read(authControllerProvider.notifier).logout();
      await scope.settle();

      expect(scope.container.read(favoritesControllerProvider).ids, isEmpty);
    });
  });

  group('FavoritesController — optimistic toggles', () {
    test(
      'adding a favorite updates the state immediately (optimistic)',
      () async {
        final scope = await createTestApp();
        await scope.container
            .read(authControllerProvider.notifier)
            .login(email: 'demo@marketflow.dev', password: 'Password123');
        final controller = scope.container.read(
          favoritesControllerProvider.notifier,
        );

        final pending = controller.addFavorite('p01');
        // The state flips before the server answers.
        expect(
          scope.container.read(favoritesControllerProvider).ids,
          contains('p01'),
        );

        await pending;
        expect(
          scope.container.read(favoritesControllerProvider).ids,
          contains('p01'),
        );
        // The server now lists it too.
        await controller.syncFromServer();
        expect(
          scope.container.read(favoritesControllerProvider).ids,
          contains('p01'),
        );
      },
    );

    test(
      'removing a seeded favorite removes it locally and server-side',
      () async {
        final scope = await createTestApp();
        await scope.container
            .read(authControllerProvider.notifier)
            .login(email: 'demo@marketflow.dev', password: 'Password123');
        await scope.settle();
        final controller = scope.container.read(
          favoritesControllerProvider.notifier,
        );
        // Let the controller's own initial sync settle before toggling.
        await scope.settle();

        final pending = controller.removeFavorite('p05');
        expect(
          scope.container.read(favoritesControllerProvider).ids,
          isNot(contains('p05')),
        );

        await pending;
        await controller.syncFromServer();
        expect(
          scope.container.read(favoritesControllerProvider).ids,
          isNot(contains('p05')),
        );
      },
    );

    test(
      'a failed add rolls back to the previous set and surfaces the error',
      () async {
        final scope = await createTestApp();
        await scope.container
            .read(authControllerProvider.notifier)
            .login(email: 'demo@marketflow.dev', password: 'Password123');
        await scope.settle();
        final controller = scope.container.read(
          favoritesControllerProvider.notifier,
        );
        await scope.settle();

        scope.host.server.conditions.forceStatusNext(1, 500);
        await controller.addFavorite('p01');

        final favorites = scope.container.read(favoritesControllerProvider);
        expect(
          favorites.ids,
          isNot(contains('p01')),
          reason: 'the optimistic add was rolled back',
        );
        expect(favorites.error, isA<ServerException>());
        expect((favorites.error as ServerException).statusCode, 500);
      },
    );

    test('a failed remove rolls back to the previous set', () async {
      final scope = await createTestApp();
      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      await scope.settle();
      final controller = scope.container.read(
        favoritesControllerProvider.notifier,
      );
      await scope.settle();

      scope.host.server.conditions.forceStatusNext(1, 500);
      await controller.removeFavorite('p12');

      final favorites = scope.container.read(favoritesControllerProvider);
      expect(favorites.ids, contains('p12'));
      expect(favorites.error, isA<ServerException>());
    });

    test('syncing twice is idempotent', () async {
      final scope = await createTestApp();
      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      final controller = scope.container.read(
        favoritesControllerProvider.notifier,
      );
      await scope.settle();

      await controller.syncFromServer();
      await controller.syncFromServer();

      expect(scope.container.read(favoritesControllerProvider).ids, {
        'p05',
        'p12',
        'p27',
      });
    });
  });

  group('FavoritesController — sync failures', () {
    test('a failed sync surfaces the error and keeps previous ids', () async {
      final scope = await createTestApp();
      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      await scope.settle();
      final controller = scope.container.read(
        favoritesControllerProvider.notifier,
      );
      await scope.settle();
      final before = scope.container.read(favoritesControllerProvider).ids;

      scope.host.server.conditions.forceStatusNext(1, 503);
      await controller.syncFromServer();

      final favorites = scope.container.read(favoritesControllerProvider);
      expect(favorites.error, isA<ServerException>());
      expect(favorites.isLoading, isFalse);
      expect(favorites.ids, before);
    });
  });

  group('FavoritesController — cache hydration', () {
    test(
      'an authenticated cold start hydrates from cache and re-syncs',
      () async {
        // Simulate a previous session: cache holds ids, storage holds a
        // still-valid token.
        final session = InMemorySessionLocalDataSource();
        await session.save(
          const AuthSession(
            token: 'tok-demo-1',
            user: User(
              id: 'u1',
              name: 'Dana Mercado',
              email: 'demo@marketflow.dev',
              memberSince: null,
            ),
          ),
        );
        final scope = await createTestApp(sessionLocal: session);
        await scope.favoritesCache.writeIds({'p33', 'p44'});

        scope.container.read(favoritesControllerProvider.notifier);
        await scope.settle();

        // The cached ids render instantly; the server sync then replaces them
        // with the authoritative list.
        expect(scope.container.read(favoritesControllerProvider).ids, {
          'p05',
          'p12',
          'p27',
        });
      },
    );

    test('a signed-out cold start does not surface cached ids', () async {
      final scope = await createTestApp();
      await scope.favoritesCache.writeIds({'p33', 'p44'});

      scope.container.read(favoritesControllerProvider.notifier);
      await scope.settle();

      // Privacy: signing out (or starting signed out) must clear cached ids.
      expect(scope.container.read(favoritesControllerProvider).ids, isEmpty);
    });
  });
}
