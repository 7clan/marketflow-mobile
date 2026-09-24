import 'dart:async';

import 'package:dio/dio.dart';

/// Injects the bearer token into every outgoing request and reports session
/// expiry (401 while a token was attached) through the [onUnauthorized]
/// callback so the session owner can clear it.
///
/// Both dependencies are plain callbacks — trivially injectable in tests.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenProvider, required this.onUnauthorized});

  /// Supplies the current access token, or `null` when signed out.
  final Future<String?> Function() tokenProvider;

  /// Invoked when a previously valid token is rejected (401) outside the
  /// login/register endpoints themselves.
  final void Function() onUnauthorized;

  static const _authEndpoints = <String>{'auth/login', 'auth/register'};

  bool _isAuthEndpoint(String path) =>
      _authEndpoints.any((endpoint) => path.contains(endpoint));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    unawaited(() async {
      String? token;
      try {
        token = await tokenProvider();
      } catch (_) {
        // Token lookup must never break traffic — continue anonymously.
      }
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }());
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    final hadToken = err.requestOptions.headers['Authorization'] != null;
    final isAuthEndpoint = _isAuthEndpoint(err.requestOptions.path);

    if (status == 401 && hadToken && !isAuthEndpoint) {
      // A previously valid token is now rejected → the session expired.
      onUnauthorized();
    }
    handler.next(err);
  }
}
