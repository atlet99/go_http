import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// Stub for web transport on non-web platforms
class WebTransport implements Transport {
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
  }) {
    throw UnsupportedError('WebTransport is only available on web platforms');
  }

  @override
  void dispose() {
    // No-op
  }
}
