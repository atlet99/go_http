import 'package:meta/meta.dart';

import 'request.dart';

/// HTTP response representation
@immutable
class Response<T> {
  const Response({
    required this.request,
    required this.statusCode,
    Map<String, String>? headers,
    this.data,
    this.statusMessage,
  }) : headers = headers ?? const {};

  final Request request;
  final int statusCode;
  final Map<String, String> headers;
  final T? data;
  final String? statusMessage;

  /// Check if the response is successful (2xx status code)
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Check if the response is a redirect (3xx status code)
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// Check if the response is a client error (4xx status code)
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// Check if the response is a server error (5xx status code)
  bool get isServerError => statusCode >= 500 && statusCode < 600;

  Response<R> copyWith<R>({
    Request? request,
    int? statusCode,
    Map<String, String>? headers,
    R? data,
    String? statusMessage,
  }) {
    return Response<R>(
      request: request ?? this.request,
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      data: data ?? (this.data as R?),
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}
