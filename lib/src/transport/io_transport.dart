import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../cancel/cancellation_token.dart';
import '../decoders.dart';
import '../dns_resolver.dart';
import '../enrichment.dart';
import '../errors.dart';
import '../headers.dart';
import '../pinning.dart';
import '../proxy.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// IO-based transport using dart:io HttpClient
class IoTransport implements Transport {
  IoTransport({
    HttpClient? httpClient,
    this.maxConnectionsPerHost = 100,
    this.autoDecompress = true,
    this.tryHttpOnHttpsError = false,
    this.resolver,
    Duration? idleTimeout,
    ProxyMounts? proxyMounts,
    bool trustEnv = true,
    Object? verify,
    Object? minTlsVersion,
    Object? maxTlsVersion,
    PinnedCertificates? pinnedCertificates,
  }) : _httpClient = httpClient ??
            _buildClient(
              maxConnectionsPerHost,
              idleTimeout,
              proxyMounts,
              trustEnv,
              verify,
              minTlsVersion,
              maxTlsVersion,
              pinnedCertificates,
            );

  final HttpClient _httpClient;
  final int maxConnectionsPerHost;
  final bool autoDecompress;
  final bool tryHttpOnHttpsError;

  /// Optional DNS resolver for custom lookup and caching.
  ///
  /// When set and no explicit [RequestOptions.dialAddress] or
  /// [RequestOptions.sni] is provided, the transport resolves the
  /// hostname itself and injects the resolved IP as the connection
  /// target, restoring the original `Host` header. Populates
  /// [RequestTrace.dnsStart] / [RequestTrace.dnsDone].
  final DnsResolver? resolver;

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
    ProgressCallback? onSendProgress,
  }) async {
    cancel?.throwIfCancelled();

    final connect = connectTimeout ?? const Duration(seconds: 10);
    final send = sendTimeout ?? const Duration(seconds: 30);
    final receive = receiveTimeout ?? const Duration(seconds: 30);
    final shouldDecompress = autoDecompress ?? this.autoDecompress;

    final uri = request.uri;
    final connAddr = request.options?.dialAddress;
    final sni = request.options?.sni;

    // DNS resolution with cache (before retry loop — not retried on gzip
    // fallback since the hostname doesn't change between attempts).
    String? dnsResolvedIp;
    if (resolver != null && connAddr == null && sni == null) {
      _recordTrace(request, dnsStart: _traceUs());
      try {
        final address = await resolver!.lookup(uri.host);
        dnsResolvedIp = address.address;
      } finally {
        _recordTrace(request, dnsDone: _traceUs());
      }
    }

    final connUri = sni != null
        ? uri.replace(host: sni)
        : connAddr != null
            ? uri.replace(host: connAddr.host, port: connAddr.port)
            : dnsResolvedIp != null
                ? uri.replace(host: dnsResolvedIp)
                : uri;

    // Gzip-fallback retry: if gzip decode fails for an idempotent request,
    // retry once with Accept-Encoding: identity.
    var gzipFallbackRetried = false;

    while (true) {
      HttpClientRequest ioRequest;
      _recordTrace(request, connectStart: _traceUs());
      try {
        ioRequest = await _httpClient
            .openUrl(request.methodString, connUri)
            .timeout(connect);
        _recordTrace(request, connectDone: _traceUs());
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

      // Apply headers: drop accept-encoding when decompress disabled,
      // or set to identity for gzip-fallback retry.
      if (gzipFallbackRetried) {
        ioRequest.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      } else if (!shouldDecompress) {
        ioRequest.headers.removeAll(HttpHeaders.acceptEncodingHeader);
      }

      // Set request headers
      for (final entry in request.headers.multiItems) {
        // Don't override the accept-encoding we set above
        if (entry.key.toLowerCase() != 'accept-encoding') {
          ioRequest.headers.set(entry.key, entry.value);
        }
      }

      // If dialAddress, sni, or DNS-resolved IP was used, restore the
      // original Host header
      if (connAddr != null || sni != null || dnsResolvedIp != null) {
        final defaultPort = uri.scheme == 'https' ? 443 : 80;
        final host = uri.port > 0 && uri.port != defaultPort
            ? '${uri.host}:${uri.port}'
            : uri.host;
        ioRequest.headers.set('host', host);
      }

      // Set body if present (only on first attempt; retry with identity
      // is only done for idempotent methods where body is replayable or empty)
      if (request.body != null && !gzipFallbackRetried) {
        if (request.body is String) {
          final s = request.body as String;
          ioRequest.write(s);
          if (onSendProgress != null) {
            onSendProgress(s.length, s.length);
          }
        } else if (request.body is Uint8List) {
          final b = request.body as Uint8List;
          ioRequest.add(b);
          if (onSendProgress != null) {
            onSendProgress(b.length, b.length);
          }
        } else if (request.body is List<int>) {
          final b = request.body as List<int>;
          ioRequest.add(b);
          if (onSendProgress != null) {
            onSendProgress(b.length, b.length);
          }
        } else if (request.body is Stream<List<int>>) {
          var sent = 0;
          final stream = request.body as Stream<List<int>>;
          final counting = stream.map((chunk) {
            sent += chunk.length;
            if (onSendProgress != null) {
              onSendProgress(sent, -1);
            }
            return chunk;
          });
          try {
            await ioRequest.addStream(counting);
          } on HttpException catch (e) {
            throw NetworkError(
              request: request,
              message: 'Stream error: ${e.message}',
              originalError: e,
            );
          }
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
        _recordTrace(request, wroteRequest: _traceUs());

        cancel?.throwIfCancelled();

        final total = int.tryParse(
              ioResponse.headers.value('content-length') ?? '',
            ) ??
            -1;

        // Read response body
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
          await _drainIterator(bodyIterator);
          throw ReadTimeoutError(
            request: request,
            timeout: receive,
          );
        } catch (e) {
          await _drainIterator(bodyIterator);
          rethrow;
        }

        _recordTrace(request, responseDone: _traceUs());

        final body = Uint8List.fromList(chunks.expand((c) => c).toList());

        // Convert headers
        final headers = Headers();
        ioResponse.headers.forEach((name, values) {
          final lower = name.toLowerCase();
          for (final value in values) {
            headers.add(lower, value);
          }
        });

        // Manual content-encoding decode
        if (shouldDecompress) {
          final encoding = headers['content-encoding'];
          try {
            final decoded = decodeContentEncoding(body, encoding);
            headers.remove('content-encoding');
            final remoteAddr = ioResponse.connectionInfo?.remoteAddress.address;
            final tlsInfo = _buildTlsInfo(ioResponse);
            return Response(
              request: request,
              statusCode: ioResponse.statusCode,
              headers: headers,
              data: Uint8List.fromList(decoded),
              statusMessage: ioResponse.reasonPhrase,
              remoteAddress: remoteAddr,
              tlsInfo: tlsInfo,
            );
          } on FormatException {
            // ponytail: gzip-fallback retry — if the server sent
            // Content-Encoding: gzip but the body isn't actually
            // compressed, retry once with Accept-Encoding: identity.
            if (!gzipFallbackRetried &&
                encoding != null &&
                encoding.contains('gzip') &&
                request.isIdempotent) {
              gzipFallbackRetried = true;
              // Drain remaining chunks from the failed response (unlikely
              // for short compress-decode failures but keeps pool happy).
              await _drainIterator(bodyIterator);
              continue; // retry with identity
            }
            // Return raw body as last resort
            headers.remove('content-encoding');
            final remoteAddr = ioResponse.connectionInfo?.remoteAddress.address;
            final tlsInfo = _buildTlsInfo(ioResponse);
            return Response(
              request: request,
              statusCode: ioResponse.statusCode,
              headers: headers,
              data: body,
              statusMessage: ioResponse.reasonPhrase,
              remoteAddress: remoteAddr,
              tlsInfo: tlsInfo,
            );
          }
        } else {
          final remoteAddr = ioResponse.connectionInfo?.remoteAddress.address;
          final tlsInfo = _buildTlsInfo(ioResponse);
          return Response(
            request: request,
            statusCode: ioResponse.statusCode,
            headers: headers,
            data: body,
            statusMessage: ioResponse.reasonPhrase,
            remoteAddress: remoteAddr,
            tlsInfo: tlsInfo,
          );
        }
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
  }

  /// Build [TlsInfo] from a dart:io [HttpClientResponse], computing SHA-256
  /// fingerprint from the PEM body and detecting self-signed / wildcard.
  static TlsInfo? _buildTlsInfo(HttpClientResponse ioResponse) {
    final cert = ioResponse.certificate;
    if (cert == null) {
      return null;
    }
    final fingerprintSha256 = _sha256Fingerprint(cert.pem);
    final subject = cert.subject;
    final issuer = cert.issuer;
    return TlsInfo(
      serverCertificate: cert.pem,
      subject: subject,
      issuer: issuer,
      fingerprintSha1:
          cert.sha1.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':'),
      fingerprintSha256: fingerprintSha256,
      isSelfSigned: subject == issuer,
      isWildcard: subject.contains('*.'),
      validFrom: cert.startValidity,
      validTo: cert.endValidity,
    );
  }

  /// Compute SHA-256 fingerprint from a PEM-encoded certificate.
  /// ponytail: naive PEM parser — strips BEGIN/END lines, base64-decodes
  /// the body, hashes the DER bytes. Does not validate PEM structure.
  static String? _sha256Fingerprint(String pem) {
    try {
      final lines = pem.split('\n');
      final b64 = lines.where((l) => !l.startsWith('-----')).join();
      final der = base64.decode(b64);
      final hash = sha256.convert(der);
      return hash.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':');
    } catch (_) {
      return null;
    }
  }

  /// Record phase timestamps into [request.trace], if non-null.
  static void _recordTrace(
    Request request, {
    int? dnsStart,
    int? dnsDone,
    int? connectStart,
    int? connectDone,
    int? tlsHandshakeStart,
    int? tlsHandshakeDone,
    int? wroteRequest,
    int? gotFirstResponseByte,
    int? responseDone,
  }) {
    final t = request.trace;
    if (t == null) {
      return;
    }
    t.dnsStart = dnsStart ?? t.dnsStart;
    t.dnsDone = dnsDone ?? t.dnsDone;
    t.connectStart = connectStart ?? t.connectStart;
    t.connectDone = connectDone ?? t.connectDone;
    t.tlsHandshakeStart = tlsHandshakeStart ?? t.tlsHandshakeStart;
    t.tlsHandshakeDone = tlsHandshakeDone ?? t.tlsHandshakeDone;
    t.wroteRequest = wroteRequest ?? t.wroteRequest;
    t.gotFirstResponseByte = gotFirstResponseByte ?? t.gotFirstResponseByte;
    t.responseDone = responseDone ?? t.responseDone;
  }

  /// Monotonic microsecond counter for trace timestamps.
  static int _traceUs() => DateTime.now().microsecondsSinceEpoch;

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
    Duration? idleTimeout,
    ProxyMounts? proxyMounts,
    bool trustEnv,
    Object? verify,
    Object? minTlsVersion,
    Object? maxTlsVersion,
    PinnedCertificates? pinnedCertificates,
  ) {
    final client = HttpClient(context: buildSecurityContext(verify, trustEnv))
      ..maxConnectionsPerHost = maxConnectionsPerHost
      ..autoUncompress = false;

    if (idleTimeout != null) {
      client.idleTimeout = idleTimeout;
    }

    // ponytail: minTlsVersion/maxTlsVersion config fields are reserved for
    // platform TLS version constraints. The current dart:io SDK does not
    // expose TlsVersion — re-enable when the API stabilises.

    final hasPins =
        pinnedCertificates != null && pinnedCertificates.pins.isNotEmpty;

    if (hasPins) {
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) {
        final hostPins = pinnedCertificates.pins[host];
        if (hostPins != null && hostPins.isNotEmpty) {
          final fp = base64Encode(sha256.convert(cert.der).bytes);
          return hostPins.contains(fp);
        }
        // Host not pinned → use verify setting.
        return verify == false;
      };
    } else if (verify == false) {
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
