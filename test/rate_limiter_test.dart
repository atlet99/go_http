import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter.take', () {
    test('instant when tokens are available', () async {
      final limiter = RateLimiter(rate: 100, burst: 5);

      for (var i = 0; i < 5; i++) {
        // Each call should return near-instantly while burst lasts.
        await expectLater(limiter.take(), completes);
      }
    });

    test('waits when burst is exhausted', () async {
      final limiter = RateLimiter(rate: 100, burst: 1);
      await limiter.take(); // consumes the only token

      final sw = Stopwatch()..start();
      // Next take must wait for a refill (~10ms for 1 token at 100 tps).
      await limiter.take();
      sw.stop();

      // At 100 tokens/sec, 1 token takes 10ms. Allow generous margin.
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(5));
    });

    test('supports concurrent takers', () async {
      // A slow rate with a small burst — concurrent takers queue correctly.
      final limiter = RateLimiter(rate: 50, burst: 2);
      await limiter.take(); // 1 consumed, 1 left
      await limiter.take(); // 2 consumed, 0 left

      // Now 3 concurrent takers all need tokens (refill at 50/sec ≈ 20ms each).
      final sw = Stopwatch()..start();
      await Future.wait([
        limiter.take(),
        limiter.take(),
        limiter.take(),
      ]);
      sw.stop();

      // Three tokens at 50/sec ≈ 60ms total (with burst=0 now, sequential).
      // The last taker waits ~40ms (2 refills after the initial burst).
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(30));
    });
  });
}
