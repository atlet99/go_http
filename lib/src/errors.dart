import 'request.dart';
import 'response.dart';

/// Base class for all HTTP-related errors.
///
/// [request] is `null` for errors that are not tied to a single request
/// (e.g. [InvalidUrl], [CookieConflict]).
abstract class HttpError implements Exception {
  const HttpError({this.request, required this.message, this.originalError});

  final Request? request;
  final String message;
  final Object? originalError;

  @override
  String toString() => message;
}

/// Errors scoped to a particular [Request] — every failure except a plain
/// status response or a client-config problem. Catch this to handle any
/// request-scoped failure at once.
abstract class RequestError extends HttpError {
  const RequestError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// Failure in the underlying transport (connect/read/write/protocol/proxy).
abstract class TransportError extends RequestError {
  const TransportError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// A timeout during one of the request phases.
class TimeoutError extends TransportError {
  const TimeoutError({
    required super.request,
    required this.timeout,
    required super.message,
    super.originalError,
  });

  final Duration timeout;
}

class ConnectTimeoutError extends TimeoutError {
  ConnectTimeoutError({
    required super.request,
    required super.timeout,
    super.originalError,
  }) : super(message: 'Connection timeout after ${timeout.inSeconds}s');
}

class ReadTimeoutError extends TimeoutError {
  ReadTimeoutError({
    required super.request,
    required super.timeout,
    super.originalError,
  }) : super(message: 'Read timeout after ${timeout.inSeconds}s');
}

class WriteTimeoutError extends TimeoutError {
  WriteTimeoutError({
    required super.request,
    required super.timeout,
    super.originalError,
  }) : super(message: 'Write timeout after ${timeout.inSeconds}s');
}

class PoolTimeoutError extends TimeoutError {
  PoolTimeoutError({
    required super.request,
    required super.timeout,
    super.originalError,
  }) : super(message: 'Pool timeout after ${timeout.inSeconds}s');
}

/// A network-level failure (DNS, refused, dropped connection...).
class NetworkError extends TransportError {
  const NetworkError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class ConnectError extends NetworkError {
  ConnectError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class ReadError extends NetworkError {
  ReadError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class WriteError extends NetworkError {
  WriteError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class CloseError extends NetworkError {
  CloseError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class ProtocolError extends TransportError {
  const ProtocolError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class LocalProtocolError extends ProtocolError {
  LocalProtocolError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class RemoteProtocolError extends ProtocolError {
  RemoteProtocolError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class ProxyError extends TransportError {
  ProxyError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class UnsupportedProtocol extends TransportError {
  UnsupportedProtocol({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// Failure while decoding a response body.
class DecodingError extends RequestError {
  const DecodingError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// Too many redirects followed.
class TooManyRedirects extends RequestError {
  const TooManyRedirects({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// Request cancelled via a [CancellationToken].
class CancellationError extends RequestError {
  const CancellationError({
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

/// HTTP error responses (4xx, 5xx).
///
/// Deliberately does **not** extend [RequestError] — a status error is a
/// valid server response, not a transport/request failure, so
/// `catch (RequestError)` must not swallow a 404.
class HttpStatusError extends HttpError {
  HttpStatusError({
    required Request request,
    required this.response,
    String? message,
    super.originalError,
  }) : super(
          request: request,
          message: message ??
              'HTTP ${response.statusCode} ${response.statusMessage ?? ''}',
        );

  final Response response;

  int get statusCode => response.statusCode;
}

/// A URL could not be parsed / used.
class InvalidUrl extends HttpError {
  const InvalidUrl({
    required this.url,
    required super.message,
    super.originalError,
  }) : super(request: null);

  final String url;
}

/// Multiple cookies matched a lookup and disambiguation is required.
class CookieConflict extends HttpError {
  const CookieConflict({required super.message, super.originalError})
      : super(request: null);
}

/// Error involving the request/response byte stream.
abstract class StreamError extends RequestError {
  const StreamError({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class StreamConsumed extends StreamError {
  StreamConsumed({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class StreamClosed extends StreamError {
  StreamClosed({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class ResponseNotRead extends StreamError {
  ResponseNotRead({
    required super.request,
    required super.message,
    super.originalError,
  });
}

class RequestNotRead extends StreamError {
  RequestNotRead({
    required super.request,
    required super.message,
    super.originalError,
  });
}

/// Sentinel returned by [Interceptor.onError] to signal that the error was
/// resolved (e.g. credentials were refreshed) and the request should be sent
/// again.
///
/// The client retries the request a bounded number of times (once by default)
/// when it receives a [RetrySignal] from an interceptor.
class RetrySignal {
  const RetrySignal();
}
