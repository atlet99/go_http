import 'dart:convert';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('GoHttpClient.request', () {
    test('returns the response on success', () async {
      final transport = FakeTransport([
        ok(200, Uint8List.fromList([1, 2])),
      ]);
      final client = GoHttpClient(transport: transport);

      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      expect(res.data, [1, 2]);
      client.dispose();
    });

    test('retries 503 then succeeds within maxAttempts', () async {
      final transport = FakeTransport([
        status(503),
        status(503),
        ok(200),
      ]);
      final client = GoHttpClient(
        transport: transport,
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      expect(transport.callCount, 3);
      client.dispose();
    });

    test('throws HttpStatusError after retries are exhausted', () async {
      final transport = FakeTransport([status(503)]);
      final client = GoHttpClient(
        transport: transport,
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 2,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      await expectLater(
        () => client.get<Uint8List>(Uri.parse('https://x.test')),
        throwsA(isA<HttpStatusError>()),
      );
      client.dispose();
    });

    test('error interceptors run exactly once per attempt', () async {
      final transport = FakeTransport([status(503), status(503), status(503)]);
      final counter = CountingInterceptor();
      final client = GoHttpClient(
        transport: transport,
        interceptors: [counter],
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 2,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      await expectLater(
        () => client.get<Uint8List>(Uri.parse('https://x.test')),
        throwsA(isA<HttpStatusError>()),
      );
      // Each transport send triggers the error path exactly once.
      expect(counter.onErrorCount, transport.callCount);
      client.dispose();
    });

    test('cancellation is not retried and throws CancellationError', () async {
      final token = CancellationToken()..cancel('stop');
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(
        transport: transport,
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 5,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      await expectLater(
        () => client.get<Uint8List>(Uri.parse('https://x.test'), cancel: token),
        throwsA(isA<CancellationError>()),
      );
      expect(transport.callCount, 0);
      client.dispose();
      token.dispose();
    });

    test('network error is retried on idempotent request', () async {
      final transport = FakeTransport([
        networkError(),
        ok(200),
      ]);
      final client = GoHttpClient(
        transport: transport,
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      expect(transport.callCount, 2);
      client.dispose();
    });

    test('POST is not retried even on network error', () async {
      final transport = FakeTransport([networkError(), ok(200)]);
      final client = GoHttpClient(
        transport: transport,
        retryPolicy: DefaultRetryPolicy(
          maxAttempts: 3,
          baseDelay: Duration.zero,
          maxDelay: Duration.zero,
        ),
      );

      await expectLater(
        () => client.post<Uint8List>(Uri.parse('https://x.test')),
        throwsA(isA<NetworkError>()),
      );
      expect(transport.callCount, 1);
      client.dispose();
    });
  });

  group('GoHttpClient decoder', () {
    test('decodes response body via provided Decoder', () async {
      final payload = Uint8List.fromList(utf8.encode('{"hello":"world"}'));
      final transport = FakeTransport([ok(200, payload)]);
      final client = GoHttpClient(transport: transport);

      final res = await client.get<dynamic>(
        Uri.parse('https://x.test'),
        decoder: JsonDecoder(),
      );
      expect((res.data as Map<String, dynamic>)['hello'], 'world');
      client.dispose();
    });
  });

  group('GoHttpClient queryParameters', () {
    test('merges query parameters into the request URI', () async {
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);

      await client.get<Uint8List>(
        Uri.parse('https://x.test/path'),
        options:
            RequestOptions(queryParameters: QueryParams({'a': '1', 'b': '2'})),
      );

      expect(
        transport.sent.single.uri.toString(),
        contains('a=1'),
      );
      expect(transport.sent.single.uri.toString(), contains('b=2'));
      client.dispose();
    });
  });

  group('GoHttpClient auth refresh + retry', () {
    test('refreshes token and retries once on 401', () async {
      var currentToken = 'old';
      final transport = FakeTransport([
        status(401),
        (r) async {
          // On retry the Authorization header must carry the refreshed token.
          expect(r.headers['Authorization'], 'Bearer new');
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
        // Disable retry-policy retries so only the auth retry applies.
        retryPolicy: DefaultRetryPolicy(maxAttempts: 0),
      );

      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      expect(transport.callCount, 2);
      client.dispose();
    });

    test('does not loop forever when the server keeps returning 401', () async {
      final transport = FakeTransport([status(401), status(401)]);
      var refreshCount = 0;
      final client = GoHttpClient(
        transport: transport,
        interceptors: [
          AuthInterceptor(
            tokenProvider: () async => 't',
            tokenRefresher: () async {
              refreshCount++;
              return 't';
            },
          ),
        ],
        retryPolicy: DefaultRetryPolicy(maxAttempts: 0),
      );

      await expectLater(
        () => client.get<Uint8List>(Uri.parse('https://x.test')),
        throwsA(isA<HttpStatusError>()),
      );
      // Initial attempt + one auth retry = 2 transport calls, then it stops.
      expect(transport.callCount, 2);
      // Refresh is bounded (proves the loop terminates).
      expect(refreshCount, lessThanOrEqualTo(2));
      client.dispose();
    });
  });

  group('GoHttpClient buildRequest/send', () {
    test('buildRequest merges default headers and baseUrl', () {
      final client = GoHttpClient(
        transport: FakeTransport([ok(200)]),
        baseUrl: 'https://api.test/v1/',
        defaultHeaders: {'x-default': '1'},
      );
      final req = client.buildRequest(
        Request(method: HttpMethod.get, uri: Uri.parse('users')),
      );
      expect(req.uri.toString(), 'https://api.test/v1/users');
      expect(req.headers['x-default'], '1');
      client.dispose();
    });

    test('send dispatches a mutated prepared request without re-merging',
        () async {
      final transport = FakeTransport([
        ok(200, Uint8List.fromList([9])),
      ]);
      final client = GoHttpClient(transport: transport);
      final prepared = client.buildRequest(
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test')),
      );
      // Escape hatch: mutate after build, send directly.
      prepared.headers.add('x-extra', '1');
      final res = await client.send<Uint8List>(prepared);
      expect(res.statusCode, 200);
      expect(transport.sent.single.headers['x-extra'], '1');
      client.dispose();
    });
  });

  group('GoHttpClient convenience methods', () {
    final cases =
        <String, Future<Response<Uint8List>> Function(GoHttpClient, Uri)>{
      'put': (c, u) => c.put<Uint8List>(u),
      'delete': (c, u) => c.delete<Uint8List>(u),
      'patch': (c, u) => c.patch<Uint8List>(u),
      'head': (c, u) => c.head<Uint8List>(u),
      'options': (c, u) => c.options<Uint8List>(u),
    };

    cases.forEach((name, call) {
      test('$name() sends the correct method', () async {
        final transport = FakeTransport([ok(200)]);
        final client = GoHttpClient(transport: transport);

        await call(client, Uri.parse('https://x.test'));

        expect(transport.sent.single.method.name, name);
        client.dispose();
      });
    });
  });
}
