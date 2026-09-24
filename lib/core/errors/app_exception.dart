/// Base type for every failure the UI may need to present.
///
/// Repositories translate low-level transport / HTTP / parsing / storage
/// errors into these user-safe types so widgets never receive raw technical
/// error text. Every subclass exposes [message] — a short, human-readable
/// string that is safe to render directly.
sealed class AppException implements Exception {
  const AppException({this.code, this.cause, this.stackTrace});

  /// Machine-readable error code from the API error envelope, when present
  /// (e.g. `out_of_stock`). Useful for logging and tests; never shown to users.
  final String? code;

  /// Original error, kept for logging — never shown to users.
  final Object? cause;

  /// Stack trace of the original error, for diagnostics.
  final StackTrace? stackTrace;

  /// Human-readable, non-technical message safe to display in the UI.
  String get message;

  @override
  String toString() => '$runtimeType${code == null ? '' : '($code)'}: $message';
}

/// The device is offline or the server cannot be reached at all.
class NetworkException extends AppException {
  const NetworkException({super.code, super.cause, super.stackTrace});

  @override
  String get message => 'No connection. Check your internet and try again.';
}

/// The request took longer than the configured timeouts.
class TimeoutException extends AppException {
  const TimeoutException({super.code, super.cause, super.stackTrace});

  @override
  String get message =>
      'The server is taking too long to respond. Please try again.';
}

/// Missing or expired credentials (HTTP 401).
class UnauthorizedException extends AppException {
  const UnauthorizedException({
    this.serverMessage,
    super.code,
    super.cause,
    super.stackTrace,
  });

  /// User-safe message supplied by the API, when the backend provides one
  /// (e.g. "Invalid email or password.").
  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? 'Your session has expired. Please sign in again.';
}

/// Authenticated but not allowed to perform the action (HTTP 403).
class ForbiddenException extends AppException {
  const ForbiddenException({
    this.serverMessage,
    super.code,
    super.cause,
    super.stackTrace,
  });

  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? "You don't have permission to perform this action.";
}

/// Requested resource does not exist (HTTP 404).
class NotFoundException extends AppException {
  const NotFoundException({
    this.serverMessage,
    super.code,
    super.cause,
    super.stackTrace,
  });

  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? 'What you were looking for is no longer available.';
}

/// The API rejected the request payload outright (HTTP 400).
class BadRequestException extends AppException {
  const BadRequestException({
    this.serverMessage,
    super.code,
    super.cause,
    super.stackTrace,
  });

  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? 'The request could not be processed. Please try again.';
}

/// The API rejected the request payload with per-field messages (HTTP 422).
///
/// Carries the field → messages map the forms can render inline.
class ValidationException extends AppException {
  const ValidationException({
    required this.fieldErrors,
    super.code,
    super.cause,
    super.stackTrace,
  });

  /// Field name → list of validation messages (never empty for a field).
  final Map<String, List<String>> fieldErrors;

  @override
  String get message => 'Please review the highlighted fields and try again.';
}

/// The request conflicts with the current server state (HTTP 409).
///
/// Checkout uses this to report items that went out of stock between the
/// cart being loaded and the order being placed.
class ConflictException extends AppException {
  const ConflictException({
    this.serverMessage,
    this.conflictingItems = const <String>[],
    super.code,
    super.cause,
    super.stackTrace,
  });

  final String? serverMessage;

  /// Identifiers (e.g. product ids) the conflict refers to.
  final List<String> conflictingItems;

  @override
  String get message =>
      serverMessage ??
      'This item just went out of stock. Please review your cart.';
}

/// Server-side failure (HTTP 5xx) or any unexpected status code.
class ServerException extends AppException {
  const ServerException({
    this.statusCode,
    this.serverMessage,
    super.code,
    super.cause,
    super.stackTrace,
  });

  final int? statusCode;
  final String? serverMessage;

  @override
  String get message =>
      serverMessage ?? 'Something went wrong on our side. Please try again.';
}

/// The request was cancelled (e.g. search superseded by a newer query).
class CancelledException extends AppException {
  const CancelledException({super.code, super.cause, super.stackTrace});

  @override
  String get message => 'This request was cancelled.';
}

/// The response body could not be decoded or did not match the expected shape.
class MalformedResponseException extends AppException {
  const MalformedResponseException({super.code, super.cause, super.stackTrace});

  @override
  String get message => 'We received an unexpected response from the server.';
}

/// Local persistence (cart / session / favorites cache) failed.
class CacheException extends AppException {
  const CacheException({super.code, super.cause, super.stackTrace});

  @override
  String get message => 'We could not access saved data on this device.';
}

/// Anything that does not fit any category above — the safe fallback.
class UnknownException extends AppException {
  const UnknownException({super.code, super.cause, super.stackTrace});

  @override
  String get message => 'Something went wrong. Please try again.';
}
