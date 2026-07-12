import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../cancel/cancellation_token.dart';
import '../errors.dart';
import '../request.dart';
import '../response.dart';
import 'transport.dart';

/// IO-based transport using dart:io HttpClient
class IoTransport implements Transport {
  IoTransport({
    HttpClient? httpClient,
    this.maxConnectionsPerHost = 6,
    this.autoDecompress = true,
  }) : _httpClient = httpClient ??
            (HttpClient()
              ..maxConnectionsPerHost = maxConnectionsPerHost
              ..autoUncompress = autoDecompress);

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
      throw TimeoutError(
        request: request,
        timeout: connect,
        message: 'Connection timeout after ${connect.inSeconds}s',
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
    request.headers.forEach((key, value) {
      ioRequest.headers.set(key, value);
    });

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
        throw TimeoutError(
          request: request,
          timeout: send,
          message: 'Send timeout after ${send.inSeconds}s',
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
      try {
        await for (final chunk in ioResponse) {
          chunks.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            onProgress(received, total);
          }
        }
      } on TimeoutException {
        throw TimeoutError(
          request: request,
          timeout: receive,
          message: 'Receive timeout after ${receive.inSeconds}s',
        );
      }

      // Flatten into a single Uint8List
      final body = Uint8List.fromList(chunks.expand((c) => c).toList());

      // Convert headers (lowercase keys; keep multi-value set-cookie separate)
      final headers = <String, String>{};
      final setCookies = <String>[];
      ioResponse.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower == 'set-cookie') {
          setCookies.addAll(values);
        } else {
          headers[lower] = values.join(', ');
        }
      });
      if (setCookies.isNotEmpty) {
        headers['set-cookie'] = setCookies.join('\n');
      }

      return Response(
        request: request,
        statusCode: ioResponse.statusCode,
        headers: headers,
        data: body,
        statusMessage: ioResponse.reasonPhrase,
      );
    } on HttpError {
      rethrow;
    } on SocketException catch (e) {
      throw NetworkError(
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

  @override
  void dispose() {
    _httpClient.close(force: true);
  }
}
