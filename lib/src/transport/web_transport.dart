import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' hide Headers, Request;

import '../cancel/cancellation_token.dart';
import '../errors.dart';
import '../headers.dart';
import '../request.dart';
import '../response.dart' as http_response;
import 'transport.dart';

/// Web-based transport using XMLHttpRequest.
///
/// Uses `package:web` + `dart:js_interop` instead of `dart:html` to support
/// compilation to WASM.
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
    ProgressCallback? onSendProgress,
  }) async {
    cancel?.throwIfCancelled();

    // XHR exposes a single overall timeout; map it to the receive timeout as
    // the closest semantic equivalent.
    final timeout = receiveTimeout ?? const Duration(seconds: 30);
    final timeoutMs = timeout.inMilliseconds;

    final xhr = XMLHttpRequest();
    xhr.responseType = 'arraybuffer';
    xhr.timeout = timeoutMs;

    // Prepare body
    JSAny? body;
    if (request.body != null) {
      if (request.body is String) {
        body = (request.body as String).toJS;
      } else if (request.body is Uint8List) {
        body = (request.body as Uint8List).toJS;
      } else if (request.body is List<int>) {
        body = Uint8List.fromList(request.body as List<int>).toJS;
      } else {
        body = request.body.toString().toJS;
      }
    }

    // Cancellation listener
    StreamSubscription? cancelSubscription;
    if (cancel != null) {
      cancelSubscription = cancel.stream.listen((_) {
        try {
          xhr.abort();
        } catch (_) {}
      });
    }

    try {
      // Open and configure request
      xhr.open(request.methodString, request.uri.toString());

      // Set user headers
      for (final entry in request.headers.multiItems) {
        final lower = entry.key.toLowerCase();
        if (lower == 'content-length' || lower == 'accept-encoding') {
          continue;
        }
        try {
          xhr.setRequestHeader(entry.key, entry.value);
        } catch (_) {}
      }

      // Download progress
      StreamSubscription? progressSub;
      if (onProgress != null) {
        progressSub = xhr.onProgress.listen((ProgressEvent e) {
          onProgress(e.loaded, e.total < 0 ? -1 : e.total);
        });
      }

      // Upload progress
      if (onSendProgress != null) {
        xhr.upload.onprogress = ((JSAny event) {
          final e = event as ProgressEvent;
          onSendProgress(e.loaded, e.total < 0 ? -1 : e.total);
        }).toJS;
      }

      // Race completion against load / error events
      final completer = Completer<void>();
      StreamSubscription<ProgressEvent>? loadSub;
      StreamSubscription<ProgressEvent>? errorSub;
      loadSub = xhr.onLoad.listen((ProgressEvent e) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });
      errorSub = xhr.onError.listen((ProgressEvent e) {
        if (!completer.isCompleted) {
          // Check if the request was aborted (cancellation)
          if (cancel?.isCancelled ?? false) {
            completer.completeError(
              CancellationError(
                request: request,
                reason: cancel?.reason,
                originalError: null,
              ),
            );
          } else {
            completer.completeError(
              NetworkError(
                request: request,
                message: 'Network error: request failed',
              ),
            );
          }
        }
      });

      try {
        if (body != null) {
          xhr.send(body);
        } else {
          xhr.send();
        }

        await completer.future;
      } finally {
        await loadSub.cancel();
        await errorSub.cancel();
        await progressSub?.cancel();
        xhr.upload.onprogress = null;
      }

      cancel?.throwIfCancelled();

      // Read binary body
      final raw = xhr.response;
      final Uint8List bodyBytes;
      if (raw != null) {
        final arrayBuf = raw as JSArrayBuffer;
        bodyBytes = arrayBuf.toDart.asUint8List();
      } else if (xhr.status >= 400) {
        bodyBytes = Uint8List(0);
      } else {
        bodyBytes = Uint8List(0);
      }

      // Parse headers (lowercase keys; keep multi-value set-cookie separate)
      final responseHeaders = Headers();
      final allHeaders = xhr.getAllResponseHeaders();
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
          responseHeaders.add(name, value);
        }
      }

      return http_response.Response(
        request: request,
        statusCode: xhr.status,
        headers: responseHeaders,
        data: bodyBytes,
        statusMessage: xhr.statusText.isNotEmpty ? xhr.statusText : null,
      );
    } on HttpError {
      rethrow;
    } on CancellationException {
      rethrow;
    } catch (e) {
      throw NetworkError(
        request: request,
        message: 'Network error: ${e.toString()}',
        originalError: e as Object?,
      );
    } finally {
      await cancelSubscription?.cancel();
    }
  }

  @override
  void dispose() {
    // No cleanup needed for web transport
  }
}
