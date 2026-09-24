import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/domain/entities/auth_session.dart';
import 'package:marketflow/domain/entities/user.dart';
import 'package:marketflow/presentation/providers/auth_controller.dart';

import '../helpers/app_container.dart';

void main() {
  group('AuthController — login / logout / restore', () {
    test('build with no stored session resolves to unauthenticated', () async {
      final scope = await createTestApp();

      final state = await scope.container.read(authControllerProvider.future);

      expect(state, isA<AuthUnauthenticated>());
    });

    test('login with demo credentials transitions to authenticated', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(authControllerProvider.notifier);

      await controller.login(
        email: 'demo@marketflow.dev',
        password: 'Password123',
      );
      // State transitions arrive via the repository's user stream — flush.
      await Future<void>.delayed(Duration.zero);

      final state = scope.container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.name, 'Dana Mercado');
      expect(scope.sessionLocal.read(), completes);
      final stored = await scope.sessionLocal.read();
      expect(stored!.token, 'tok-demo-1');
    });

    test('a failed login keeps the app unauthenticated and rethrows', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(authControllerProvider.notifier);

      await expectLater(
        controller.login(email: 'demo@marketflow.dev', password: 'wrong'),
        throwsA(isA<UnauthorizedException>()),
      );

      final state = scope.container.read(authControllerProvider).requireValue;
      expect(state, isA<AuthUnauthenticated>());
      expect(await scope.sessionLocal.read(), isNull);
    });

    test('logout returns to unauthenticated and clears the session', () async {
      final scope = await createTestApp();
      final controller = scope.container.read(authControllerProvider.notifier);

      await controller.login(
        email: 'demo@marketflow.dev',
        password: 'Password123',
      );
      await controller.logout();

      expect(
        scope.container.read(authControllerProvider).requireValue,
        isA<AuthUnauthenticated>(),
      );
      expect(await scope.sessionLocal.read(), isNull);
    });
  });

  group('AuthController — session restore', () {
    test('a persisted session is restored on container startup', () async {
      // Seed storage as if a previous run signed in.
      final sessionLocal = InMemorySessionLocalDataSource();
      await sessionLocal.save(
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

      final scope = await createTestApp(sessionLocal: sessionLocal);
      final state = await scope.container.read(authControllerProvider.future);

      expect(state, isA<AuthAuthenticated>());
      expect((state as AuthAuthenticated).user.email, 'demo@marketflow.dev');
    });

    test('an expired (rejected) token signs out instead of erroring', () async {
      final sessionLocal = InMemorySessionLocalDataSource();
      await sessionLocal.save(
        const AuthSession(
          token: 'tok-long-expired',
          user: User(
            id: 'u1',
            name: 'Dana Mercado',
            email: 'demo@marketflow.dev',
            memberSince: null,
          ),
        ),
      );

      final scope = await createTestApp(sessionLocal: sessionLocal);
      final state = await scope.container.read(authControllerProvider.future);

      expect(
        state,
        isA<AuthUnauthenticated>(),
        reason: 'the 401 from /auth/me must clean the session',
      );
      expect(await sessionLocal.read(), isNull);
    });

    test(
      'a session from a fresh container wins over a stale container',
      () async {
        // Two containers sharing one storage: the second one sees the login
        // made through the first one on restore.
        final sessionLocal = InMemorySessionLocalDataSource();
        final first = await createTestApp(sessionLocal: sessionLocal);
        await first.container
            .read(authControllerProvider.notifier)
            .login(email: 'demo@marketflow.dev', password: 'Password123');

        final second = await createTestApp(sessionLocal: sessionLocal);
        final restored = await second.container.read(
          authControllerProvider.future,
        );

        expect(restored, isA<AuthAuthenticated>());
      },
    );
  });

  group('AuthUserX helpers', () {
    test('user and isAuthenticated read off AsyncValue', () async {
      final scope = await createTestApp();
      final value = scope.container.read(authControllerProvider);

      expect(value.isAuthenticated, false);
      expect(value.user, isNull);

      await scope.container
          .read(authControllerProvider.notifier)
          .login(email: 'demo@marketflow.dev', password: 'Password123');
      await Future<void>.delayed(Duration.zero);
      final authenticated = scope.container.read(authControllerProvider);

      expect(authenticated.isAuthenticated, true);
      expect(authenticated.user?.email, 'demo@marketflow.dev');
    });
  });
}
