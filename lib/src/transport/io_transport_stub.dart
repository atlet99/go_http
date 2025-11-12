import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// Stub for IO transport on web platforms
class IoTransport implements Transport {
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
  }) {
    throw UnsupportedError('IoTransport is only available on native platforms');
  }

  @override
  void dispose() {
    // No-op
  }
}
