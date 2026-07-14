import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// A [Transport] backed by a caller-supplied handler function.
///
/// This is the primary testing primitive: pass a function that turns a
/// [Request] into a [Response] (or throws), and run the full client pipeline —
/// interceptors, retry, auth, cookies — without any real network I/O.
///
/// Mirrors `httpx.MockTransport`.
///
/// Example:
/// ```dart
/// final client = GoHttpClient(
///   transport: MockTransport((request) async {
///     return Response(
///       request: request,
///       statusCode: 200,
///       data: Uint8List.fromList([1, 2, 3]),
///     );
///   }),
/// );
/// ```
class MockTransport implements Transport {
  MockTransport(this.handler);

  /// Function invoked for every request. May return a [Response] or throw.
  final Future<Response> Function(Request request) handler;

  /// Number of times [send] has been called (useful in tests).
  int callCount = 0;

  /// All requests seen so far (in order).
  final List<Request> sent = [];

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
    cancel?.throwIfCancelled();
    callCount++;
    sent.add(request);
    return handler(request);
  }

  @override
  void dispose() {}
}
