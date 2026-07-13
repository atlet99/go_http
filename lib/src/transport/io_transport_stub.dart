import '../cancel/cancellation_token.dart';
import '../dns_resolver.dart';
import '../proxy.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// Stub for IO transport on web platforms
class IoTransport implements Transport {
  IoTransport({
    dynamic httpClient,
    int maxConnectionsPerHost = 6,
    bool autoDecompress = true,
    this.tryHttpOnHttpsError = false,
    this.resolver,
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
    Object? minTlsVersion,
    Object? maxTlsVersion,
  });

  final bool tryHttpOnHttpsError;
  final DnsResolver? resolver;

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
    throw UnsupportedError('IoTransport is only available on native platforms');
  }

  @override
  void dispose() {
    // No-op
  }
}
