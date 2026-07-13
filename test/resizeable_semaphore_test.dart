import 'dart:async';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('ResizeableSemaphore', () {
    test('acquire/release cycles', () async {
      final sem = ResizeableSemaphore(maxPermits: 2);
      expect(sem.available, 2);

      await sem.acquire();
      expect(sem.available, 1);

      await sem.acquire();
      expect(sem.available, 0);

      sem.release();
      expect(sem.available, 1);
    });

    test('blocks when all permits are taken', () async {
      final sem = ResizeableSemaphore(maxPermits: 1);
      await sem.acquire();

      bool acquired = false;
      unawaited(sem.acquire().then((_) => acquired = true));
      await Future.microtask(() {});
      expect(acquired, false);

      sem.release();
      await Future.microtask(() {});
      expect(acquired, true);
    });

    test('resize increases capacity', () async {
      final sem = ResizeableSemaphore(maxPermits: 0);
      bool acquired = false;
      unawaited(sem.acquire().then((_) => acquired = true));
      await Future.microtask(() {});
      expect(acquired, false); // blocks because maxPermits=0

      sem.resize(2);
      await Future.microtask(() {});
      expect(acquired, true); // resize woke the waiter
    });

    test('resize down does not revoke held permits', () async {
      final sem = ResizeableSemaphore(maxPermits: 5);
      await sem.acquire();
      await sem.acquire();
      expect(sem.available, 3);

      sem.resize(1); // max < held (2) → available should be 0
      expect(sem.available, 0);
    });

    test('FIFO ordering', () async {
      final sem = ResizeableSemaphore(maxPermits: 1);
      await sem.acquire();

      final order = <int>[];
      unawaited(sem.acquire().then((_) => order.add(1)));
      unawaited(sem.acquire().then((_) => order.add(2)));

      sem.release(); // wakes waiter 1
      await Future.microtask(() {});
      sem.release(); // wakes waiter 2
      await Future.microtask(() {});

      expect(order, [1, 2]);
    });
  });
}
