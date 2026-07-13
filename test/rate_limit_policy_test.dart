import 'dart:async';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimitPolicy', () {
    test('global mode uses a single shared limiter', () async {
      final policy = RateLimitPolicy.global(100, burst: 5);
      // Burst allows 5 instant takes
      for (var i = 0; i < 5; i++) {
        await expectLater(policy.wait('host-a'), completes);
      }
      // 6th should be near-instant too because it's 100 tps
      await expectLater(policy.wait('host-b'), completes);
    });

    test('perHost mode creates separate limiters per host', () async {
      final policy = RateLimitPolicy.perHost(100, burst: 2);

      // Each host has its own burst of 2
      await policy.wait('a');
      await policy.wait('a');
      await policy.wait('b');
      await policy.wait('b');
      // No error: separate limiters
    });

    test('perHost isolates failures between hosts', () async {
      final policy = RateLimitPolicy.perHost(100, burst: 1);
      await policy.wait('a'); // exhaust host a

      bool aBlocked = false;
      unawaited(policy.wait('a').then((_) => aBlocked = true));
      await Future.microtask(() {});
      expect(aBlocked, false); // host a is blocked

      // Host b is unaffected
      await expectLater(policy.wait('b'), completes);
    });
  });
}
