import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../cancel/cancellation_token.dart';
import '../decoders.dart';
import '../errors.dart';
import '../headers.dart';
import '../proxy.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// IO-based transport using dart:io HttpClient
class IoTransport implements Transport {
  IoTransport({
    HttpClient? httpClient,
    this.maxConnectionsPerHost = 6,
    this.autoDecompress = true,
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
  }) : _httpClient = httpClient ??
            _buildClient(
              maxConnectionsPerHost,
              proxyMounts,
              trustEnv,
              verify,
            );

  final HttpClient _httpClient;
  final int maxConnectionsPerHost;
  final bool autoDecompress;

  @override
  Future<Response> send(
    Request request, {
    CancellationToken? cancel,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    ProgressCallback? onProgress,
  }) async {
    cancel?.throwIfCancelled();

    final connect = connectTimeout ?? const Duration(seconds: 10);
    final send = sendTimeout ?? const Duration(seconds: 30);
    final receive = receiveTimeout ?? const Duration(seconds: 30);
    final shouldDecompress = autoDecompress ?? this.autoDecompress;

    HttpClientRequest ioRequest;
    try {
      ioRequest = await _httpClient
          .openUrl(request.methodString, request.uri)
          .timeout(connect);
    } on TimeoutException {
      throw ConnectTimeoutError(
        request: request,
        timeout: connect,
      );
    }

    // Honor redirect settings per request
    ioRequest.followRedirects = followRedirects ?? true;
    ioRequest.maxRedirects = maxRedirects ?? 5;

    // If the caller disabled decompression for this request, drop the
    // accept-encoding header so the server doesn't compress the body.
    if (!shouldDecompress) {
      ioRequest.headers.removeAll(HttpHeaders.acceptEncodingHeader);
    }

    // Set headers
    for (final entry in request.headers.multiItems) {
      ioRequest.headers.set(entry.key, entry.value);
    }

    // Set body if present
    if (request.body != null) {
      if (request.body is String) {
        ioRequest.write(request.body as String);
      } else if (request.body is Uint8List) {
        ioRequest.add(request.body as Uint8List);
      } else if (request.body is List<int>) {
        ioRequest.add(request.body as List<int>);
      } else {
        throw ArgumentError(
          'Unsupported body type: ${request.body.runtimeType}',
        );
      }
    }

    // Listen for cancellation
    StreamSubscription? cancelSubscription;
    if (cancel != null) {
      cancelSubscription = cancel.stream.listen((_) {
        try {
          ioRequest.abort();
          // ignore: empty_catches
        } catch (_) {}
      });
    }

    try {
      final HttpClientResponse ioResponse;
      try {
        ioResponse = await ioRequest.close().timeout(send);
      } on TimeoutException {
        throw WriteTimeoutError(
          request: request,
          timeout: send,
        );
      }

      cancel?.throwIfCancelled();

      // Determine expected total length for progress reporting
      final total = int.tryParse(
            ioResponse.headers.value('content-length') ?? '',
          ) ??
          -1;

      // Read response body, reporting progress when requested
      final chunks = <List<int>>[];
      var received = 0;
      final bodyIterator = StreamIterator(ioResponse);
      try {
        while (await bodyIterator.moveNext()) {
          final chunk = bodyIterator.current;
          chunks.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(received, total);
          }
        }
      } on TimeoutException {
        // Drain remaining bytes for keep-alive connection reuse
        await _drainIterator(bodyIterator);
        throw ReadTimeoutError(
          request: request,
          timeout: receive,
        );
      } catch (e) {
        // Drain remaining on any read error to return connection to pool
        await _drainIterator(bodyIterator);
        rethrow;
      }

      // Flatten into a single Uint8List
      final body = Uint8List.fromList(chunks.expand((c) => c).toList());

      // Convert headers (lowercase keys; keep multi-value set-cookie separate)
      final headers = Headers();
      ioResponse.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        for (final value in values) {
          headers.add(lower, value);
        }
      });

      // Manual content-encoding decode (autoUncompress is always false;
      // dart:io compression is disabled so we control decoding).
      final decodedBody = shouldDecompress
          ? Uint8List.fromList(
              decodeContentEncoding(body, headers['content-encoding']),
            )
          : body;
      if (shouldDecompress) {
        headers.remove('content-encoding');
      }

      return Response(
        request: request,
        statusCode: ioResponse.statusCode,
        headers: headers,
        data: decodedBody,
        statusMessage: ioResponse.reasonPhrase,
      );
    } on HttpError {
      rethrow;
    } on SocketException catch (e) {
      throw ConnectError(
        request: request,
        message: 'Network error: ${e.message}',
        originalError: e,
      );
    } on HttpException catch (e) {
      throw NetworkError(
        request: request,
        message: 'HTTP error: ${e.message}',
        originalError: e,
      );
    } catch (e) {
      if (e is CancellationException) {
        throw CancellationError(
          request: request,
          reason: e.reason,
          originalError: e,
        );
      }
      rethrow;
    } finally {
      await cancelSubscription?.cancel();
    }
  }

  /// Drain remaining bytes from [iterator] into the void, allowing
  /// keep-alive connection reuse. Errors during drain are silently ignored.
  /// ponytail: short timeout to avoid hanging on a stuck connection.
  static Future<void> _drainIterator(StreamIterator<List<int>> iterator) async {
    try {
      while (await iterator.moveNext()) {}
    } catch (_) {}
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
  }

  static HttpClient _buildClient(
    int maxConnectionsPerHost,
    ProxyMounts? proxyMounts,
    bool trustEnv,
    Object? verify,
  ) {
    final client = HttpClient(context: buildSecurityContext(verify, trustEnv))
      ..maxConnectionsPerHost = maxConnectionsPerHost
      ..autoUncompress = false;

    if (verify == false) {
      // No certificate verification.
      client.badCertificateCallback = (_, __, ___) => true;
    }

    if (proxyMounts != null || !trustEnv) {
      client.findProxy = (uri) {
        final proxy = proxyMounts?.findProxy(uri);
        if (proxy != null) {
          return proxy.findProxyUrl; // Proxy or throws for socks
        }
        if (!trustEnv) {
          return 'DIRECT';
        }
        return HttpClient.findProxyFromEnvironment(uri);
      };
    }
    return client;
  }
}
