import 'package:meta/meta.dart';

import 'headers.dart';
import 'request_trace.dart';
import 'timeout.dart';
import 'url.dart';

/// Sentinel used on per-request options to mean "fall back to the client
/// default" — distinct from an explicit `null`, which means "disable".
///
/// Mirrors `httpx.USE_CLIENT_DEFAULT`.
class UseClientDefault {
  const UseClientDefault._();
  static const instance = UseClientDefault._();
}

/// Shared sentinel instance. Compare with `identical(option, useClientDefault)`.
const useClientDefault = UseClientDefault.instance;

/// HTTP request method
enum HttpMethod {
  get,
  post,
  put,
  delete,
  patch,
  head,
  options,
}

/// Request options for customizing HTTP requests
@immutable
class RequestOptions {
  const RequestOptions({
    this.headers,
    this.queryParameters,
    this.connectTimeout,
    this.sendTimeout,
    this.receiveTimeout,
    this.timeout = useClientDefault,
    this.followRedirects = useClientDefault,
    this.maxRedirects,
    this.autoDecompress,
    this.delay,
    this.maxBytesToRead,
    this.maxBytesToSave,
    this.dialAddress,
    this.sni,
  });

  final Map<String, String>? headers;
  final QueryParams? queryParameters;
  final Duration? connectTimeout;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;

  /// Structured timeout (takes precedence over the individual
  /// [connectTimeout]/[sendTimeout]/[receiveTimeout] fields when set).
  /// Defaults to [useClientDefault] (use the client's timeout).
  final Object? timeout;
  final Object? followRedirects;
  final int? maxRedirects;
  final bool? autoDecompress;

  /// Optional delay to wait before sending the request.
  /// Useful for rate-limiting (polite crawling, avoiding throttling).
  final Duration? delay;

  /// Hard limit on response body bytes. Throws [MaxBytesReadError] if the
  /// decoded response body exceeds this value.
  final int? maxBytesToRead;

  /// Hard limit on response body bytes before saving/spooling. Throws
  /// [MaxBytesReadError] if the decoded body exceeds this value.
  /// ponytail: future versions may spill to a temp file instead of throwing.
  final int? maxBytesToSave;

  /// Override the IP/host:port used for the TCP connection, while keeping the
  /// original [Request.uri] for the `Host` header and TLS SNI. Useful for
  /// vhost-probing, pinned-IP testing, or connecting via a specific IP without
  /// changing the logical request target.
  /// ponytail: dart:io HttpClient does not support custom Dialer integration,
  /// so this works by rewriting the connection URI and restoring the Host
  /// header. TLS SNI still uses the original hostname (dart:io handles this).
  final Uri? dialAddress;

  /// Override the TLS SNI (Server Name Indication) hostname sent during the
  /// TLS handshake, while keeping the original [Request.uri] for the TCP
  /// connection target and `Host` header. Useful for vhost-testing behind
  /// load balancers or CDNs that route by SNI.
  final String? sni;

  RequestOptions copyWith({
    Map<String, String>? headers,
    QueryParams? queryParameters,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    Timeout? timeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    Duration? delay,
    int? maxBytesToRead,
    int? maxBytesToSave,
    Uri? dialAddress,
    String? sni,
  }) {
    return RequestOptions(
      headers: headers ?? this.headers,
      queryParameters: queryParameters ?? this.queryParameters,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      timeout: timeout ?? this.timeout,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      autoDecompress: autoDecompress ?? this.autoDecompress,
      delay: delay ?? this.delay,
      maxBytesToRead: maxBytesToRead ?? this.maxBytesToRead,
      maxBytesToSave: maxBytesToSave ?? this.maxBytesToSave,
      dialAddress: dialAddress ?? this.dialAddress,
      sni: sni ?? this.sni,
    );
  }
}

/// HTTP request representation
@immutable
class Request {
  Request({
    required this.method,
    required this.uri,
    Object? headers,
    this.body,
    this.options,
    this.trace,
  }) : headers = headers is Headers ? headers : Headers(headers);

  final HttpMethod method;
  final Uri uri;
  final Headers headers;
  final Object? body;
  final RequestOptions? options;

  /// Optional trace populated by the transport with phase timestamps.
  final RequestTrace? trace;

  Request copyWith({
    HttpMethod? method,
    Uri? uri,
    Object? headers,
    Object? body,
    RequestOptions? options,
    RequestTrace? trace,
  }) {
    return Request(
      method: method ?? this.method,
      uri: uri ?? this.uri,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      options: options ?? this.options,
      trace: trace ?? this.trace,
    );
  }

  /// Check if the request method is idempotent
  bool get isIdempotent {
    return method == HttpMethod.get ||
        method == HttpMethod.head ||
        method == HttpMethod.options ||
        method == HttpMethod.put ||
        method == HttpMethod.delete;
  }

  /// Convert HttpMethod to string
  String get methodString {
    return method.name.toUpperCase();
  }

  @override
  String toString() {
    final buf = StringBuffer('$methodString $uri');
    if (body != null) {
      buf.write(' [body: ${_describeBody()}]');
    }
    return buf.toString();
  }

  Object _describeBody() {
    if (body is String) {
      final s = body as String;
      if (s.length <= 100) {
        return s;
      }
      return '${s.substring(0, 100)}... (${s.length} chars)';
    }
    if (body is List<int>) {
      final b = body as List<int>;
      return '${b.length} bytes';
    }
    if (body is Stream<List<int>>) {
      return '<stream>';
    }
    return body.runtimeType.toString();
  }
}
