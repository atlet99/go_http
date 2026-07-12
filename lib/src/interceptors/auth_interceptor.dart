import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'interceptor.dart';

/// Callback for getting authentication token
typedef TokenProvider = Future<String?> Function();

/// Callback for refreshing authentication token
typedef TokenRefresher = Future<String?> Function();

/// Interceptor for automatic authentication token management.
///
/// On the request path it attaches the token from [tokenProvider]. When a `401
/// Unauthorized` is received, it refreshes the token via [tokenRefresher] and
/// returns a [RetrySignal]; the client then retries the request (re-running
/// request interceptors so the fresh token is attached).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    this.tokenProvider,
    this.tokenRefresher,
    this.headerName = 'Authorization',
    this.headerPrefix = 'Bearer ',
  });

  final TokenProvider? tokenProvider;
  final TokenRefresher? tokenRefresher;
  final String headerName;
  final String headerPrefix;

  @override
  Future<Request> onRequest(Request request) async {
    if (tokenProvider == null) {
      return request;
    }
    final token = await tokenProvider!();
    if (token == null) {
      return request;
    }
    final headers = request.headers.copy();
    headers[headerName] = '$headerPrefix$token';
    return request.copyWith(headers: headers);
  }

  @override
  Future<Response> onResponse(Response response) async => response;

  @override
  Future<Object> onError(HttpError error) async {
    // Handle 401 by refreshing the token and signalling a retry
    if (error is HttpResponseError &&
        error.statusCode == 401 &&
        tokenRefresher != null) {
      final newToken = await tokenRefresher!();
      if (newToken != null) {
        return const RetrySignal();
      }
    }
    return Future.error(error);
  }
}
