import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../cancel/cancellation_token.dart';
import '../decoders.dart';
import '../enrichment.dart';
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
    this.tryHttpOnHttpsError = false,
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
  final bool tryHttpOnHttpsError;

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
    final uri = request.uri;
    final connAddr = request.options?.dialAddress;
    final sni = request.options?.sni;
    // SNI customization: substitute host in connection URL so TLS uses the
    // desired hostname; the original Host header is restored below.
    final connUri = sni != null
        ? uri.replace(host: sni)
        : connAddr != null
            ? uri.replace(host: connAddr.host, port: connAddr.port)
            : uri;
    try {
      ioRequest = await _httpClient
          .openUrl(request.methodString, connUri)
          .timeout(connect);
    } on TimeoutException {
      if (connUri.scheme == 'https' && tryHttpOnHttpsError) {
        try {
          ioRequest = await _httpClient
              .openUrl(request.methodString, connUri.replace(scheme: 'http'))
              .timeout(connect);
        } catch (_) {
          throw ConnectTimeoutError(request: request, timeout: connect);
        }
      } else {
        throw ConnectTimeoutError(request: request, timeout: connect);
      }
    } on SocketException catch (e) {
      if (connUri.scheme == 'https' && tryHttpOnHttpsError) {
        try {
          ioRequest = await _httpClient
              .openUrl(request.methodString, connUri.replace(scheme: 'http'))
              .timeout(connect);
        } catch (_) {
          throw ConnectError(
            request: request,
            message: 'Network error: ${e.message}',
            originalError: e,
          );
        }
      } else {
        throw ConnectError(
          request: request,
          message: 'Network error: ${e.message}',
          originalError: e,
        );
      }
    } on HttpException catch (e) {
      if (connUri.scheme == 'https' && tryHttpOnHttpsError) {
        try {
          ioRequest = await _httpClient
              .openUrl(request.methodString, connUri.replace(scheme: 'http'))
              .timeout(connect);
        } catch (_) {
          throw NetworkError(
            request: request,
            message: 'HTTP error: ${e.message}',
            originalError: e,
          );
        }
      } else {
        throw NetworkError(
          request: request,
          message: 'HTTP error: ${e.message}',
          originalError: e,
        );
      }
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

    // If dialAddress or sni was used, restore the original Host header so the
    // server sees the logical request target, not the connection address.
    if (connAddr != null || sni != null) {
      final defaultPort = uri.scheme == 'https' ? 443 : 80;
      final host = uri.port > 0 && uri.port != defaultPort
          ? '${uri.host}:${uri.port}'
          : uri.host;
      ioRequest.headers.set('host', host);
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
      // ponytail: wroteRequest recorded after close, not after the last byte.
      _recordTrace(request, wroteRequest: _traceUs());

      cancel?.throwIfCancelled();

      // Determine expected total length for progress reporting
      final total = int.tryParse(
            ioResponse.headers.value('content-length') ?? '',
          ) ??
          -1;

      // Read response body, reporting progress when requested
      final chunks = <List<int>>[];
      var received = 0;
      var firstByteRecorded = false;
      final bodyIterator = StreamIterator(ioResponse);
      try {
        while (await bodyIterator.moveNext()) {
          final chunk = bodyIterator.current;
          if (!firstByteRecorded) {
            firstByteRecorded = true;
            _recordTrace(request, gotFirstResponseByte: _traceUs());
          }
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

      _recordTrace(request, responseDone: _traceUs());

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
              _decodeWithGzipFallback(body, headers['content-encoding']),
            )
          : body;
      if (shouldDecompress) {
        headers.remove('content-encoding');
      }

      final remoteAddr = ioResponse.connectionInfo?.remoteAddress.address;
      final cert = ioResponse.certificate;
      final tlsInfo = cert != null
          ? TlsInfo(
              serverCertificate: cert.pem,
              subject: cert.subject,
              issuer: cert.issuer,
              fingerprintSha1: cert.sha1
                  .map((b) => b.toRadixString(16).padLeft(2, '0'))
                  .join(':'),
              validFrom: cert.startValidity,
              validTo: cert.endValidity,
            )
          : null;

      return Response(
        request: request,
        statusCode: ioResponse.statusCode,
        headers: headers,
        data: decodedBody,
        statusMessage: ioResponse.reasonPhrase,
        remoteAddress: remoteAddr,
        tlsInfo: tlsInfo,
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

  /// Record phase timestamps into [request.trace], if non-null.
  static void _recordTrace(
    Request request, {
    int? wroteRequest,
    int? gotFirstResponseByte,
    int? responseDone,
  }) {
    final t = request.trace;
    if (t == null) {
      return;
    }
    t.wroteRequest = wroteRequest ?? t.wroteRequest;
    t.gotFirstResponseByte = gotFirstResponseByte ?? t.gotFirstResponseByte;
    t.responseDone = responseDone ?? t.responseDone;
  }

  /// Monotonic microsecond counter for trace timestamps.
  static int _traceUs() => DateTime.now().microsecondsSinceEpoch;

  /// Decode [body] with [encoding], falling back to raw bytes if gzip
  /// decompression fails (server sent `Content-Encoding: gzip` but the body
  /// is not actually gzip-compressed — a real-world bug).
  static List<int> _decodeWithGzipFallback(Uint8List body, String? encoding) {
    try {
      return decodeContentEncoding(body, encoding);
    } on FormatException {
      // ponytail: gzip-fallback — return raw body instead of error.
      return body;
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
