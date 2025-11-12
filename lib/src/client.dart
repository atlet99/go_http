import 'dart:async';

import 'cancel/cancellation_token.dart';
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

/// Main HTTP client class
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
  final Map<String, String> _defaultHeaders;
  final MetricsSink? _metrics;

  static Transport _createDefaultTransport() {
    // Use conditional import to determine platform
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
  }) async {
    return request<T>(
      Request(
        method: HttpMethod.get,
        uri: url,
        headers: _mergeHeaders(options?.headers),
        options: options,
      ),
      cancel: cancel,
    );
  }

  /// Send a POST request
  Future<Response<T>> post<T>(
    Uri url, {
    Object? data,
    RequestOptions? options,
    CancellationToken? cancel,
  }) async {
    return request<T>(
      Request(
        method: HttpMethod.post,
        uri: url,
        headers: _mergeHeaders(options?.headers),
        body: data,
        options: options,
      ),
      cancel: cancel,
    );
  }

  /// Send a custom HTTP request
  Future<Response<T>> request<T>(
    Request req, {
    CancellationToken? cancel,
  }) async {
    var request = req;
    var attempt = 0;

    // Apply default headers
    request = request.copyWith(
      headers: _mergeHeaders(request.headers),
    );

    // Add cookies
    final cookies = _cookieStore.getCookies(request.uri);
    if (cookies.isNotEmpty) {
      final headers = Map<String, String>.from(request.headers);
      headers['cookie'] = cookies.join('; ');
      request = request.copyWith(headers: headers);
    }

    // Run request interceptors
    for (final interceptor in _interceptors) {
      request = await interceptor.onRequest(request);
    }

    // Metrics: request start
    _metrics?.onRequestStart(request);

    while (true) {
      attempt++;
      cancel?.throwIfCancelled();

      try {
        // Send request through transport
        var response = await _transport.send(
          request,
          cancel: cancel,
          connectTimeout: request.options?.connectTimeout ?? _connectTimeout,
          sendTimeout: request.options?.sendTimeout ?? _sendTimeout,
          receiveTimeout: request.options?.receiveTimeout ?? _receiveTimeout,
          followRedirects: request.options?.followRedirects ?? _followRedirects,
          maxRedirects: request.options?.maxRedirects ?? _maxRedirects,
          autoDecompress: request.options?.autoDecompress ?? _autoDecompress,
        );

        // Store cookies from response
        _cookieStore.setCookies(response);

        // Check for HTTP error status codes (4xx, 5xx)
        if (response.isClientError || response.isServerError) {
          final httpError = HttpResponseError(
            request: request,
            response: response,
          );

          // Run error interceptors
          for (final interceptor in _interceptors) {
            try {
              final handledError = await interceptor.onError(httpError);
              if (handledError is HttpError) {
                throw handledError;
              }
            } catch (e) {
              if (e is HttpError) {
                rethrow;
              }
            }
          }

          // Check if we should retry
          if (_retryPolicy != null &&
              _retryPolicy!.shouldRetry(request, httpError, attempt)) {
            final delay = _retryPolicy!.getDelay(attempt);
            _metrics?.onRetry(request, attempt, delay);
            await Future.delayed(delay);
            continue;
          }

          // Metrics: error
          _metrics?.onError(httpError);

          // Re-throw error
          throw httpError;
        }

        // Run response interceptors
        for (final interceptor in _interceptors) {
          response = await interceptor.onResponse(response);
        }

        // Metrics: request end
        _metrics?.onRequestEnd(request, response);

        // Handle redirects
        if (response.isRedirect && _followRedirects) {
          final location = response.headers['location'];
          if (location != null) {
            final redirectUri = Uri.parse(location);
            final absoluteUri = request.uri.resolveUri(redirectUri);
            if (_redirectPolicy?.shouldFollowRedirect(
                  request,
                  response,
                  attempt,
                ) ??
                false) {
              request = request.copyWith(uri: absoluteUri);
              continue;
            }
          }
        }

        return response as Response<T>;
      } catch (e) {
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

        // Run error interceptors
        for (final interceptor in _interceptors) {
          try {
            error = await interceptor.onError(error) as HttpError;
          } catch (e) {
            // Interceptor re-threw the error
            if (e is HttpError) {
              error = e;
            }
          }
        }

        // Check if we should retry
        if (_retryPolicy != null &&
            _retryPolicy!.shouldRetry(request, error, attempt)) {
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

  /// Dispose resources
  void dispose() {
    _transport.dispose();
  }
}
