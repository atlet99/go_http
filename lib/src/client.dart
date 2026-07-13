import 'dart:async';
import 'dart:typed_data';

import 'body_encoding.dart';
import 'cancel/cancellation_token.dart';
import 'codec/decoder.dart';
import 'config.dart';
import 'cookie/cookie_store.dart';
import 'cookie/memory_cookie_store.dart';
import 'enrichment.dart';
import 'errors.dart';
import 'event_hooks.dart';
import 'headers.dart';
import 'interceptors/interceptor.dart';
import 'limits.dart';
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
import 'url.dart';

/// Main HTTP client class.
///
/// [GoHttpClient] orchestrates interceptors, retry/redirect policies, cookie
/// storage, timeouts and metrics on top of a pluggable [Transport].
class GoHttpClient {
  GoHttpClient({
    ClientConfig? clientConfig,
    ExecutorConfig? executorConfig,
    Transport? transport,
    List<Interceptor> interceptors = const [],
    RetryPolicy? retryPolicy,
    RedirectPolicy? redirectPolicy,
    CookieStore? cookieStore,
    Timeout? timeout,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    int? maxAuthRetries,
    this.baseUrl,
    ProxyMounts? proxyMounts,
    bool? trustEnv,
    Object? verify,
    Map<String, String>? defaultHeaders,
    MetricsSink? metrics,
    EventHooks? eventHooks,
  })  : _transport = transport ??
            clientConfig?.transport ??
            _createDefaultTransport(
              proxyMounts: proxyMounts ?? clientConfig?.proxyMounts,
              trustEnv: trustEnv ?? clientConfig?.trustEnv ?? true,
              verify: verify ?? clientConfig?.verify,
              minTlsVersion: clientConfig?.minTlsVersion,
              maxTlsVersion: clientConfig?.maxTlsVersion,
              limits: clientConfig?.limits,
            ),
        _interceptors = List.from(
          interceptors.isNotEmpty
              ? interceptors
              : executorConfig?.interceptors ?? const [],
        ),
        _retryPolicy =
            retryPolicy ?? clientConfig?.retryPolicy ?? DefaultRetryPolicy(),
        _redirectPolicy = redirectPolicy ??
            clientConfig?.redirectPolicy ??
            DefaultRedirectPolicy(),
        _cookieStore =
            cookieStore ?? clientConfig?.cookieStore ?? MemoryCookieStore(),
        _timeout = timeout ?? clientConfig?.timeout,
        _connectTimeout = connectTimeout ??
            clientConfig?.connectTimeout ??
            const Duration(seconds: 10),
        _sendTimeout = sendTimeout ??
            clientConfig?.sendTimeout ??
            const Duration(seconds: 30),
        _receiveTimeout = receiveTimeout ??
            clientConfig?.receiveTimeout ??
            const Duration(seconds: 30),
        _followRedirects =
            followRedirects ?? clientConfig?.followRedirects ?? true,
        _maxRedirects = maxRedirects ?? clientConfig?.maxRedirects ?? 5,
        _autoDecompress =
            autoDecompress ?? clientConfig?.autoDecompress ?? true,
        _maxAuthRetries = maxAuthRetries ?? clientConfig?.maxAuthRetries ?? 1,
        _defaultHeaders = Headers(
          defaultHeaders ??
              clientConfig?.defaultHeaders ??
              const {'accept-encoding': 'gzip, deflate, br'},
        ),
        _metrics = metrics ?? executorConfig?.metrics,
        _eventHooks = eventHooks ?? executorConfig?.eventHooks,
        _enrichers = executorConfig?.enrichers ?? const [];

  /// Default configuration preset — explicit constructor defaults as a
  /// factory, useful for JSON/YAML deserialization and env-merge patterns.
  static GoHttpClient defaults() =>
      GoHttpClient(clientConfig: ClientConfig.defaults);

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
  EventHooks? _eventHooks;
  final List<ResponseEnricher> _enrichers;

  int _inFlight = 0;
  bool _isShuttingDown = false;
  Completer<void>? _shutdownCompleter;

  /// Hot-swappable request/response callbacks (see [EventHooks]).
  set eventHooks(EventHooks? hooks) => _eventHooks = hooks;

  /// Optional base URL; a relative request URI is resolved against it.
  final String? baseUrl;

