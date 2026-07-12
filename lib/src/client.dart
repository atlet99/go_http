import 'dart:async';

import 'cancel/cancellation_token.dart';
import 'codec/decoder.dart';
import 'cookie/cookie_store.dart';
import 'cookie/memory_cookie_store.dart';
import 'errors.dart';
import 'interceptors/interceptor.dart';
import 'metrics/metrics_sink.dart';
import 'policy/redirect_policy.dart';
import 'policy/retry_policy.dart';
import 'request.dart';
import 'response.dart';
import 'transport/io_transport_stub.dart'
    if (dart.library.io) 'transport/io_transport.dart';
import 'transport/platform_checker_stub.dart'
    if (dart.library.io) 'transport/platform_checker.dart';
import 'transport/transport.dart';
import 'transport/web_transport_stub.dart'
    if (dart.library.html) 'transport/web_transport.dart';

/// Main HTTP client class.
///
/// [GoHttpClient] orchestrates interceptors, retry/redirect policies, cookie
/// storage, timeouts and metrics on top of a pluggable [Transport].
class GoHttpClient {
  GoHttpClient({
    Transport? transport,
    List<Interceptor> interceptors = const [],
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    CookieStore? cookieStore,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool followRedirects = true,
    int maxRedirects = 5,
    bool autoDecompress = true,
    int maxAuthRetries = 1,
    Map<String, String> defaultHeaders = const {
      'accept-encoding': 'gzip, br',
    },
    MetricsSink? metrics,
  })  : _transport = transport ?? _createDefaultTransport(),
        _interceptors = List.from(interceptors),
        _retryPolicy = retryPolicy ?? DefaultRetryPolicy(),
        _redirectPolicy = redirectPolicy ?? DefaultRedirectPolicy(),
        _cookieStore = cookieStore ?? MemoryCookieStore(),
        _connectTimeout = connectTimeout,
        _sendTimeout = sendTimeout,
        _receiveTimeout = receiveTimeout,
        _followRedirects = followRedirects,
        _maxRedirects = maxRedirects,
        _autoDecompress = autoDecompress,
        _maxAuthRetries = maxAuthRetries,
        _defaultHeaders = Map.from(defaultHeaders),
        _metrics = metrics;

  final Transport _transport;
  final List<Interceptor> _interceptors;
  final RetryPolicy? _retryPolicy;
  final RedirectPolicy? _redirectPolicy;
  final CookieStore _cookieStore;
  final Duration _connectTimeout;
  final Duration _sendTimeout;
  final Duration _receiveTimeout;
  final bool _followRedirects;
  final int _maxRedirects;
  final bool _autoDecompress;
  final int _maxAuthRetries;
  final Map<String, String> _defaultHeaders;
  final MetricsSink? _metrics;

  static Transport _createDefaultTransport() {
    if (isIoPlatform) {
      return IoTransport();
    } else {
      return WebTransport();
    }
  }

  /// Send a GET request
  Future<Response<T>> get<T>(
    Uri url, {
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.get,
        uri: url,
        headers: options?.headers ?? const {},
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
      onProgress: onProgress,
    );
  }

  /// Send a POST request
  Future<Response<T>> post<T>(
    Uri url, {
    Object? data,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.post,
        uri: url,
        headers: options?.headers ?? const {},
        body: data,
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
      onProgress: onProgress,
    );
  }

  /// Send a PUT request
  Future<Response<T>> put<T>(
    Uri url, {
    Object? data,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.put,
        uri: url,
        headers: options?.headers ?? const {},
        body: data,
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
      onProgress: onProgress,
    );
  }

  /// Send a DELETE request
  Future<Response<T>> delete<T>(
    Uri url, {
    Object? data,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.delete,
        uri: url,
        headers: options?.headers ?? const {},
        body: data,
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
      onProgress: onProgress,
    );
  }

  /// Send a PATCH request
  Future<Response<T>> patch<T>(
    Uri url, {
    Object? data,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.patch,
        uri: url,
        headers: options?.headers ?? const {},
        body: data,
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
      onProgress: onProgress,
    );
  }

  /// Send a HEAD request
  Future<Response<T>> head<T>(
    Uri url, {
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.head,
        uri: url,
        headers: options?.headers ?? const {},
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
    );
  }

  /// Send an OPTIONS request
  Future<Response<T>> options<T>(
    Uri url, {
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
  }) {
    return request<T>(
      Request(
        method: HttpMethod.options,
        uri: url,
        headers: options?.headers ?? const {},
        options: options,
      ),
      cancel: cancel,
      decoder: decoder,
    );
  }

