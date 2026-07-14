import 'dart:async';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('DelegatingTransport', () {
    test('send delegates to inner transport', () async {
      final inner = MockTransport((req) async {
        return Response(request: req, statusCode: 200);
      });
      final dt = _TestDelegatingTransport(inner);

      await dt.send(
        Request(uri: Uri.parse('https://example.com'), method: HttpMethod.get),
      );

      expect(inner.callCount, 1);
    });

    test('dispose delegates to inner transport', () {
      final inner = _DisposeTrackingTransport();
      final dt = _TestDelegatingTransport(inner);
      dt.dispose();
      expect(inner.disposed, isTrue);
    });

    test('inner is mutable and can be swapped', () async {
      final inner1 = MockTransport((req) async {
        return Response(request: req, statusCode: 200);
      });
      final inner2 = MockTransport((req) async {
        return Response(request: req, statusCode: 200);
      });
      final dt = _TestDelegatingTransport(inner1);

      await dt.send(
        Request(uri: Uri.parse('https://example.com'), method: HttpMethod.get),
      );
      expect(inner1.callCount, 1);
      expect(inner2.callCount, 0);

      dt.inner = inner2;
      await dt.send(
        Request(uri: Uri.parse('https://other.com'), method: HttpMethod.get),
      );
      expect(inner1.callCount, 1);
      expect(inner2.callCount, 1);
    });
  });

  group('RateLimitTransport', () {
    test('calls policy.wait before delegating', () async {
      var innerCalled = false;
      final inner = MockTransport((req) async {
        innerCalled = true;
        return Response(request: req, statusCode: 200);
      });

      final transport = RateLimitTransport(
        inner,
        RateLimitPolicy.global(1000, burst: 5),
      );

      await transport.send(
        Request(uri: Uri.parse('https://example.com'), method: HttpMethod.get),
      );

      expect(innerCalled, isTrue);
    });

    test('rate-limits requests beyond burst capacity', () async {
      final inner = MockTransport((req) async {
        return Response(request: req, statusCode: 200);
      });
      final transport = RateLimitTransport(
        inner,
        RateLimitPolicy.global(1, burst: 1),
      );

      await transport.send(
        Request(uri: Uri.parse('https://example.com'), method: HttpMethod.get),
      );

      var secondDone = false;
      final secondTransport = transport;
      final secondRequest = Request(
        uri: Uri.parse('https://example.com'),
        method: HttpMethod.get,
      );
      unawaited(
        secondTransport.send(secondRequest).then((_) => secondDone = true),
      );

      await Future.microtask(() {});
      expect(secondDone, isFalse);
    });

    test('per-host isolation', () async {
      final inner = MockTransport((req) async {
        return Response(request: req, statusCode: 200);
      });
      final transport = RateLimitTransport(
        inner,
        RateLimitPolicy.perHost(1, burst: 1),
      );

      await transport.send(
        Request(
          uri: Uri.parse('https://a.example.com'),
          method: HttpMethod.get,
        ),
      );

      await transport.send(
        Request(
          uri: Uri.parse('https://b.example.com'),
          method: HttpMethod.get,
        ),
      );

      expect(inner.callCount, 2);
    });

    test('dispose cascades to inner transport', () async {
      final tracking = _DisposeTrackingTransport();
      final transport = RateLimitTransport(
        tracking,
        RateLimitPolicy.global(1000, burst: 5),
      );
      transport.dispose();
      expect(tracking.disposed, isTrue);
    });
  });
}

/// Minimal concrete DelegatingTransport for testing the base class.
class _TestDelegatingTransport extends DelegatingTransport {
  _TestDelegatingTransport(super.inner);
}

/// Wraps a MockTransport to track dispose.
class _DisposeTrackingTransport implements Transport {
  _DisposeTrackingTransport();
  bool disposed = false;

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
    return Response(request: request, statusCode: 200);
  }

  @override
  void dispose() {
    disposed = true;
  }
}
