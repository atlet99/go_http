import '../cancel/cancellation_token.dart';
import '../rate_limit_policy.dart';
import '../request.dart';
import '../response.dart';
import 'delegating_transport.dart';
import 'transport.dart';

/// A [DelegatingTransport] that rate-limits requests via a [RateLimitPolicy].
///
/// Before delegating to the inner transport, [send] calls
/// `policy.wait(request.uri.host)` — acquiring a token from the policy's
/// token-bucket (global or per-host).
///
/// ```dart
/// final client = GoHttpClient(
///   transport: RateLimitTransport(
///     IoTransport(),
///     RateLimitPolicy.global(50), // max 50 req/s
///   ),
/// );
/// ```
class RateLimitTransport extends DelegatingTransport {
  RateLimitTransport(super.inner, this.policy);

  final RateLimitPolicy policy;

  @override
  Future<Response> send(
    Request request, {
    CancellationToken? cancel,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    ProgressCallback? onProgress,
    ProgressCallback? onSendProgress,
  }) async {
    await policy.wait(request.uri.host);
    return inner.send(
      request,
      cancel: cancel,
      connectTimeout: connectTimeout,
      sendTimeout: sendTimeout,
      receiveTimeout: receiveTimeout,
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      autoDecompress: autoDecompress,
      onProgress: onProgress,
      onSendProgress: onSendProgress,
    );
  }
}