  /// Send a custom HTTP request.
  ///
  /// Runs request interceptors once, then loops: send → (on error → error
  /// interceptors once → optional auth retry / policy retry) until success or
  /// limits are exhausted. [RetrySignal] returned by an interceptor triggers a
  /// bounded auth-style retry (re-running request interceptors to pick up the
  /// refreshed credentials).
  Future<Response<T>> request<T>(
    Request req, {
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) async {
    var request = req;

    // Merge default headers
    request = request.copyWith(headers: _mergeHeaders(request.headers));

    // Apply query parameters from options
    final queryParams = request.options?.queryParameters;
    if (queryParams != null && queryParams.isNotEmpty) {
      request = _applyQueryParams(request, queryParams);
    }

    // Add cookies
    request = _applyCookies(request);

    // Run request interceptors once
    for (final interceptor in _interceptors) {
      request = await interceptor.onRequest(request);
    }

    // Metrics: request start
    _metrics?.onRequestStart(request);

    var attempt = 0;
    var authRetry = 0;

    while (true) {
      try {
        // Check cancellation up front (caught below → converted to
        // CancellationError, and never retried).
        cancel?.throwIfCancelled();

        var response = await _transport.send(
          request,
          cancel: cancel,
          connectTimeout: request.options?.connectTimeout ?? _connectTimeout,
          sendTimeout: request.options?.sendTimeout ?? _sendTimeout,
          receiveTimeout: request.options?.receiveTimeout ?? _receiveTimeout,
          followRedirects: request.options?.followRedirects ?? _followRedirects,
          maxRedirects: request.options?.maxRedirects ?? _maxRedirects,
          autoDecompress: request.options?.autoDecompress ?? _autoDecompress,
          onProgress: onProgress,
        );

        // Store cookies from response
        _cookieStore.setCookies(response);

        // Treat 4xx/5xx as errors (throws into the catch below, where error
        // interceptors run exactly once).
        if (response.isClientError || response.isServerError) {
          throw HttpResponseError(request: request, response: response);
        }

        // Run response interceptors
        for (final interceptor in _interceptors) {
          response = await interceptor.onResponse(response);
        }

        // Metrics: request end
        _metrics?.onRequestEnd(request, response);

        // Decode if a decoder was provided, otherwise return the raw bytes.
        // Re-wrap in a properly-typed Response<T> (avoids an unsafe cast).
        final decoded =
            decoder != null ? decoder.decode(response.data) : response.data;
        return response.copyWith<T>(data: decoded);
      } catch (e) {
        // Build a typed HttpError
        HttpError error;
        if (e is HttpError) {
          error = e;
        } else if (e is CancellationException) {
          error = CancellationError(
            request: request,
            reason: e.reason,
            originalError: e,
          );
        } else {
          error = NetworkError(
            request: request,
            message: 'Unexpected error: $e',
            originalError: e,
          );
        }

        // Never retry or intercept cancellations
        if (error is CancellationError) {
          _metrics?.onError(error);
          throw error;
        }

        // Run error interceptors exactly once per attempt
        Object result = error;
        for (final interceptor in _interceptors) {
          try {
            result = await interceptor.onError(result as HttpError);
          } on HttpError catch (interceptorError) {
            result = interceptorError;
          }
        }

        // An interceptor may signal that the error was resolved and the
        // request should be retried (e.g. after an auth-token refresh).
        if (result is RetrySignal) {
          if (authRetry < _maxAuthRetries) {
            authRetry++;
            // Re-run request interceptors to pick up the refreshed state
            for (final interceptor in _interceptors) {
              request = await interceptor.onRequest(request);
            }
            continue;
          }
          // Retry budget exhausted: fall through with the original error
          result = error;
        }

        if (result is HttpError) {
          error = result;
        }

        // Retry policy (bounded)
        if (_retryPolicy != null &&
            _retryPolicy!.shouldRetry(request, error, attempt)) {
          attempt++;
          final delay = _retryPolicy!.getDelay(attempt);
          _metrics?.onRetry(request, attempt, delay);
          await Future.delayed(delay);
          continue;
        }

        // Metrics: error
        _metrics?.onError(error);

        // Re-throw error
        throw error;
      }
    }
  }

  Map<String, String> _mergeHeaders(Map<String, String>? customHeaders) {
    final headers = Map<String, String>.from(_defaultHeaders);
    if (customHeaders != null) {
      headers.addAll(customHeaders);
    }
    return headers;
  }

  Request _applyCookies(Request request) {
    final cookies = _cookieStore.getCookies(request.uri);
    if (cookies.isEmpty) {
      return request;
    }
    final headers = Map<String, String>.from(request.headers);
    headers['cookie'] = cookies.join('; ');
    return request.copyWith(headers: headers);
  }

  Request _applyQueryParams(Request request, Map<String, String> params) {
    final uri = request.uri;
    final extra = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final query = uri.query.isEmpty ? extra : '${uri.query}&$extra';
    return request.copyWith(uri: uri.replace(query: query));
  }

  /// Expose the redirect policy (used by tests / advanced configuration)
  RedirectPolicy? get redirectPolicy => _redirectPolicy;

  /// Dispose resources
  void dispose() {
    _transport.dispose();
  }
}
