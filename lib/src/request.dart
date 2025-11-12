import 'package:meta/meta.dart';

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
    this.followRedirects,
    this.maxRedirects,
    this.autoDecompress,
  });

  final Map<String, String>? headers;
  final Map<String, String>? queryParameters;
  final Duration? connectTimeout;
  final Duration? sendTimeout;
  final Duration? receiveTimeout;
  final bool? followRedirects;
  final int? maxRedirects;
  final bool? autoDecompress;

  RequestOptions copyWith({
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
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
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      autoDecompress: autoDecompress ?? this.autoDecompress,
    );
  }
}

/// HTTP request representation
@immutable
class Request {
  const Request({
    required this.method,
    required this.uri,
    Map<String, String>? headers,
    this.body,
    this.options,
  }) : headers = headers ?? const {};

  final HttpMethod method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
  final RequestOptions? options;

  Request copyWith({
    HttpMethod? method,
    Uri? uri,
    Map<String, String>? headers,
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
