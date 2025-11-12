import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'interceptor.dart';

/// Callback for getting authentication token
typedef TokenProvider = Future<String?> Function();

/// Callback for refreshing authentication token
typedef TokenRefresher = Future<String?> Function();

/// Interceptor for automatic authentication token management
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
  bool _isRefreshing = false;

  @override
  Future<Request> onRequest(Request request) async {
    if (tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null) {
        final headers = Map<String, String>.from(request.headers);
        headers[headerName] = '$headerPrefix$token';
        return request.copyWith(headers: headers);
      }
    }
    return request;
  }

  @override
  Future<Response> onResponse(Response response) async {
    // If we get 401 Unauthorized, try to refresh token
    if (response.statusCode == 401 && tokenRefresher != null) {
      if (!_isRefreshing) {
        _isRefreshing = true;
        try {
          final newToken = await tokenRefresher!();
          if (newToken != null) {
            // Note: Actual retry should be handled by the client
            // Token has been refreshed, return response to allow retry
            return response;
          }
        } finally {
          _isRefreshing = false;
        }
      }
    }
    return response;
  }

  @override
  Future<Object> onError(HttpError error) async {
    // Handle 401 errors
    if (error is HttpResponseError && error.statusCode == 401) {
      if (tokenRefresher != null && !_isRefreshing) {
        _isRefreshing = true;
        try {
          final newToken = await tokenRefresher!();
          if (newToken != null) {
            // Token refreshed, let client retry
            return error;
          }
        } finally {
          _isRefreshing = false;
        }
      }
    }
    return Future.error(error);
  }
}
