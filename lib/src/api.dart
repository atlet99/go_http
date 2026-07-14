import 'cancel/cancellation_token.dart';
import 'client.dart';
import 'codec/decoder.dart';
import 'request.dart';
import 'response.dart';
import 'transport/transport.dart';

GoHttpClient _defaultClient() {
  // ponytail: single default client; use GoHttpClient() for custom config.
  _default ??= GoHttpClient();
  return _default!;
}

GoHttpClient? _default;

/// Send a GET request.
Future<Response<T>> get<T>(
  Uri url, {
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  ProgressCallback? onSendProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).get<T>(
    url,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
    onSendProgress: onSendProgress,
  );
}

/// Send a POST request.
Future<Response<T>> post<T>(
  Uri url, {
  Object? data,
  Object? json,
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  ProgressCallback? onSendProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).post<T>(
    url,
    data: data,
    json: json,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
    onSendProgress: onSendProgress,
  );
}

/// Send a PUT request.
Future<Response<T>> put<T>(
  Uri url, {
  Object? data,
  Object? json,
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  ProgressCallback? onSendProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).put<T>(
    url,
    data: data,
    json: json,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
    onSendProgress: onSendProgress,
  );
}

/// Send a DELETE request.
Future<Response<T>> delete<T>(
  Uri url, {
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  ProgressCallback? onSendProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).delete<T>(
    url,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
    onSendProgress: onSendProgress,
  );
}

/// Send a PATCH request.
Future<Response<T>> patch<T>(
  Uri url, {
  Object? data,
  Object? json,
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  ProgressCallback? onSendProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).patch<T>(
    url,
    data: data,
    json: json,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
    onSendProgress: onSendProgress,
  );
}

/// Send a HEAD request.
Future<Response<T>> head<T>(
  Uri url, {
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).head<T>(
    url,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
  );
}

/// Send an OPTIONS request.
Future<Response<T>> options<T>(
  Uri url, {
  RequestOptions? options,
  CancellationToken? cancel,
  Decoder<T>? decoder,
  ProgressCallback? onProgress,
  GoHttpClient? client,
}) {
  return (client ?? _defaultClient()).options<T>(
    url,
    options: options,
    cancel: cancel,
    decoder: decoder,
    onProgress: onProgress,
  );
}
