import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('ApiResponse', () {
    test('ApiSuccess holds response', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final res = Response(request: req, statusCode: 200);
      final result = ApiSuccess(res);
      expect(result.response.statusCode, 200);
    });

    test('ApiError holds error and exposes statusCode', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final res = Response(request: req, statusCode: 404);
      final error = HttpStatusError(request: req, response: res);
      final result = ApiError(error);
      expect(result.statusCode, 404);
      expect(result.response, same(res));
    });

    test('ApiNetworkError holds RequestError', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final error = NetworkError(request: req, message: 'dns failed');
      final result = ApiNetworkError(error);
      expect(result.error.message, 'dns failed');
    });
  });

  group('requestResult', () {
    test('returns ApiSuccess on 2xx', () async {
      final client = GoHttpClient(
        transport: FakeTransport([
          ok(200, Uint8List.fromList([1, 2, 3])),
        ]),
      );

      final result = await client.requestResult<Uint8List>(
        Request(method: HttpMethod.get, uri: Uri.parse('https://example.com')),
      );

      expect(result, isA<ApiSuccess<Uint8List>>());
      final success = result as ApiSuccess<Uint8List>;
      expect(success.response.statusCode, 200);
    });

    test('returns ApiError on 4xx', () async {
      final client = GoHttpClient(
        transport: FakeTransport([ok(404)]),
      );

      final result = await client.requestResult(
        Request(method: HttpMethod.get, uri: Uri.parse('https://example.com')),
      );

      expect(result, isA<ApiError>());
      final error = result as ApiError;
      expect(error.statusCode, 404);
    });

    test('returns ApiError on 5xx', () async {
      final client = GoHttpClient(
        transport: FakeTransport([ok(500)]),
      );

      final result = await client.requestResult(
        Request(method: HttpMethod.get, uri: Uri.parse('https://example.com')),
      );

      expect(result, isA<ApiError>());
      expect((result as ApiError).statusCode, 500);
    });

    test('returns ApiNetworkError on transport failure', () async {
      final client = GoHttpClient(
        transport: FakeTransport([networkError('connection refused')]),
      );

      final result = await client.requestResult(
        Request(method: HttpMethod.get, uri: Uri.parse('https://example.com')),
      );

      expect(result, isA<ApiNetworkError>());
      expect(
        (result as ApiNetworkError).error.message,
        'connection refused',
      );
    });

    test('exhaustive switch compiles without default', () async {
      final client = GoHttpClient(
        transport: FakeTransport([ok(200)]),
      );

      final result = await client.requestResult(
        Request(method: HttpMethod.get, uri: Uri.parse('https://example.com')),
      );

      // Exhaustive switch — no default needed.
      String label;
      switch (result) {
        case ApiSuccess():
          label = 'success';
        case ApiError():
          label = 'error';
        case ApiNetworkError():
          label = 'network';
      }
      expect(label, 'success');
    });
  });
}