  static Transport _createDefaultTransport({
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
    Object? minTlsVersion,
    Object? maxTlsVersion,
    Limits? limits,
  }) {
    if (isIoPlatform) {
      return IoTransport(
        proxyMounts: proxyMounts,
        trustEnv: trustEnv,
        verify: verify,
        minTlsVersion: minTlsVersion,
        maxTlsVersion: maxTlsVersion,
        maxConnectionsPerHost: limits?.maxConnections ?? 100,
        idleTimeout: limits?.keepaliveExpiry,
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
    Object? json,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    final enc = encodeRequest(
      data: data,
      json: json,
      headers: Headers(options?.headers ?? const {}),
    );
    return request<T>(
      Request(
        method: HttpMethod.post,
        uri: url,
        headers: enc.headers.toMap(),
        body: enc.body,
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
    Object? json,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    final enc = encodeRequest(
      data: data,
      json: json,
      headers: Headers(options?.headers ?? const {}),
    );
    return request<T>(
      Request(
        method: HttpMethod.put,
        uri: url,
        headers: enc.headers.toMap(),
        body: enc.body,
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
    Object? json,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    final enc = encodeRequest(
      data: data,
      json: json,
      headers: Headers(options?.headers ?? const {}),
    );
    return request<T>(
      Request(
        method: HttpMethod.delete,
        uri: url,
        headers: enc.headers.toMap(),
        body: enc.body,
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
    Object? json,
    RequestOptions? options,
    CancellationToken? cancel,
    Decoder<T>? decoder,
    ProgressCallback? onProgress,
  }) {
    final enc = encodeRequest(
      data: data,
      json: json,
      headers: Headers(options?.headers ?? const {}),
    );
    return request<T>(
      Request(
        method: HttpMethod.patch,
        uri: url,
        headers: enc.headers.toMap(),
        body: enc.body,
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
    if (_isShuttingDown) {
      throw ClientShutdownError(request: req);
    }
    _inFlight++;
    try {
      return await _sendWithRetry<T>(
        req,
        cancel: cancel,
        decoder: decoder,
        onProgress: onProgress,
      );
    } finally {
      _inFlight--;
      if (_isShuttingDown && _inFlight == 0) {
        _shutdownCompleter?.complete();
      }
    }
  }

  Future<Response<T>> _sendWithRetry<T>(
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

        for (final hook in _eventHooks?.request ?? const []) {
          hook(request);
        }

        // Per-request delay (rate-limiting / polite crawling)
        final reqDelay = request.options?.delay;
        if (reqDelay != null && reqDelay > Duration.zero) {
          await Future.delayed(reqDelay);
        }

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

        for (final hook in _eventHooks?.response ?? const []) {
          hook(resp);
        }

        // Metrics: request end
        _metrics?.onRequestEnd(request, resp);

        // Enforce byte limits (check raw bytes before application-level decode)
        final rawBytes = resp.data;
        if (rawBytes != null && rawBytes is Uint8List) {
          final len = rawBytes.length;
          final maxRead = request.options?.maxBytesToRead;
          if (maxRead != null && len > maxRead) {
            throw MaxBytesReadError(
              request: request,
              maxBytes: maxRead,
              actualBytes: len,
            );
          }
          final maxSave = request.options?.maxBytesToSave;
          if (maxSave != null && len > maxSave) {
            throw MaxBytesReadError(
              request: request,
              maxBytes: maxSave,
              actualBytes: len,
            );
          }
        }

        // Compute follow-up request for redirects when auto-follow is off
        final nextReq = resp.hasRedirectLocation
            ? _buildRedirectRequest(request, resp)
            : null;

        // Count downloaded bytes from the raw response body
        final rawData = resp.data;
        final bytesCount = rawData is Uint8List
            ? rawData.length
            : rawData is List<int>
                ? rawData.length
                : 0;

        // Decode if a decoder was provided, otherwise return the raw bytes.
        // Re-wrap in a properly-typed Response<T> (avoids an unsafe cast).
        final decoded = decoder != null ? decoder.decode(resp.data) : resp.data;
        final enrichment = await _buildEnrichment(request, resp);
        return resp.copyWith<T>(
          data: decoded,
          elapsed: stopwatch.elapsed,
          enrichment: enrichment,
          numBytesDownloaded: bytesCount,
          nextRequest: nextReq,
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

  Request _applyQueryParams(Request request, QueryParams params) {
    final uri = request.uri;
    final extra = params.toQueryString();
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

  /// Build enrichment data after a response is received.
  Future<ResponseEnrichment> _buildEnrichment(
    Request req,
    Response resp,
  ) async {
    Map<String, dynamic>? extra;
    if (_enrichers.isNotEmpty) {
      extra = {};
      for (final enricher in _enrichers) {
        final values = await enricher.enrich(resp);
        extra.addAll(values);
      }
      if (extra.isEmpty) {
        extra = null;
      }
    }
    return ResponseEnrichment(
      trace: req.trace,
      remoteAddress: resp.remoteAddress,
      tlsInfo: resp.tlsInfo,
      extra: extra,
    );
  }

  /// Build the next request for a redirect response.
  Request? _buildRedirectRequest(Request originalRequest, Response response) {
    final location = response.headers['location'];
    if (location == null || location.isEmpty) {
      return null;
    }
    final redirectUri = originalRequest.uri.resolve(location);
    return originalRequest.copyWith(uri: redirectUri, body: null);
  }

  /// Expose the redirect policy (used by tests / advanced configuration)
  RedirectPolicy? get redirectPolicy => _redirectPolicy;

  /// Validate client configuration. Returns a list of problems found;
  /// empty list means the configuration is valid.
  /// ponytail: basic checks — add more as needed.
  List<ValidationError> validate() {
    final errors = <ValidationError>[];
    if (_connectTimeout <= Duration.zero) {
      errors.add(const ValidationError('connectTimeout', 'must be positive'));
    }
    if (_sendTimeout <= Duration.zero) {
      errors.add(const ValidationError('sendTimeout', 'must be positive'));
    }
    if (_receiveTimeout <= Duration.zero) {
      errors.add(const ValidationError('receiveTimeout', 'must be positive'));
    }
    if (_maxRedirects < 0) {
      errors.add(const ValidationError('maxRedirects', 'must be non-negative'));
    }
    if (_maxAuthRetries < 0) {
      errors
          .add(const ValidationError('maxAuthRetries', 'must be non-negative'));
    }
    return errors;
  }

  /// Soft shutdown: stop accepting new requests, wait for in-flight to finish.
  /// Returns a future that completes once all active requests complete.
  Future<void> shutdown() async {
    _isShuttingDown = true;
    if (_inFlight == 0) {
      return;
    }
    _shutdownCompleter ??= Completer<void>();
    return _shutdownCompleter!.future;
  }

  /// Hard dispose: force-close transport and all in-flight connections.
  void dispose() {
    _isShuttingDown = true;
    _transport.dispose();
    _shutdownCompleter?.complete();
    _shutdownCompleter = null;
  }
}
