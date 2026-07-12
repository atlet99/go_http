import 'dart:async';

import 'cancel/cancellation_token.dart';
import 'codec/decoder.dart';
import 'cookie/cookie_store.dart';
import 'cookie/memory_cookie_store.dart';
import 'errors.dart';
import 'headers.dart';
import 'interceptors/interceptor.dart';
import 'metrics/metrics_sink.dart';
import 'multipart.dart';
import 'policy/redirect_policy.dart';
import 'policy/retry_policy.dart';
import 'proxy.dart';
import 'request.dart';
import 'response.dart';
import 'timeout.dart';
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
    Timeout? timeout,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration sendTimeout = const Duration(seconds: 30),
    Duration receiveTimeout = const Duration(seconds: 30),
    bool followRedirects = true,
    int maxRedirects = 5,
    bool autoDecompress = true,
    int maxAuthRetries = 1,
    this.baseUrl,
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
    Map<String, String> defaultHeaders = const {
      'accept-encoding': 'gzip, br',
    },
    MetricsSink? metrics,
  })  : _transport = transport ?? _createDefaultTransport(
          proxyMounts: proxyMounts,
          trustEnv: trustEnv,
          verify: verify,
        ),
        _interceptors = List.from(interceptors),
        _retryPolicy = retryPolicy ?? DefaultRetryPolicy(),
        _redirectPolicy = redirectPolicy ?? DefaultRedirectPolicy(),
        _cookieStore = cookieStore ?? MemoryCookieStore(),
        _timeout = timeout,
        _connectTimeout = connectTimeout,
        _sendTimeout = sendTimeout,
        _receiveTimeout = receiveTimeout,
        _followRedirects = followRedirects,
        _maxRedirects = maxRedirects,
        _autoDecompress = autoDecompress,
        _maxAuthRetries = maxAuthRetries,
        _defaultHeaders = Headers(defaultHeaders),
        _metrics = metrics;

  final Transport _transport;
  final List<Interceptor> _interceptors;
  final RetryPolicy? _retryPolicy;
  final RedirectPolicy? _redirectPolicy;
  final CookieStore _cookieStore;
  final Timeout? _timeout;
  final Duration _connectTimeout;
  final Duration _sendTimeout;
  final Duration _receiveTimeout;
  final bool _followRedirects;
  final int _maxRedirects;
  final bool _autoDecompress;
  final int _maxAuthRetries;
  final Headers _defaultHeaders;
  final MetricsSink? _metrics;

  /// Optional base URL; a relative request URI is resolved against it.
  final String? baseUrl;

  static Transport _createDefaultTransport({
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
  }) {
    if (isIoPlatform) {
      return IoTransport(
        proxyMounts: proxyMounts,
        trustEnv: trustEnv,
        verify: verify,
      );
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

  /// Build the fully-prepared [Request] by merging client configuration
  /// (default headers, cookies, query params, base URL) onto [req].
  ///
  /// Mirrors `httpx.Client.buildRequest` — the merge boundary. Callers may
  /// mutate the result before handing it to [send] (escape hatch):
  /// ```dart
  /// final prepared = client.buildRequest(Request.get(uri));
  /// prepared.headers.add('x-custom', '1');
  /// final res = await client.send(prepared);
  /// ```
  Request buildRequest(Request req) {
    var request = req;
    request = request.copyWith(headers: _mergeHeaders(request.headers));
    final queryParams = request.options?.queryParameters;
    if (queryParams != null && queryParams.isNotEmpty) {
      request = _applyQueryParams(request, queryParams);
    }
    request = _applyCookies(request);
    request = _applyBaseUrl(request);
    return request;
  }

  /// Send an already-prepared [Request] (use [buildRequest] to prepare one)
  /// through the transport, running interceptors and retry/redirect policies.
  ///
  /// Unlike [request], [send] does **not** re-merge client config, so it is
  /// safe to call repeatedly on the same prepared request.
  Future<Response<T>> send<T>(
    Request req, {
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) async {
    var request = req;

    // Run request interceptors once per send (re-run on auth retry below).
    for (final interceptor in _interceptors) {
      request = await interceptor.onRequest(request);
    }

    // Serialize a Multipart body to bytes (sets Content-Type if absent).
    if (request.body is Multipart) {
      request = _encodeMultipart(request);
    }

    _metrics?.onRequestStart(request);

    final effectiveTimeout = _resolveTimeout(request.options?.timeout);
    final connectTimeout = effectiveTimeout?.connect ?? _connectTimeout;
    final sendTimeout = effectiveTimeout?.write ?? _sendTimeout;
    final receiveTimeout = effectiveTimeout?.read ?? _receiveTimeout;
    final followRedirects =
        _resolveBool(request.options?.followRedirects, _followRedirects);
    final maxRedirects = request.options?.maxRedirects ?? _maxRedirects;
    final autoDecompress = request.options?.autoDecompress ?? _autoDecompress;

    final stopwatch = Stopwatch()..start();
    var attempt = 0;
    var authRetry = 0;

    while (true) {
      try {
        // Check cancellation up front (caught below → converted to
        // CancellationError, and never retried).
        cancel?.throwIfCancelled();

        final response = await _transport.send(
          request,
          cancel: cancel,
          connectTimeout: connectTimeout,
          sendTimeout: sendTimeout,
          receiveTimeout: receiveTimeout,
          followRedirects: followRedirects,
          maxRedirects: maxRedirects,
          autoDecompress: autoDecompress,
          onProgress: onProgress,
        );

        // Store cookies from response
        _cookieStore.setCookies(response);

        // Treat 4xx/5xx as errors (throws into the catch below, where error
        // interceptors run exactly once).
        if (response.isClientError || response.isServerError) {
          throw HttpStatusError(request: request, response: response);
        }

        // Run response interceptors
        var resp = response;
        for (final interceptor in _interceptors) {
          resp = await interceptor.onResponse(resp);
        }

        // Metrics: request end
        _metrics?.onRequestEnd(request, resp);

        // Decode if a decoder was provided, otherwise return the raw bytes.
        // Re-wrap in a properly-typed Response<T> (avoids an unsafe cast).
        final decoded = decoder != null ? decoder.decode(resp.data) : resp.data;
        return resp.copyWith<T>(
          data: decoded,
          elapsed: stopwatch.elapsed,
        );
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

  /// Send a [Request], first merging it with client configuration.
  ///
  /// Equivalent to `send(buildRequest(req))` — see those for the split.
  Future<Response<T>> request<T>(
    Request req, {
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) =>
      send<T>(
        buildRequest(req),
        cancel: cancel,
        decoder: decoder,
        onProgress: onProgress,
      );

  Timeout? _resolveTimeout(Object? timeout) {
    if (identical(timeout, useClientDefault)) {
      return _timeout;
    }
    if (timeout == null) {
      return const Timeout.disabled();
    }
    return timeout as Timeout;
  }

  bool _resolveBool(Object? value, bool fallback) {
    if (identical(value, useClientDefault)) {
      return fallback;
    }
    return value as bool? ?? fallback;
  }

  Headers _mergeHeaders(Headers customHeaders) {
    final headers = _defaultHeaders.copy();
    for (final entry in customHeaders.multiItems) {
      if (headers.containsKey(entry.key)) {
        headers.remove(entry.key);
      }
      headers.add(entry.key, entry.value);
    }
    return headers;
  }

  Request _applyCookies(Request request) {
    final cookies = _cookieStore.getCookies(request.uri);
    if (cookies.isEmpty) {
      return request;
    }
    final headers = request.headers.copy();
    headers.remove('cookie');
    headers.add('cookie', cookies.join('; '));
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

  Request _applyBaseUrl(Request request) {
    final base = baseUrl;
    if (base == null || base.isEmpty) {
      return request;
    }
    final uri = request.uri;
    if (uri.hasScheme) {
      return request;
    }
    return request.copyWith(uri: Uri.parse(base).resolveUri(uri));
  }

  Request _encodeMultipart(Request request) {
    final mp = request.body as Multipart;
    final headers = request.headers.copy();
    if (headers['content-type'] == null) {
      headers['content-type'] = mp.contentType;
    }
    return request.copyWith(headers: headers, body: mp.render());
  }

  /// Expose the redirect policy (used by tests / advanced configuration)
  RedirectPolicy? get redirectPolicy => _redirectPolicy;

  /// Dispose resources
  void dispose() {
    _transport.dispose();
  }
}
