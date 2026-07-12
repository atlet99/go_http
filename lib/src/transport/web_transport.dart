// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

import '../cancel/cancellation_token.dart';
import '../errors.dart';
import '../request.dart';
import '../response.dart' as http_response;
import 'transport.dart';

/// Web-based transport using XMLHttpRequest.
///
/// Note: This transport only works on web platforms. Binary responses are read
/// via `responseType = 'arraybuffer'` so that arbitrary byte data (images,
/// gzipped bodies, etc.) is preserved correctly.
class WebTransport implements Transport {
  @override
  Future<http_response.Response> send(
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

    // XHR exposes a single overall timeout; map it to the receive timeout as
    // the closest semantic equivalent.
    final timeout = receiveTimeout ?? const Duration(seconds: 30);
    final timeoutMs = timeout.inMilliseconds;

    final httpRequest = html.HttpRequest();
    httpRequest.responseType = 'arraybuffer';
    httpRequest.timeout = timeoutMs;

    // Prepare body
    Object? body;
    if (request.body != null) {
      if (request.body is String) {
        body = request.body as String;
      } else if (request.body is Uint8List) {
        body = request.body as Uint8List;
      } else if (request.body is List<int>) {
        body = Uint8List.fromList(request.body as List<int>);
      } else {
        body = request.body.toString();
      }
    }

    // Cancellation listener
    StreamSubscription? cancelSubscription;
    if (cancel != null) {
      cancelSubscription = cancel.stream.listen((_) {
        try {
          httpRequest.abort();
          // ignore: empty_catches
        } catch (_) {}
      });
    }

    try {
      // Open and configure request
      httpRequest
        ..open(request.methodString, request.uri.toString())
        ..setRequestHeader('accept-encoding', 'gzip');

      // Set user headers (skip reserved ones handled by the browser)
      request.headers.forEach((key, value) {
        final lower = key.toLowerCase();
        if (lower == 'content-length' || lower == 'accept-encoding') {
          return;
        }
        try {
          httpRequest.setRequestHeader(key, value);
          // ignore: empty_catches
        } catch (_) {}
      });

      // Progress reporting
      StreamSubscription? progressSub;
      if (onProgress != null) {
        progressSub = httpRequest.onProgress.listen((html.ProgressEvent e) {
          onProgress(e.loaded ?? 0, e.total ?? -1);
        });
      }

      // Race completion against load / timeout / error events
      final completer = Completer<void>();
      StreamSubscription? loadSub;
      StreamSubscription? timeoutSub;
      StreamSubscription? errorSub;
      loadSub = httpRequest.onLoad.listen((_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      timeoutSub = httpRequest.onTimeout.listen((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Request timed out', timeout),
          );
        }
      });
      errorSub = httpRequest.onError.listen((_) {
        if (!completer.isCompleted) {
          completer.completeError(
            NetworkError(
              request: request,
              message: 'Network error: request failed',
            ),
          );
        }
      });

      try {
        // Send the request body (or nothing)
        if (body != null) {
          httpRequest.send(body);
        } else {
          httpRequest.send();
        }

        await completer.future;
      } finally {
        await loadSub.cancel();
        await timeoutSub.cancel();
        await errorSub.cancel();
        await progressSub?.cancel();
      }

      cancel?.throwIfCancelled();

      // Read binary body
      final dynamic raw = httpRequest.response;
      final Uint8List bodyBytes;
      if (raw is ByteBuffer) {
        bodyBytes = Uint8List.view(raw);
      } else if (raw is Uint8List) {
        bodyBytes = raw;
      } else if (raw == null || (httpRequest.status ?? 0) >= 400) {
        bodyBytes = Uint8List(0);
      } else {
        bodyBytes = Uint8List.fromList('$raw'.codeUnits);
      }

      // Parse headers (lowercase keys; keep multi-value set-cookie separate)
      final responseHeaders = <String, String>{};
      final setCookies = <String>[];
      final allHeaders = httpRequest.getAllResponseHeaders();
      if (allHeaders.isNotEmpty) {
        for (final line in allHeaders.split('\r\n')) {
          if (line.isEmpty) {
            continue;
          }
          final idx = line.indexOf(':');
          if (idx <= 0) {
            continue;
          }
          final name = line.substring(0, idx).trim().toLowerCase();
          final value = line.substring(idx + 1).trim();
          if (name == 'set-cookie') {
            setCookies.add(value);
          } else {
            responseHeaders[name] = value;
          }
        }
      }
      if (setCookies.isNotEmpty) {
        responseHeaders['set-cookie'] = setCookies.join('\n');
      }

      return http_response.Response(
        request: request,
        statusCode: httpRequest.status ?? 0,
        headers: responseHeaders,
        data: bodyBytes,
        statusMessage: httpRequest.statusText,
      );
    } on HttpError {
      rethrow;
    } on TimeoutException catch (e) {
      throw TimeoutError(
        request: request,
        timeout: timeout,
        message: 'Request timeout after ${timeout.inSeconds}s',
        originalError: e,
      );
    } on html.DomException catch (e) {
      if (e.name == 'AbortError') {
        throw CancellationError(
          request: request,
          reason: cancel?.reason,
          originalError: e,
        );
      }
      throw NetworkError(
        request: request,
        message: 'Network error: ${e.message}',
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

  @override
  void dispose() {
    // No cleanup needed for web transport
  }
}
