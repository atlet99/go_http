import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// Abstract base for transports that wrap an inner [Transport].
///
/// The default [send] implementation delegates to [inner] with the same
/// arguments. Subclasses override [send] to add behaviour (rate-limiting,
/// caching, logging, circuit-breaking, etc.) and call `super.send()` or
/// `inner.send()` to continue the chain.
///
/// ```dart
/// class LogTransport extends DelegatingTransport {
///   LogTransport(super.inner);
///   @override
///   Future<Response> send(Request request, { ... }) async {
///     print('>> ${request.method} ${request.uri}');
///     final resp = await super.send(request, ...);
///     print('<< ${resp.statusCode}');
///     return resp;
///   }
/// }
/// ```
abstract class DelegatingTransport implements Transport {
  DelegatingTransport(this.inner);

  Transport inner;

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
  }) =>
      inner.send(
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

  @override
  void dispose() => inner.dispose();
}
