import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/user.dart';
import 'infrastructure_providers.dart';

/// The authentication states the UI can render.
///
/// The async wrapper ([AsyncValue]) covers the loading phase during startup
/// restore and during login/register submissions.
sealed class AuthState {
  const AuthState();
}

/// Signed in as [user].
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final User user;
}

/// Signed out.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// App-wide authentication state.
///
/// * `build()` restores the persisted session (verifying it server-side);
/// * login/register surface their error to the **caller** (the form shows
///   inline errors) while the shared state only tracks the session itself;
/// * any 401 outside the auth endpoints funnels into [handleSessionExpired]
///   and signs the user out.
final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // Auth is app-global: it must survive losing all listeners temporarily.
    ref.keepAlive();

    final repository = ref.watch(authRepositoryProvider);

    // Session transitions (login, register, restore, logout, expiry) are
    // mirrored here from the repository's user stream.
    final subscription = repository.userChanges.listen((user) {
      state = AsyncData(
        user == null ? const AuthUnauthenticated() : AuthAuthenticated(user),
      );
    });
    ref.onDispose(subscription.cancel);

    final session = await repository.restoreSession();
    return session == null
        ? const AuthUnauthenticated()
        : AuthAuthenticated(session.user);
  }

  /// Signs in; throws [AppException]s to the caller for inline form errors.
  Future<void> login({required String email, required String password}) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repository.login(email: email, password: password);
      // State transitions arrive via the repository's user stream.
    } catch (error) {
      state = const AsyncData(AuthUnauthenticated());
      rethrow;
    }
  }

  /// Creates an account and signs in; throws to the caller on failure.
  Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repository.register(name: name, email: email, password: password);
    } catch (error) {
      state = const AsyncData(AuthUnauthenticated());
      rethrow;
    }
  }

  /// Signs out — local state clears even when the network call fails.
  Future<void> logout() async {
    final repository = ref.read(authRepositoryProvider);
    state = const AsyncLoading();
    try {
      await repository.logout();
    } on AppException {
      // The repository already cleared the local session.
    } finally {
      state = const AsyncData(AuthUnauthenticated());
    }
  }

  /// Called by the auth interceptor when a previously valid token got a 401.
  void handleSessionExpired() {
    final repository = ref.read(authRepositoryProvider);
    unawaited(repository.discardLocalSession());
  }
}

/// Convenience extension: the signed-in user, or `null`.
extension AuthUserX on AsyncValue<AuthState> {
  /// The signed-in [User] when authenticated, otherwise `null`.
  User? get user {
    final value = this.value;
    return value is AuthAuthenticated ? value.user : null;
  }

  /// `true` while the underlying data is the signed-in state.
  bool get isAuthenticated => value is AuthAuthenticated;
}
