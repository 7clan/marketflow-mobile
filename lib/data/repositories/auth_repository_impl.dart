import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/errors/app_exception.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/network/api_client.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/session_local_data_source.dart';
import '../models/auth_session_model.dart';
import '../models/user_model.dart';

/// Auth repository: real HTTP against the backend plus secure local
/// persistence of the session.
///
/// Every failure leaves this class as an [AppException] — the presentation
/// layer never sees a `DioException`.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.apiClient, required this.local});

  final ApiClient apiClient;
  final SessionLocalDataSource local;

  final StreamController<User?> _userController =
      StreamController<User?>.broadcast();

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppException {
      rethrow;
    } catch (error, stackTrace) {
      throw ErrorMapper.map(error, stackTrace: stackTrace);
    }
  }

  void _emitUser(User? user) {
    if (!_userController.isClosed) _userController.add(user);
  }

  @override
  Stream<User?> get userChanges => _userController.stream;

  @override
  Future<AuthSession> login({required String email, required String password}) {
    return _guard(() async {
      final payload = await apiClient.postObject(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final session = AuthSessionModel.fromJson(payload).toDomain();
      await local.save(session);
      _emitUser(session.user);
      return session;
    });
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final payload = await apiClient.postObject(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      final session = AuthSessionModel.fromJson(payload).toDomain();
      await local.save(session);
      _emitUser(session.user);
      return session;
    });
  }

  @override
  Future<AuthSession?> restoreSession() {
    return _guard(() async {
      final stored = await local.read();
      if (stored == null) {
        _emitUser(null);
        return null;
      }
      // Verify the stored token is still accepted server-side.
      try {
        final userJson = await apiClient.getObject('/auth/me');
        final user = UserModel.fromJson(userJson).toDomain();
        final session = AuthSession(token: stored.token, user: user);
        _emitUser(user);
        return session;
      } on UnauthorizedException {
        await local.clear();
        _emitUser(null);
        return null;
      } on DioException catch (error) {
        // The API client propagates raw transport errors (including 401s),
        // so a rejected token must be recognized here — otherwise an expired
        // session would surface as an app error instead of a clean sign-out.
        if (error.response?.statusCode == 401) {
          await local.clear();
          _emitUser(null);
          return null;
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> logout() async {
    // Local-only sign-out: the token has no server-side revocation, so
    // clearing the persisted session is the complete logout.
    await _guard(local.clear);
    _emitUser(null);
  }

  @override
  Future<User?> currentUser() {
    return _guard(() async => (await local.read())?.user);
  }

  @override
  Future<void> discardLocalSession() async {
    await _guard(local.clear);
    _emitUser(null);
  }

  /// Releases the [userChanges] stream. Called when the owning provider is
  /// disposed.
  void dispose() {
    unawaited(_userController.close());
  }
}
