import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('HostCircuitBreaker', () {
    test('allows requests when closed', () {
      final cb = HostCircuitBreaker(failureThreshold: 3);
      expect(cb.canTry('x.test'), isTrue);
      expect(cb.state('x.test'), isNull);
    });

    test('trips after threshold failures', () {
      final cb = HostCircuitBreaker(failureThreshold: 3);
      for (var i = 0; i < 3; i++) {
        cb.recordFailure('x.test');
      }
      expect(cb.state('x.test'), BreakerState.open);
      expect(cb.canTry('x.test'), isFalse);
    });

    test('recovers after cooldown', () async {
      final cb = HostCircuitBreaker(
        failureThreshold: 2,
        cooldown: const Duration(milliseconds: 10),
      );
      cb.recordFailure('x.test');
      cb.recordFailure('x.test');
      expect(cb.canTry('x.test'), isFalse);

      await Future.delayed(const Duration(milliseconds: 20));
      expect(cb.canTry('x.test'), isTrue); // half-open
      expect(cb.state('x.test'), BreakerState.halfOpen);
    });

    test('success resets and closes the breaker', () {
      final cb =
          HostCircuitBreaker(failureThreshold: 3, cooldown: Duration.zero);
      for (var i = 0; i < 3; i++) {
        cb.recordFailure('x.test');
      }
      expect(
        cb.canTry('x.test'),
        isTrue, // cooldown zero, immediately half-open
      );

      cb.recordSuccess('x.test');
      expect(cb.state('x.test'), BreakerState.closed);
      expect(cb.canTry('x.test'), isTrue);
    });
  });
}
