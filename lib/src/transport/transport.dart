import '../cancel/cancellation_token.dart';
import '../request.dart';
import '../response.dart';

/// Abstract transport interface for HTTP requests
abstract class Transport {
  /// Send an HTTP request
  Future<Response> send(
    Request request, {
    CancellationToken? cancel,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
  });

  /// Dispose resources
  void dispose();
}
