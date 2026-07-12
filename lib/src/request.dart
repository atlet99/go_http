import 'package:meta/meta.dart';

import 'headers.dart';

import 'timeout.dart';

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
    this.timeout,
    this.followRedirects,
    this.maxRedirects,
    this.autoDecompress,
  });

  final Map<String, String>? headers;
  final Map<String, String>? queryParameters;
  final Duration? connectTimeout;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;

  /// Structured timeout (takes precedence over the individual [connectTimeout]/
  /// [sendTimeout]/[receiveTimeout] fields when set).
  final Timeout? timeout;
  final bool? followRedirects;
  final int? maxRedirects;
  final bool? autoDecompress;

  RequestOptions copyWith({
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    Timeout? timeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
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
  }) : headers = headers is Headers ? headers : Headers(headers);

  final HttpMethod method;
  final Uri uri;
  final Headers headers;
  final Object? body;
  final RequestOptions? options;

  Request copyWith({
    HttpMethod? method,
    Uri? uri,
    Object? headers,
    Object? body,
    RequestOptions? options,
  }) {
    return Request(
      method: method ?? this.method,
      uri: uri ?? this.uri,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      options: options ?? this.options,
    );
  }

  /// Check if the request method is idempotent
  bool get isIdempotent {
    return method == HttpMethod.get ||
        method == HttpMethod.head ||
        method == HttpMethod.options;
  }

  /// Convert HttpMethod to string
  String get methodString {
    return method.name.toUpperCase();
  }
}
