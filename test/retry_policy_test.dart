import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('RetryPolicy presets', () {
    test('scanning() fails fast with 1 retry and short backoff', () {
      final policy = RetryPolicy.scanning();
      expect(policy.getDelay(0).inMilliseconds, lessThanOrEqualTo(100));
      expect(policy.getDelay(1).inMilliseconds, lessThanOrEqualTo(250));
    });

    test('single() retries 5xx and 429', () {
      final policy = RetryPolicy.single();
      final getReq = Request(method: HttpMethod.get, uri: Uri.parse('https://x.test'));

      expect(
        policy.shouldRetry(
          getReq,
          HttpStatusError(
            request: Request(
              method: HttpMethod.get,
              uri: Uri.parse('https://x.test'),
            ),
            response: Response(request: getReq, statusCode: 500),
          ),
          0,
        ),
        isTrue,
      );

      expect(
        policy.shouldRetry(
          getReq,
          HttpStatusError(
            request: Request(
              method: HttpMethod.get,
              uri: Uri.parse('https://x.test'),
            ),
            response: Response(request: getReq, statusCode: 400),
          ),
          0,
        ),
        isFalse,
      );
    });

    test('single() stops after max attempts', () {
      final policy = RetryPolicy.single();
      final req = Request(method: HttpMethod.get, uri: Uri.parse('https://x.test'));
      expect(policy.shouldRetry(req, NetworkError(message: 'test', request: req), 4), isTrue);
      expect(policy.shouldRetry(req, NetworkError(message: 'test', request: req), 5), isFalse);
    });
  });
  late Request getRequest;

  setUp(() {
    getRequest = Request(
      method: HttpMethod.get,
      uri: Uri.parse('https://example.com/x'),
    );
  });

  group('DefaultRetryPolicy.shouldRetry', () {
    test('retries NetworkError on idempotent methods', () {
      final policy = DefaultRetryPolicy();
      expect(
        policy.shouldRetry(
          getRequest,
          NetworkError(request: getRequest, message: 'e'),
          0,
        ),
        isTrue,
      );
    });

    test('does not retry on non-idempotent methods (POST)', () {
      final policy = DefaultRetryPolicy();
      final post = Request(
        method: HttpMethod.post,
        uri: Uri.parse('https://example.com/x'),
      );
      expect(
        policy.shouldRetry(
          post,
          NetworkError(request: post, message: 'e'),
          0,
        ),
        isFalse,
      );
    });

    test('retries on 429/503/504 but not on 500/400', () {
      final policy = DefaultRetryPolicy();

      bool retryForStatus(int code) {
        final resp = Response(
          request: getRequest,
          statusCode: code,
          headers: const {},
          data: null,
        );
        return policy.shouldRetry(
          getRequest,
          HttpStatusError(request: getRequest, response: resp),
          0,
        );
      }

      expect(retryForStatus(429), isTrue);
      expect(retryForStatus(503), isTrue);
      expect(retryForStatus(504), isTrue);
      expect(retryForStatus(500), isFalse);
      expect(retryForStatus(400), isFalse);
      expect(retryForStatus(404), isFalse);
    });

    test('stops after maxAttempts', () {
      final policy = DefaultRetryPolicy(maxAttempts: 3);
      final err = NetworkError(request: getRequest, message: 'e');
      expect(policy.shouldRetry(getRequest, err, 0), isTrue);
      expect(policy.shouldRetry(getRequest, err, 2), isTrue);
      expect(policy.shouldRetry(getRequest, err, 3), isFalse);
    });

    test('never retries CancellationError', () {
      final policy = DefaultRetryPolicy();
      final err = CancellationError(request: getRequest, reason: 'stop');
      expect(policy.shouldRetry(getRequest, err, 0), isFalse);
    });
  });

  group('DefaultRetryPolicy.getDelay (equal jitter)', () {
    test('delay stays within [temp/2, temp] bounds', () {
      final policy = DefaultRetryPolicy(
        baseDelay: const Duration(milliseconds: 300),
        maxDelay: const Duration(milliseconds: 2000),
      );

      // Run several times to exercise the random component.
      for (var i = 0; i < 50; i++) {
        for (final attempt in [1, 2, 3]) {
          final delay = policy.getDelay(attempt);
          // temp = min(maxDelay, baseDelay * 2^attempt)
          final tempMs = (300 * (1 << attempt)).clamp(0, 2000);
          expect(delay.inMilliseconds, lessThanOrEqualTo(tempMs));
          expect(delay.inMilliseconds, greaterThanOrEqualTo(tempMs ~/ 2 - 1));
        }
      }
    });

    test('never exceeds maxDelay', () {
      final policy = DefaultRetryPolicy(
        baseDelay: const Duration(seconds: 1),
        maxDelay: const Duration(milliseconds: 500),
      );
      for (var attempt = 1; attempt <= 5; attempt++) {
        expect(policy.getDelay(attempt).inMilliseconds, lessThanOrEqualTo(500));
      }
    });
  });
}
