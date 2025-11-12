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
  }) : _httpClient = httpClient ?? HttpClient()
          ..maxConnectionsPerHost = maxConnectionsPerHost
          ..autoUncompress = true;

  final HttpClient _httpClient;
  final int maxConnectionsPerHost;

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
  }) async {
    cancel?.throwIfCancelled();

    try {
      final ioRequest = await _httpClient.openUrl(
        request.methodString,
        request.uri,
      );

      // Note: HttpClientRequest doesn't support per-request timeouts
      // Timeouts are handled at the HttpClient level or via cancellation

      // Set headers
      request.headers.forEach((key, value) {
        ioRequest.headers.set(key, value);
      });

      // Set body if present
      if (request.body != null) {
        if (request.body is String) {
          ioRequest.write(request.body as String);
        } else if (request.body is List<int>) {
          ioRequest.add(request.body as List<int>);
        } else if (request.body is Uint8List) {
          ioRequest.add(request.body as Uint8List);
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
          ioRequest.abort();
        });
      }

      try {
        final ioResponse = await ioRequest.close();
        cancel?.throwIfCancelled();

        // Read response body
        final bodyBytes = await ioResponse.expand((chunk) => chunk).toList();
        final body = Uint8List.fromList(bodyBytes);

        // Convert headers
        final headers = <String, String>{};
        ioResponse.headers.forEach((key, values) {
          headers[key] = values.join(', ');
        });

        final response = Response(
          request: request,
          statusCode: ioResponse.statusCode,
          headers: headers,
          data: body,
          statusMessage: ioResponse.reasonPhrase,
        );

        return response;
      } finally {
        await cancelSubscription?.cancel();
      }
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
    }
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
  }
}
