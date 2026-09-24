import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/errors/app_exception.dart';
import 'package:marketflow/core/errors/error_mapper.dart';

RequestOptions _options() => RequestOptions(path: '/test');

DioException _timeout(DioExceptionType type) =>
    DioException(requestOptions: _options(), type: type);

DioException _badResponse(int status, {Object? data}) {
  return DioException(
    requestOptions: _options(),
    type: DioExceptionType.badResponse,
    response: Response<Object?>(
      requestOptions: _options(),
      statusCode: status,
      data: data,
    ),
  );
}

void main() {
  group('ErrorMapper.map — transport failures', () {
    test('connection timeout becomes TimeoutException', () {
      final mapped = ErrorMapper.map(
        _timeout(DioExceptionType.connectionTimeout),
      );
      expect(mapped, isA<TimeoutException>());
    });

    test('receive timeout becomes TimeoutException', () {
      final mapped = ErrorMapper.map(_timeout(DioExceptionType.receiveTimeout));
      expect(mapped, isA<TimeoutException>());
    });

    test('send timeout becomes TimeoutException', () {
      final mapped = ErrorMapper.map(_timeout(DioExceptionType.sendTimeout));
      expect(mapped, isA<TimeoutException>());
    });

    test('connection error becomes NetworkException', () {
      final mapped = ErrorMapper.map(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.connectionError,
          error: 'socket failed',
        ),
      );
      expect(mapped, isA<NetworkException>());
      expect(
        mapped.message,
        'No connection. Check your internet and try again.',
      );
    });

    test('bad certificate becomes NetworkException', () {
      final mapped = ErrorMapper.map(_timeout(DioExceptionType.badCertificate));
      expect(mapped, isA<NetworkException>());
    });

    test('cancellation becomes CancelledException', () {
      final mapped = ErrorMapper.map(_timeout(DioExceptionType.cancel));
      expect(mapped, isA<CancelledException>());
      expect(mapped.message, 'This request was cancelled.');
    });

    test('unknown DioException wrapping a connection error becomes NetworkException', () {
      final nested = DioException(
        requestOptions: _options(),
        type: DioExceptionType.connectionError,
      );
      final mapped = ErrorMapper.map(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.unknown,
          error: nested,
        ),
      );
      expect(mapped, isA<NetworkException>());
    });

    test('unknown DioException wrapping a receive timeout becomes TimeoutException', () {
      final nested = DioException(
        requestOptions: _options(),
        type: DioExceptionType.receiveTimeout,
      );
      final mapped = ErrorMapper.map(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.unknown,
          error: nested,
        ),
      );
      expect(mapped, isA<TimeoutException>());
    });

    test('unknown DioException wrapping a FormatException becomes '
        'MalformedResponseException', () {
      final mapped = ErrorMapper.map(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.unknown,
          error: const FormatException('not JSON'),
        ),
      );
      expect(mapped, isA<MalformedResponseException>());
      expect(
        mapped.message,
        'We received an unexpected response from the server.',
      );
    });

    test('bare unknown DioException becomes UnknownException', () {
      final mapped = ErrorMapper.map(
        DioException(
          requestOptions: _options(),
          type: DioExceptionType.unknown,
        ),
      );
      expect(mapped, isA<UnknownException>());
      expect(mapped.message, 'Something went wrong. Please try again.');
    });
  });

  group('ErrorMapper.map — HTTP status codes', () {
    test('401 without envelope falls back to session-expired copy', () {
      final mapped = ErrorMapper.map(_badResponse(401));
      expect(mapped, isA<UnauthorizedException>());
      expect(mapped.code, isNull);
      expect(mapped.message, 'Your session has expired. Please sign in again.');
    });

    test('401 surfaces the server message and code', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          401,
          data: {
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid email or password.',
            },
          },
        ),
      );
      expect(mapped, isA<UnauthorizedException>());
      expect(mapped.code, 'invalid_credentials');
      expect(mapped.message, 'Invalid email or password.');
    });

    test('403 becomes ForbiddenException with fallback copy', () {
      final mapped = ErrorMapper.map(_badResponse(403));
      expect(mapped, isA<ForbiddenException>());
      expect(
        mapped.message,
        "You don't have permission to perform this action.",
      );
    });

    test('404 becomes NotFoundException and surfaces the server message', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          404,
          data: {
            'error': {'code': 'not_found', 'message': 'Unknown product.'},
          },
        ),
      );
      expect(mapped, isA<NotFoundException>());
      expect(mapped.message, 'Unknown product.');
    });

    test('plain 400 without field errors becomes BadRequestException', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          400,
          data: {
            'error': {'code': 'bad_request', 'message': 'minPrice is invalid.'},
          },
        ),
      );
      expect(mapped, isA<BadRequestException>());
      expect(mapped.code, 'bad_request');
      expect(mapped.message, 'minPrice is invalid.');
    });

    test('422 with field errors becomes ValidationException', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          422,
          data: {
            'error': {
              'code': 'validation',
              'message': 'Please review the highlighted fields.',
              'errors': {
                'email': ['Enter a valid email address.'],
                'password': ['Use at least 8 characters.'],
              },
            },
          },
        ),
      );
      expect(mapped, isA<ValidationException>());
      final validation = mapped as ValidationException;
      expect(validation.fieldErrors.keys, containsAll(['email', 'password']));
      expect(validation.fieldErrors['email'], ['Enter a valid email address.']);
      expect(
        mapped.message,
        'Please review the highlighted fields and try again.',
      );
    });

    test('422 without field errors degrades to BadRequestException', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          422,
          data: {
            'error': {'message': 'Unprocessable.'},
          },
        ),
      );
      expect(mapped, isA<BadRequestException>());
      expect(mapped.message, 'Unprocessable.');
    });

    test('409 becomes ConflictException with conflicting item ids', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          409,
          data: {
            'error': {
              'code': 'out_of_stock',
              'message': 'Some items are no longer available.',
              'items': ['p03', 'p10'],
            },
          },
        ),
      );
      expect(mapped, isA<ConflictException>());
      final conflict = mapped as ConflictException;
      expect(conflict.conflictingItems, ['p03', 'p10']);
      expect(conflict.message, 'Some items are no longer available.');
    });

    test('500 becomes ServerException carrying the status code', () {
      final mapped = ErrorMapper.map(
        _badResponse(
          500,
          data: {
            'error': {'code': 'forced_status', 'message': 'Simulated failure.'},
          },
        ),
      );
      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).statusCode, 500);
      expect(mapped.message, 'Simulated failure.');
    });

    test('503 without a message uses the fallback server copy', () {
      final mapped = ErrorMapper.map(_badResponse(503));
      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).statusCode, 503);
      expect(
        mapped.message,
        'Something went wrong on our side. Please try again.',
      );
    });

    test('unexpected 3xx-style status is treated as a server failure', () {
      final mapped = ErrorMapper.map(_badResponse(302));
      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).statusCode, 302);
    });

    test('non-map error bodies are tolerated', () {
      final mapped = ErrorMapper.map(_badResponse(500, data: 'oops'));
      expect(mapped, isA<ServerException>());
      expect((mapped as ServerException).serverMessage, isNull);
    });
  });

  group('ErrorMapper.map — non-Dio failures', () {
    test('FormatException becomes MalformedResponseException', () {
      final mapped = ErrorMapper.map(const FormatException('bad json'));
      expect(mapped, isA<MalformedResponseException>());
    });

    test('TypeError becomes MalformedResponseException', () {
      final mapped = ErrorMapper.map(
        TypeError(),
        stackTrace: StackTrace.current,
      );
      expect(mapped, isA<MalformedResponseException>());
    });

    test('any other object becomes UnknownException', () {
      final mapped = ErrorMapper.map(Exception('boom'));
      expect(mapped, isA<UnknownException>());
      expect(mapped.cause, isA<Exception>());
    });

    test('AppException instances pass through untouched', () {
      const original = CacheException(code: 'cache');
      final mapped = ErrorMapper.map(original);
      expect(identical(mapped, original), isTrue);
    });
  });
}
