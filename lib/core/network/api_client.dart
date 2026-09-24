import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../errors/app_exception.dart';
import 'auth_interceptor.dart';

/// The app's typed HTTP surface over a real [Dio] pipeline.
///
/// Responsibilities:
/// * applies [AppConfig] (base URL, timeouts, headers) to a genuine [Dio];
/// * attaches the bearer token and reports session expiry through
///   [AuthInterceptor];
/// * unwraps the MarketFlow response envelope `{"data": ...}` and guarantees
///   the payload type the caller asked for, throwing
///   [MalformedResponseException] otherwise.
///
/// Non-2xx statuses propagate as [DioException]s — repositories translate
/// them with `ErrorMapper` before anything reaches the UI. Swapping the mock
/// backend for a production API is a one-line [AppConfig] change.
class ApiClient {
  ApiClient({
    required AppConfig config,
    required Future<String?> Function() tokenProvider,
    void Function()? onUnauthorized,
  }) : _dio = Dio(
         BaseOptions(
           baseUrl: config.baseUrl,
           connectTimeout: config.connectTimeout,
           receiveTimeout: config.receiveTimeout,
           sendTimeout: config.sendTimeout,
           headers: {'Accept': 'application/json'},
           responseType: ResponseType.json,
         ),
       ) {
    _dio.interceptors.add(
      AuthInterceptor(
        tokenProvider: tokenProvider,
        onUnauthorized: onUnauthorized ?? _ignoreUnauthorized,
      ),
    );
  }

  final Dio _dio;

  /// The underlying [Dio], exposed for attaching extra interceptors (e.g.
  /// logging in integration tests). Requests should still go through this
  /// class so the envelope contract stays in one place.
  Dio get dio => _dio;

  /// Sends a GET and returns the envelope's `data` payload as a JSON object.
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _unwrapObject(
      () => _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ),
    );
  }

  /// Sends a GET and returns the envelope's `data` payload as a JSON array.
  Future<List<dynamic>> getArray(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _unwrapArray(
      () => _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ),
    );
  }

  /// Sends a POST and returns the envelope's `data` payload as a JSON object.
  Future<Map<String, dynamic>> postObject(
    String path, {
    Object? data,
    CancelToken? cancelToken,
  }) {
    return _unwrapObject(
      () => _dio.post<dynamic>(path, data: data, cancelToken: cancelToken),
    );
  }

  /// Sends a DELETE and returns the envelope's `data` payload as a JSON object.
  Future<Map<String, dynamic>> deleteObject(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
  }) {
    return _unwrapObject(
      () => _dio.delete<dynamic>(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      ),
    );
  }

  /// Closes the underlying connection pool.
  void close() => _dio.close();

  Future<Map<String, dynamic>> _unwrapObject(
    Future<Response<dynamic>> Function() send,
  ) async {
    final response = await send();
    final payload = _payloadOf(response);
    if (payload is Map<String, dynamic>) return payload;
    throw MalformedResponseException(
      cause:
          'Expected a JSON object payload but received '
          '${payload.runtimeType}',
    );
  }

  Future<List<dynamic>> _unwrapArray(
    Future<Response<dynamic>> Function() send,
  ) async {
    final response = await send();
    final payload = _payloadOf(response);
    if (payload is List) return payload;
    throw MalformedResponseException(
      cause:
          'Expected a JSON array payload but received '
          '${payload.runtimeType}',
    );
  }

  /// Extracts the `data` field from `{"data": ...}`.
  Object? _payloadOf(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      throw MalformedResponseException(
        cause:
            'Expected the {"data": ...} envelope but received '
            '${body.runtimeType}',
      );
    }
    if (!body.containsKey('data')) {
      throw MalformedResponseException(
        cause: 'Response envelope is missing the "data" field.',
      );
    }
    return body['data'];
  }

  void _ignoreUnauthorized() {
    // No session owner attached — expiry handling is opt-in.
  }
}
