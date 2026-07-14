import 'errors.dart';
import 'response.dart';

/// A type-safe result type for HTTP requests.
///
/// Coexists with the exception-based hierarchy ([HttpError]) — use whichever
/// fits your style.  The sealed hierarchy enables exhaustive `switch`:
///
/// ```dart
/// final result = await client.requestResult<Map>(...);
/// switch (result) {
///   case ApiSuccess(:final response):
///     print(response.json());
///   case ApiError(:final error):
///     print('HTTP ${error.statusCode}');
///   case ApiNetworkError(:final error):
///     print('Network: ${error.message}');
/// }
/// ```
sealed class ApiResponse<T> {
  const ApiResponse();
}

/// A successful HTTP response (2xx).
class ApiSuccess<T> extends ApiResponse<T> {
  /// Creates an [ApiSuccess] with [response].
  const ApiSuccess(this.response);

  /// The full HTTP response.
  final Response<T> response;
}

/// An HTTP error response (4xx, 5xx).
class ApiError<T> extends ApiResponse<T> {
  /// Creates an [ApiError] with [error].
  const ApiError(this.error);

  /// The underlying [HttpStatusError].
  final HttpStatusError error;

  /// HTTP status code.
  int get statusCode => error.statusCode;

  /// The response that caused the error.
  Response get response => error.response;
}

/// A network/transport-level failure (DNS, connection, timeout, etc.).
class ApiNetworkError<T> extends ApiResponse<T> {
  /// Creates an [ApiNetworkError] with [error].
  const ApiNetworkError(this.error);

  /// The underlying [RequestError].
  final RequestError error;
}
