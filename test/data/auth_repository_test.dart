import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/data/datasources/session_local_data_source.dart';
import 'package:marketflow/data/repositories/auth_repository_impl.dart';
import 'package:marketflow/domain/entities/auth_session.dart';
import 'package:marketflow/domain/entities/user.dart';

import '../helpers/mock_api.dart';

void main() {
  late MockApiHarness api;
  late InMemorySessionLocalDataSource local;
  late AuthRepositoryImpl repository;

  setUp(() async {
    local = InMemorySessionLocalDataSource();
    // Token is read from the (in-memory) session storage on every request,
    // exactly like the app wiring.
    api = await startMockApi(
      tokenProvider: () async => (await local.read())?.token,
    );
    addTearDown(api.dispose);
    repository = AuthRepositoryImpl(apiClient: api.apiClient, local: local);
  });

  test(
    'login with valid demo credentials returns the session and persists it',
    () async {
      final session = await repository.login(
        email: 'demo@marketflow.dev',
        password: 'Password123',
      );

      expect(session.token, 'tok-demo-1');
      expect(session.user.email, 'demo@marketflow.dev');
      expect(session.user.name, 'Dana Mercado');
      expect(session.user.id, 'u1');
      expect(await local.read(), isNotNull);
    },
  );

  test(
    'login with the wrong password surfaces UnauthorizedException',
    () async {
      await expectLater(
        repository.login(email: 'demo@marketflow.dev', password: 'nope-nope'),
        throwsA(
          isA<UnauthorizedException>().having(
            (error) => error.message,
            'message',
            'Invalid email or password.',
          ),
        ),
      );
      expect(
        await local.read(),
        isNull,
        reason: 'a failed login must not persist a session',
      );
    },
  );

  test('login with an unknown email surfaces UnauthorizedException', () async {
    await expectLater(
      repository.login(email: 'ghost@marketflow.dev', password: 'Password123'),
      throwsA(isA<UnauthorizedException>()),
    );
  });

  test('register creates a new account and persists the session', () async {
    final session = await repository.register(
      name: 'Tina Tester',
      email: 'tina@example.com',
      password: 'Password123',
    );

    expect(session.user.name, 'Tina Tester');
    expect(session.user.email, 'tina@example.com');
    expect(session.token, isNotEmpty);
    expect(await local.read(), session);

    // The new credentials immediately work for login too.
    final relogin = await repository.login(
      email: 'tina@example.com',
      password: 'Password123',
    );
    expect(relogin.user.id, session.user.id);
  });

  test('registering an existing email surfaces ValidationException', () async {
    await expectLater(
      repository.register(
        name: 'Dana Again',
        email: 'demo@marketflow.dev',
        password: 'Password123',
      ),
      throwsA(
        isA<ValidationException>().having(
          (error) => error.fieldErrors['email'],
          'fieldErrors[email]',
          ['An account with this email already exists.'],
        ),
      ),
    );
  });

  test('restoreSession returns null when nothing is stored', () async {
    final restored = await repository.restoreSession();
    expect(restored, isNull);
  });

  test('restoreSession verifies the token against /auth/me', () async {
    await repository.login(
      email: 'demo@marketflow.dev',
      password: 'Password123',
    );

    final restored = await repository.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.token, 'tok-demo-1');
    expect(restored.user.email, 'demo@marketflow.dev');
  });

  test(
    'restoreSession drops a rejected token (401) and clears storage',
    () async {
      await repository.login(
        email: 'demo@marketflow.dev',
        password: 'Password123',
      );
      // Corrupt the stored token so /auth/me answers 401.
      final stored = await local.read();
      await local.save(AuthSession(token: 'tok-expired', user: stored!.user));

      final restored = await repository.restoreSession();

      expect(restored, isNull);
      expect(
        await local.read(),
        isNull,
        reason: 'a rejected token must be cleared',
      );
    },
  );

  test('logout clears the persisted session', () async {
    await repository.login(
      email: 'demo@marketflow.dev',
      password: 'Password123',
    );
    await repository.logout();

    expect(await local.read(), isNull);
    expect(await repository.currentUser(), isNull);
  });

  test('userChanges emits the signed-in user and null after logout', () async {
    final emitted = <User?>[];
    final subscription = repository.userChanges.listen(emitted.add);

    await repository.login(
      email: 'demo@marketflow.dev',
      password: 'Password123',
    );
    await repository.logout();
    // The repository starts by restoring (null user) during this test.
    await repository.restoreSession();

    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(emitted, everyElement(isA<User?>()));
    expect(emitted.where((user) => user != null).map((user) => user!.name), [
      'Dana Mercado',
    ]);
    expect(emitted.where((user) => user == null), isNotEmpty);
  });
}
