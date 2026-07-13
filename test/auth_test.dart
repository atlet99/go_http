import 'dart:convert' show base64, utf8;
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('Auth strategies', () {
    test('BasicAuth sets a Basic Authorization header', () {
      final req = BasicAuth('user', 'pass').apply(
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/')),
      );
      expect(
        req.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('user:pass'))}',
      );
    });

    test('FunctionAuth applies a custom transform', () {
      final req = FunctionAuth(
        (r) => r.copyWith(
          headers: r.headers.copy()..['x-token'] = 'abc',
        ),
      ).apply(
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/')),
      );
      expect(req.headers['x-token'], 'abc');
    });

    test('DigestAuth.buildHeader parses challenge and emits Digest', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://x.test/path'),
      );
      final header = DigestAuth('user', 'pass').buildHeader(
        req,
        'Digest realm="test", nonce="abc123", qop="auth", opaque="opq"',
      );
      expect(header, startsWith('Digest '));
      expect(header, contains('username="user"'));
      expect(header, contains('realm="test"'));
      expect(
        header,
        contains('nonce="abc123"'),
      );
      expect(header, contains('uri="/path"'));
      expect(header, contains('qop=auth'));
      expect(header, contains('opaque="opq"'));
      expect(header, contains('response="'));
    });
  });

  group('AuthInterceptor', () {
    test('DigestAuth completes the 401 challenge and retries once', () async {
      final transport = FakeTransport([
        (r) async => Response(
              request: r,
              statusCode: 401,
              headers: {
                'www-authenticate':
                    'Digest realm="test", nonce="abc123", qop="auth"',
              },
              data: Uint8List(0),
            ),
        (r) async {
          expect(r.headers['authorization'], startsWith('Digest '));
          expect(r.headers['authorization'], contains('username="user"'));
          expect(r.headers['authorization'], contains('nonce="abc123"'));
          return ok(200)(r);
        },
      ]);
      final client = GoHttpClient(
        transport: transport,
        interceptors: [AuthInterceptor(auth: DigestAuth('user', 'pass'))],
        retryPolicy: DefaultRetryPolicy(maxAttempts: 0),
      );

      final res = await client.get<Uint8List>(Uri.parse('https://x.test/path'));
      expect(res.statusCode, 200);
      expect(transport.callCount, 2);
      client.dispose();
    });

    test('legacy Bearer tokenProvider/tokenRefresher still works', () async {
      var currentToken = 'old';
      final transport = FakeTransport([
        status(401),
        (r) async {
          expect(r.headers['authorization'], 'Bearer new');
          return ok(200)(r);
        },
      ]);
      final client = GoHttpClient(
        transport: transport,
        interceptors: [
          AuthInterceptor(
            tokenProvider: () async => currentToken,
            tokenRefresher: () async {
              currentToken = 'new';
              return currentToken;
            },
          ),
        ],
        retryPolicy: DefaultRetryPolicy(maxAttempts: 0),
      );

      final res = await client.get<Uint8List>(Uri.parse('https://x.test/'));
      expect(res.statusCode, 200);
      client.dispose();
    });
  });
}
