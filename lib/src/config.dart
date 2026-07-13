import 'dart:io' show Platform;

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
    this.minTlsVersion,
    this.maxTlsVersion,
  });

  /// Creates from a JSON/Map representation.
  ///
  /// Timeout fields accept either an int (milliseconds) or a Duration.
  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    Duration? dur(String key) {
      final v = json[key];
      if (v is Duration) {
        return v;
      }
      if (v is int) {
        return Duration(milliseconds: v);
      }
      return null;
    }

    return ClientConfig(
      connectTimeout: dur('connectTimeout') ?? const Duration(seconds: 10),
      sendTimeout: dur('sendTimeout') ?? const Duration(seconds: 30),
      receiveTimeout: dur('receiveTimeout') ?? const Duration(seconds: 30),
      followRedirects: json['followRedirects'] as bool? ?? true,
      maxRedirects: json['maxRedirects'] as int? ?? 5,
      autoDecompress: json['autoDecompress'] as bool? ?? true,
      maxAuthRetries: json['maxAuthRetries'] as int? ?? 1,
      trustEnv: json['trustEnv'] as bool? ?? true,
      defaultHeaders: json['defaultHeaders'] is Map
          ? Map<String, String>.from(json['defaultHeaders'] as Map)
          : const {'accept-encoding': 'gzip, deflate, br'},
      verify: json['verify'],
      minTlsVersion: json['minTlsVersion'],
      maxTlsVersion: json['maxTlsVersion'],
    );
  }

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

  /// Minimum TLS version (e.g. dart:io `TlsVersion.tls1_2`).
  /// Use `Object?` to avoid platform dependency; IoTransport casts the value.
  final Object? minTlsVersion;

  /// Maximum TLS version (e.g. dart:io `TlsVersion.tls1_3`).
  final Object? maxTlsVersion;

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
      errors
          .add(const ValidationError('maxAuthRetries', 'must be non-negative'));
    }
    return errors;
  }

  /// Returns a copy with the given fields replaced.
  ClientConfig copyWith({
    Transport? transport,
    Timeout? timeout,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    int? maxAuthRetries,
    Object? verify,
    ProxyMounts? proxyMounts,
    bool? trustEnv,
    Map<String, String>? defaultHeaders,
    CookieStore? cookieStore,
    Object? minTlsVersion,
    Object? maxTlsVersion,
  }) =>
      ClientConfig(
        transport: transport ?? this.transport,
        timeout: timeout ?? this.timeout,
        connectTimeout: connectTimeout ?? this.connectTimeout,
        sendTimeout: sendTimeout ?? this.sendTimeout,
        receiveTimeout: receiveTimeout ?? this.receiveTimeout,
        retryPolicy: retryPolicy ?? this.retryPolicy,
        redirectPolicy: redirectPolicy ?? this.redirectPolicy,
        followRedirects: followRedirects ?? this.followRedirects,
        maxRedirects: maxRedirects ?? this.maxRedirects,
        autoDecompress: autoDecompress ?? this.autoDecompress,
        maxAuthRetries: maxAuthRetries ?? this.maxAuthRetries,
        verify: verify ?? this.verify,
        proxyMounts: proxyMounts ?? this.proxyMounts,
        trustEnv: trustEnv ?? this.trustEnv,
        defaultHeaders: defaultHeaders ?? this.defaultHeaders,
        cookieStore: cookieStore ?? this.cookieStore,
        minTlsVersion: minTlsVersion ?? this.minTlsVersion,
        maxTlsVersion: maxTlsVersion ?? this.maxTlsVersion,
      );

  /// Returns a new config with fields overridden by environment variables:
  ///
  /// - `GO_HTTP_CONNECT_TIMEOUT` (seconds)
  /// - `GO_HTTP_SEND_TIMEOUT` (seconds)
  /// - `GO_HTTP_RECEIVE_TIMEOUT` (seconds)
  /// - `GO_HTTP_MAX_REDIRECTS`
  /// - `GO_HTTP_VERIFY` (`"0"` / `"false"` → `false`)
  static ClientConfig mergeEnv([ClientConfig? base]) {
    var c = base ?? defaults;
    final env = Platform.environment;

    final connectStr = env['GO_HTTP_CONNECT_TIMEOUT'];
    if (connectStr != null) {
      final secs = int.tryParse(connectStr);
      if (secs != null && secs > 0) {
        c = c.copyWith(connectTimeout: Duration(seconds: secs));
      }
    }

    final sendStr = env['GO_HTTP_SEND_TIMEOUT'];
    if (sendStr != null) {
      final secs = int.tryParse(sendStr);
      if (secs != null && secs > 0) {
        c = c.copyWith(sendTimeout: Duration(seconds: secs));
      }
    }

    final recvStr = env['GO_HTTP_RECEIVE_TIMEOUT'];
    if (recvStr != null) {
      final secs = int.tryParse(recvStr);
      if (secs != null && secs > 0) {
        c = c.copyWith(receiveTimeout: Duration(seconds: secs));
      }
    }

    final maxR = env['GO_HTTP_MAX_REDIRECTS'];
    if (maxR != null) {
      final n = int.tryParse(maxR);
      if (n != null && n >= 0) {
        c = c.copyWith(maxRedirects: n);
      }
    }

    final verifyStr = env['GO_HTTP_VERIFY'];
    if (verifyStr != null) {
      c = c.copyWith(
          verify: verifyStr == '0' || verifyStr == 'false' ? false : verifyStr,);
    }

    return c;
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
