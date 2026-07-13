import '../auth.dart';
import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'interceptor.dart';

/// Callback for getting authentication token
typedef TokenProvider = Future<String?> Function();

/// Callback for refreshing authentication token
typedef TokenRefresher = Future<String?> Function();

/// Interceptor that applies a (pluggable) [Auth] strategy.
///
/// - Stateless strategies ([BasicAuth], [FunctionAuth]) are applied on the
///   request path.
/// - [DigestAuth] goes out unauthenticated, then on a `401` challenge
///   the `WWW-Authenticate` header is parsed and the digest response is
///   attached, signalling a single retry (reuses the client's retry budget).
/// - The legacy Bearer flow ([tokenProvider]/[tokenRefresher]) still works.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    this.auth,
    this.tokenProvider,
    this.tokenRefresher,
    this.headerName = 'Authorization',
    this.headerPrefix = 'Bearer ',
  });

  final Auth? auth;
  final TokenProvider? tokenProvider;
  final TokenRefresher? tokenRefresher;
  final String headerName;
  final String headerPrefix;

  String? _pendingDigest;

  @override
  Future<Request> onRequest(Request request) async {
    var req = request;
    if (auth != null) {
      req = auth!.apply(req);
    }
    if (_pendingDigest != null) {
      req = req.copyWith(
        headers: req.headers.copy()..[headerName] = _pendingDigest!,
      );
      _pendingDigest = null;
    }
    if (tokenProvider != null) {
      final token = await tokenProvider!();
      if (token != null) {
        req = req.copyWith(
          headers: req.headers.copy()..[headerName] = '$headerPrefix$token',
        );
      }
    }
    return req;
  }

  @override
  Future<Response> onResponse(Response response) async => response;

  @override
  Future<Object> onError(HttpError error) async {
    if (error is HttpStatusError && error.statusCode == 401) {
      if (auth is DigestAuth) {
        final challenge = error.response.headers['www-authenticate'];
        if (challenge != null) {
          _pendingDigest = (auth as DigestAuth).buildHeader(
            error.request!,
            challenge,
          );
          return const RetrySignal();
        }
      }
      if (tokenRefresher != null) {
        final newToken = await tokenRefresher!();
        if (newToken != null) {
          return const RetrySignal();
        }
      }
    }
    return Future.error(error);
  }
}
