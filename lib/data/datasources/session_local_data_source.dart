import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/auth_session.dart';
import '../models/auth_session_model.dart';

/// Persistence seam for the authenticated session.
///
/// Production stores the session in [FlutterSecureStorage] (Keychain /
/// EncryptedSharedPreferences). Tests inject
/// [InMemorySessionLocalDataSource] through a Riverpod override — the
/// repositories never know the difference.
abstract interface class SessionLocalDataSource {
  /// Persists token + user.
  Future<void> save(AuthSession session);

  /// Restores the persisted session, or `null` when signed out.
  Future<AuthSession?> read();

  /// Removes the persisted session.
  Future<void> clear();
}

class SecureSessionLocalDataSource implements SessionLocalDataSource {
  SecureSessionLocalDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _storageKey = 'marketflow.session';

  final FlutterSecureStorage _storage;

  /// Secure-storage reads are slow; cache the decoded session in memory.
  AuthSession? _cached;

  @override
  Future<void> save(AuthSession session) async {
    _cached = session;
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(AuthSessionModel.fromDomain(session).toJson()),
      );
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<AuthSession?> read() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null) return null;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          await clear();
          return null;
        }
        final session = AuthSessionModel.fromJson(decoded).toDomain();
        _cached = session;
        return session;
      } on FormatException {
        // Corrupt storage is treated as "signed out" — never crash on it.
        await clear();
        return null;
      } on TypeError {
        await clear();
        return null;
      }
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> clear() async {
    _cached = null;
    try {
      await _storage.delete(key: _storageKey);
    } catch (error, stackTrace) {
      throw CacheException(cause: error, stackTrace: stackTrace);
    }
  }
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
