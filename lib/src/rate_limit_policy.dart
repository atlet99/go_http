import 'rate_limiter.dart';

/// Convenient rate-limit policy that wraps [RateLimiter].
///
/// Two modes:
/// - **global** — single token-bucket shared across all hosts.
/// - **perHost** — one token-bucket per host, created lazily.
///
/// ```dart
/// final policy = RateLimitPolicy.global(100);
/// await policy.wait('api.example.com');
/// ```
class RateLimitPolicy {
  /// Token-bucket shared by **all** hosts.
  factory RateLimitPolicy.global(double rps, {int? burst}) {
    return RateLimitPolicy._(
      RateLimiter(rate: rps, burst: burst ?? rps.ceil()),
      rps,
      burst,
    );
  }

  /// One token-bucket per host (created lazily on first [wait]).
  factory RateLimitPolicy.perHost(double rpsPerHost, {int? burst}) {
    return RateLimitPolicy._(null, rpsPerHost, burst);
  }

  RateLimitPolicy._(this._global, this._rps, this._burst);

  final RateLimiter? _global;
  final double _rps;
  final int? _burst;

  final _hostLimiters = <String, RateLimiter>{};

  /// Wait for capacity to [host]. Blocks until a token is available.
  Future<void> wait(String host) async {
    if (_global != null) {
      return _global!.take();
    }
    final limiter = _hostLimiters.putIfAbsent(
      host,
      () => RateLimiter(rate: _rps, burst: _burst ?? _rps.ceil()),
    );
    return limiter.take();
  }
}
