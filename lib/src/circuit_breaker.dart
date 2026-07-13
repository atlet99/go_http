/// Circuit-breaker state for a single host.
enum BreakerState { closed, open, halfOpen }

/// Per-host circuit breaker that trips after consecutive failures.
///
/// A tripped breaker fails fast (throws [CircuitOpenError]) until the cooldown
/// elapses, then transitions to half-open and allows one probe request.
///
/// ```dart
/// final cb = HostCircuitBreaker(failureThreshold: 5, cooldown: Duration(seconds: 30));
/// if (cb.canTry('api.example.com')) {
///   try { ...; cb.recordSuccess('api.example.com'); }
///   catch (e) { cb.recordFailure('api.example.com'); }
/// } else {
///   // fail fast
/// }
/// ```
class HostCircuitBreaker {
  HostCircuitBreaker({
    this.failureThreshold = 5,
    this.cooldown = const Duration(seconds: 30),
  });

  final int failureThreshold;
  final Duration cooldown;

  final _hosts = <String, _HostState>{};

  /// Returns `true` if the request to [host] should be allowed through.
  bool canTry(String host) {
    final state = _hosts[host];
    if (state == null) {
      return true;
    }
    switch (state.state) {
      case BreakerState.closed:
        return true;
      case BreakerState.open:
        if (state._elapsedSince(cooldown)) {
          state.state = BreakerState.halfOpen;
          return true;
        }
        return false;
      case BreakerState.halfOpen:
        return true; // single probe
    }
  }

  /// Record a successful request to [host]; resets the failure count.
  void recordSuccess(String host) {
    _hosts[host] = _HostState(BreakerState.closed);
  }

  /// Record a failed request to [host]; may trip the breaker.
  void recordFailure(String host) {
    final state =
        _hosts.putIfAbsent(host, () => _HostState(BreakerState.closed));
    state.failures++;
    state.lastFailure = DateTime.now();
    if (state.failures >= failureThreshold) {
      state.state = BreakerState.open;
    }
  }

  /// Current state for [host], or `null` if no requests have been recorded.
  BreakerState? state(String host) => _hosts[host]?.state;
}

class _HostState {
  _HostState(this.state);
  BreakerState state;
  int failures = 0;
  DateTime? lastFailure;

  bool _elapsedSince(Duration d) {
    final lf = lastFailure;
    if (lf == null) {
      return true;
    }
    return DateTime.now().difference(lf) >= d;
  }
}

/// Thrown when a circuit breaker rejects a request (fail-fast).
class CircuitOpenError implements Exception {
  CircuitOpenError(this.host, {this.message});

  final String host;
  final String? message;

  @override
  String toString() =>
      message ?? 'Circuit breaker is open for $host; failing fast.';
}
