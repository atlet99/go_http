import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';

/// Callback invoked as the response body is received.
///
/// [received] is the number of bytes received so far; [total] is the expected
/// total length from `Content-Length`, or `-1` when unknown.
typedef ProgressCallback = void Function(int received, int total);

/// Abstract transport interface for HTTP requests
abstract class Transport {
  /// Send an HTTP request
  ///
  /// [onProgress] reports download progress; [onSendProgress] reports upload
  /// progress (meaningful for streaming request bodies).
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
  });

  /// Dispose resources
  void dispose();
}
