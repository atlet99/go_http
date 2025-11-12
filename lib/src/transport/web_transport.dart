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

/// Web-based transport using fetch API
/// Note: This transport only works on web platforms
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
  }) async {
    cancel?.throwIfCancelled();

    try {
      // Prepare headers
      final headers = <String, String>{};
      request.headers.forEach((key, value) {
        headers[key] = value;
      });

      // Prepare body
      Object? body;
      if (request.body != null) {
        if (request.body is String) {
          body = request.body as String;
        } else if (request.body is Uint8List) {
          body = (request.body as Uint8List).buffer.asUint8List();
        } else if (request.body is List<int>) {
          body = Uint8List.fromList(request.body as List<int>);
        } else {
          body = request.body.toString();
        }
      }

      // Use HttpRequest for web transport
      final httpRequest = html.HttpRequest();

      // Set up cancellation listener
      StreamSubscription? cancelSubscription;
      if (cancel != null) {
        cancelSubscription = cancel.stream.listen((_) {
          httpRequest.abort();
        });
      }

      try {
        // Open request
        httpRequest.open(
          request.methodString,
          request.uri.toString(),
        );

        // Set headers
        headers.forEach((key, value) {
          httpRequest.setRequestHeader(key, value);
        });

        // Send request
        if (body != null) {
          httpRequest.send(body);
        } else {
          httpRequest.send();
        }

        // Wait for response
        await httpRequest.onLoad.first;
        cancel?.throwIfCancelled();

        // Read response body
        final responseBody = httpRequest.responseText ?? '';
        final bodyBytes = Uint8List.fromList(responseBody.codeUnits);

        // Convert headers
        final responseHeaders = <String, String>{};
        final allHeaders = httpRequest.getAllResponseHeaders();
        if (allHeaders.isNotEmpty) {
          final headerLines = allHeaders.split('\r\n');
          for (final line in headerLines) {
            if (line.isNotEmpty) {
              final parts = line.split(':');
              if (parts.length >= 2) {
                responseHeaders[parts[0].trim()] =
                    parts.sublist(1).join(':').trim();
              }
            }
          }
        }

        final response = http_response.Response(
          request: request,
          statusCode: httpRequest.status ?? 0,
          headers: responseHeaders,
          data: bodyBytes,
          statusMessage: httpRequest.statusText,
        );

        return response;
      } finally {
        await cancelSubscription?.cancel();
      }
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
    }
  }

  @override
  void dispose() {
    // No cleanup needed for web transport
  }
}
