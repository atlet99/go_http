import 'request.dart';
import 'response.dart';

/// Base class for all HTTP errors
abstract class HttpError implements Exception {
  const HttpError({
    required this.request,
    required this.message,
    this.originalError,
  });

  final Request request;
  final String message;
  final Object? originalError;

  @override
  String toString() => message;
}

/// Network-related errors (connection timeout, DNS failure, etc.)
class NetworkError extends HttpError {
  const NetworkError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// HTTP error responses (4xx, 5xx)
class HttpResponseError extends HttpError {
  HttpResponseError({
    required super.request,
    required this.response,
    String? message,
    super.originalError,
  }) : super(
          message: message ??
              'HTTP ${response.statusCode} ${response.statusMessage ?? ''}',
        );

  final Response response;

  int get statusCode => response.statusCode;
}

/// Request timeout error
class TimeoutError extends HttpError {
  TimeoutError({
    required super.request,
    required this.timeout,
    String? message,
    super.originalError,
  }) : super(
          message: message ?? 'Request timeout after ${timeout.inSeconds}s',
        );

  final Duration timeout;
}

/// Request cancellation error
class CancellationError extends HttpError {
  CancellationError({
    required super.request,
    this.reason,
    String? message,
    super.originalError,
  }) : super(
          message: message ??
              'Request cancelled${reason != null ? ': $reason' : ''}',
        );

  final String? reason;
}
