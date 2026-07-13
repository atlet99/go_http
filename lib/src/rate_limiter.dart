import 'dart:async';

/// Token-bucket rate limiter.
///
/// Maintains a bucket of tokens that refills at [rate] tokens per second, up
/// to [burst] maximum. [take] consumes one token, waiting (asynchronously)
/// until one is available.
///
/// Thread-safe for concurrent [take] calls (Dart's single-threaded event loop
/// serialises access, so no locking needed).
///
/// ```dart
/// final limiter = RateLimiter(rate: 10, burst: 5);
/// await limiter.take(); // may wait for capacity
/// ```
class RateLimiter {
  RateLimiter({required double rate, required int burst})
      : _rate = rate,
        _burst = burst,
        _tokens = burst.toDouble();

  final double _rate;
  final int _burst;

  /// Current token count (refilled lazily on [take]).
  double _tokens;

  /// Monotonic microsecond clock from the last refill.
  int _lastMicros = _nowMicros();

  /// Consume one token, waiting asynchronously until one is available.
  Future<void> take() async {
    while (true) {
      _refill();
      if (_tokens >= 1) {
        _tokens -= 1;
        return;
      }
      // How long until the next token is replenished?
      final deficit = 1 - _tokens;
      final waitUs = (deficit / _rate * 1e6).ceil();
      await Future.delayed(Duration(microseconds: waitUs));
    }
  }

  void _refill() {
    final now = _nowMicros();
    final elapsedSec = (now - _lastMicros) / 1e6;
    if (elapsedSec > 0) {
      _tokens = (_tokens + elapsedSec * _rate).clamp(0, _burst.toDouble());
      _lastMicros = now;
    }
  }

  static int _nowMicros() => DateTime.now().microsecondsSinceEpoch;
}
