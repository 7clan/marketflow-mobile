import '../entities/auth_session.dart';
import '../entities/user.dart';

/// Authentication and session persistence contract.
abstract interface class AuthRepository {
  /// Signs in with [email] and [password]; returns the new session.
  ///
  /// Throws [UnauthorizedException] for wrong credentials.
  Future<AuthSession> login({required String email, required String password});

  /// Creates an account and signs the user in; returns the new session.
  ///
  /// Throws [ValidationException] for invalid/duplicate fields.
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  });

  /// Rehydrates a persisted session, verifying it server-side.
  ///
  /// Returns `null` when no session is stored or the token is stale.
  Future<AuthSession?> restoreSession();

  /// Signs the user out, clearing local state even if the network fails.
  Future<void> logout();

  /// The signed-in user right now, or `null`.
  Future<User?> currentUser();

  /// Emits the current user on every session change (login, register,
  /// restore, logout, expiry). A cold stream that replays the current value.
  Stream<User?> get userChanges;

  /// Clears the local session without a network round-trip — used when the
  /// API already reported an expired token.
  Future<void> discardLocalSession();
}
