import '../../domain/entities/auth_session.dart';

/// Persistence seam for the authenticated session.
///
/// Implementations persist token + user; tests inject
/// [InMemorySessionLocalDataSource] (or their own) through a Riverpod
/// override — the repositories never know the difference.
abstract interface class SessionLocalDataSource {
  /// Persists token + user.
  Future<void> save(AuthSession session);

  /// Restores the persisted session, or `null` when signed out.
  Future<AuthSession?> read();

  /// Removes the persisted session.
  Future<void> clear();
}

/// Fully in-memory variant for tests and previews.
class InMemorySessionLocalDataSource implements SessionLocalDataSource {
  AuthSession? _session;

  @override
  Future<void> save(AuthSession session) async => _session = session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> clear() async => _session = null;
}
