import 'cookie/cookie_store.dart';
import 'enrichment.dart';
import 'event_hooks.dart';
import 'interceptors/interceptor.dart';
import 'metrics/metrics_sink.dart';
import 'policy/redirect_policy.dart';
import 'policy/retry_policy.dart';
import 'proxy.dart';
import 'timeout.dart';
import 'transport/transport.dart';

/// A configuration validation issue.
class ValidationError {
  const ValidationError(this.field, this.message);
  final String field;
  final String message;
  @override
  String toString() => '$field: $message';
}

/// Low-level transport and HTTP behaviour configuration.
///
/// Mirrors `common/httpx/option.go` — concerns: timeouts, retry, TLS, proxy,
/// cookies, default headers. Use with [GoHttpClient] as a base layer,
/// overridable via individual constructor parameters.
class ClientConfig {
  const ClientConfig({
    this.transport,
    this.timeout,
    this.connectTimeout = const Duration(seconds: 10),
    this.sendTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.retryPolicy,
    this.redirectPolicy,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.autoDecompress = true,
    this.maxAuthRetries = 1,
    this.verify,
    this.proxyMounts,
    this.trustEnv = true,
    this.defaultHeaders = const {'accept-encoding': 'gzip, deflate, br'},
    this.cookieStore,
  });

  final Transport? transport;
  final Timeout? timeout;
  final Duration connectTimeout;
  final Duration sendTimeout;
  final Duration receiveTimeout;
  final RetryPolicy? retryPolicy;
  final RedirectPolicy? redirectPolicy;
  final bool followRedirects;
  final int maxRedirects;
  final bool autoDecompress;
  final int maxAuthRetries;
  final Object? verify;
  final ProxyMounts? proxyMounts;
  final bool trustEnv;
  final Map<String, String> defaultHeaders;
  final CookieStore? cookieStore;

  List<ValidationError> validate() {
    final errors = <ValidationError>[];
    if (connectTimeout <= Duration.zero) {
      errors.add(const ValidationError('connectTimeout', 'must be positive'));
    }
    if (sendTimeout <= Duration.zero) {
      errors.add(const ValidationError('sendTimeout', 'must be positive'));
    }
    if (receiveTimeout <= Duration.zero) {
      errors.add(const ValidationError('receiveTimeout', 'must be positive'));
    }
    if (maxRedirects < 0) {
      errors.add(const ValidationError('maxRedirects', 'must be non-negative'));
    }
    if (maxAuthRetries < 0) {
      errors.add(const ValidationError('maxAuthRetries', 'must be non-negative'));
    }
    return errors;
  }

  static const ClientConfig defaults = ClientConfig();
}

/// High-level execution orchestration configuration.
///
/// Mirrors `runner/options.go` — concerns: interceptors, metrics, event hooks.
/// These control *how* requests are executed rather than *what* the transport
/// does.
class ExecutorConfig {
  const ExecutorConfig({
    this.interceptors = const [],
    this.metrics,
    this.eventHooks,
    this.enrichers = const [],
  });

  final List<Interceptor> interceptors;
  final MetricsSink? metrics;
  final EventHooks? eventHooks;
  final List<ResponseEnricher> enrichers;

  List<ValidationError> validate() => const [];

  static const ExecutorConfig defaults = ExecutorConfig();
}
