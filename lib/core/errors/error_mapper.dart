import 'package:dio/dio.dart';

import 'app_exception.dart';

/// Single place where transport-level failures become domain [AppException]s.
///
/// Widgets and controllers only ever see `AppException` — Dio/HTTP jargon and
/// JSON parsing errors are converted here into user-safe errors. The
/// MarketFlow error envelope is `{"error": {"code": ..., "message": ...}}`;
/// when the backend supplies a message it is surfaced (it is guaranteed to be
/// user-safe), otherwise the exception's own fallback copy is used.
abstract final class ErrorMapper {
  /// Maps any thrown object to an [AppException].
  ///
  /// Already-mapped exceptions pass through untouched so repositories can
  /// call this in a single `catch` without double-wrapping.
  static AppException map(Object error, {StackTrace? stackTrace}) {
    if (error is AppException) return error;

    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return TimeoutException(cause: error, stackTrace: stackTrace);
        case DioExceptionType.connectionError:
          return NetworkException(cause: error, stackTrace: stackTrace);
        case DioExceptionType.badResponse:
          return _mapBadResponse(error, stackTrace);
        case DioExceptionType.cancel:
          return CancelledException(cause: error, stackTrace: stackTrace);
        case DioExceptionType.badCertificate:
          return NetworkException(cause: error, stackTrace: stackTrace);
        case DioExceptionType.unknown:
          return _unwrapUnknown(error, stackTrace);
      }
    }

    if (error is FormatException || error is TypeError) {
      return MalformedResponseException(cause: error, stackTrace: stackTrace);
    }

    return UnknownException(cause: error, stackTrace: stackTrace);
  }

  static AppException _mapBadResponse(DioException error, StackTrace? stack) {
    final status = error.response?.statusCode ?? 0;
    final envelope = _errorEnvelope(error.response);

    switch (status) {
      case 400:
      case 422:
        final fieldErrors = _readFieldErrors(envelope);
        if (fieldErrors.isNotEmpty) {
          return ValidationException(
            fieldErrors: fieldErrors,
            code: _readCode(envelope),
            cause: error,
            stackTrace: stack,
          );
        }
        return BadRequestException(
          serverMessage: _readMessage(envelope),
          code: _readCode(envelope),
          cause: error,
          stackTrace: stack,
        );
      case 401:
        return UnauthorizedException(
          serverMessage: _readMessage(envelope),
          code: _readCode(envelope),
          cause: error,
          stackTrace: stack,
        );
      case 403:
        return ForbiddenException(
          serverMessage: _readMessage(envelope),
          code: _readCode(envelope),
          cause: error,
          stackTrace: stack,
        );
      case 404:
        return NotFoundException(
          serverMessage: _readMessage(envelope),
          code: _readCode(envelope),
          cause: error,
          stackTrace: stack,
        );
      case 409:
        return ConflictException(
          serverMessage: _readMessage(envelope),
          conflictingItems: _readItems(envelope),
          code: _readCode(envelope),
          cause: error,
          stackTrace: stack,
        );
      default:
        if (status >= 500) {
          return ServerException(
            statusCode: status,
            serverMessage: _readMessage(envelope),
            code: _readCode(envelope),
            cause: error,
            stackTrace: stack,
          );
        }
        return ServerException(
          statusCode: status,
          serverMessage: _readMessage(envelope),
          cause: error,
          stackTrace: stack,
        );
    }
  }

  /// Extracts the `{"error": {...}}` envelope from a response, tolerating
  /// bodies that are not maps at all (they simply yield no extra detail).
  static Map<String, dynamic> _errorEnvelope(Response<dynamic>? response) {
    final data = response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic>) return error;
      return data;
    }
    return const <String, dynamic>{};
  }

  static String? _readMessage(Map<String, dynamic> envelope) {
    final message = envelope['message'];
    return message is String && message.trim().isNotEmpty ? message : null;
  }

  static String? _readCode(Map<String, dynamic> envelope) {
    final code = envelope['code'];
    return code is String && code.trim().isNotEmpty ? code : null;
  }

  /// Reads `errors: {field: [messages...]}` from the envelope.
  static Map<String, List<String>> _readFieldErrors(
    Map<String, dynamic> envelope,
  ) {
    final rawErrors = envelope['errors'];
    if (rawErrors is! Map<String, dynamic>) return const {};
    final fieldErrors = <String, List<String>>{};
    for (final entry in rawErrors.entries) {
      final messages = entry.value;
      if (messages is List && messages.isNotEmpty) {
        fieldErrors[entry.key] = [for (final m in messages) m.toString()];
      }
    }
    return fieldErrors;
  }

  static List<String> _readItems(Map<String, dynamic> envelope) {
    final items = envelope['items'];
    if (items is! List) return const <String>[];
    return [
      for (final item in items)
        if (item is String) item,
    ];
  }

  /// Dio sometimes wraps adapter-level exceptions as `unknown` with the
  /// original error nested inside — unwrap before deciding.
  static AppException _unwrapUnknown(DioException error, StackTrace? stack) {
    Object? cause = error.error;
    while (cause is DioException) {
      if (cause.type == DioExceptionType.connectionError) {
        return NetworkException(cause: cause, stackTrace: stack);
      }
      if (cause.type == DioExceptionType.receiveTimeout ||
          cause.type == DioExceptionType.connectionTimeout ||
          cause.type == DioExceptionType.sendTimeout) {
        return TimeoutException(cause: cause, stackTrace: stack);
      }
      cause = cause.error;
    }
    if (cause is FormatException || cause is TypeError) {
      // Typically the JSON decoder choking on a non-JSON body.
      return MalformedResponseException(cause: cause, stackTrace: stack);
    }
    return UnknownException(cause: error, stackTrace: stack);
  }
}
