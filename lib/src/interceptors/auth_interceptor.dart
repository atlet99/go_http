import '../auth.dart';
import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'interceptor.dart';

/// Callback for getting authentication token.
///
/// Use [BearerAuth] with a resolved token instead.
typedef TokenProvider = Future<String?> Function();

/// Callback for refreshing authentication token.
///
/// Use [BearerAuth] with a [AuthInterceptor]'s retry flow instead.
typedef TokenRefresher = Future<String?> Function();

/// Interceptor that applies a (pluggable) [Auth] strategy.
///
/// - Stateless strategies ([BasicAuth], [BearerAuth], [FunctionAuth]) are
///   applied on the request path.
/// - [DigestAuth] goes out unauthenticated, then on a `401` challenge
///   the `WWW-Authenticate` header is parsed and the digest response is
///   attached, signalling a single retry (reuses the client's retry budget).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    this.auth,
    @Deprecated('Use BearerAuth(auth) instead') this.tokenProvider,
    @Deprecated('Use BearerAuth with onError hook instead') this.tokenRefresher,
    @Deprecated('No longer needed — BearerAuth sets the header')
    this.headerName = 'Authorization',
    @Deprecated('No longer needed — BearerAuth sets the prefix')
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

    // 1. Apply the auth strategy (stateless — Basic, Bearer, etc.)
    if (auth != null) {
      req = auth!.apply(req);
    }

    // 2. Digest retry — attach the computed challenge response
    if (_pendingDigest != null) {
      req = req.copyWith(
        headers: req.headers.copy()..[headerName] = _pendingDigest!,
      );
      _pendingDigest = null;
    }

    // 3. Legacy bearer flow — wraps in BearerAuth internally
    if (tokenProvider != null && auth == null) {
      final token = await tokenProvider!();
      if (token != null) {
        req = BearerAuth(token).apply(req);
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
