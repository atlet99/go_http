import 'dart:async';
import 'dart:collection';

/// A semaphore whose maximum permit count can be changed at runtime.
///
/// Useful for adaptive connection pooling: increase permits under light load,
/// decrease under back-pressure.
///
/// ```dart
/// final sem = ResizeableSemaphore(maxPermits: 10);
/// await sem.acquire();
/// // ... do work ...
/// sem.release();
/// ```
class ResizeableSemaphore {
  ResizeableSemaphore({required int maxPermits}) : _maxPermits = maxPermits;

  int _maxPermits;

  /// Current number of permits held by acquirers.
  int _held = 0;

  /// Waiters queued FIFO for fairness.
  final _queue = Queue<Completer<void>>();

  /// Acquire one permit, waiting asynchronously until one is available.
  Future<void> acquire() async {
    if (_tryAcquire()) {
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    return c.future;
  }

  /// Return one permit to the pool. Wakes the longest-waiting acquirer.
  void release() {
    _held--;
    _drainQueue();
  }

  /// Change the maximum permit count at runtime.
  ///
  /// If [n] is smaller than the current max, outstanding permits are not
  /// revoked; new acquires stall until releases bring held permits below [n].
  void resize(int n) {
    _maxPermits = n;
    _drainQueue();
  }

  /// Number of permits that can be acquired immediately.
  int get available => (_maxPermits - _held).clamp(0, _maxPermits);

  /// Maximum permit count (may be changed via [resize]).
  int get maxPermits => _maxPermits;

  bool _tryAcquire() {
    if (_held < _maxPermits) {
      _held++;
      return true;
    }
    return false;
  }

  void _drainQueue() {
    while (_queue.isNotEmpty && _held < _maxPermits) {
      final c = _queue.removeFirst();
      if (!c.isCompleted) {
        _held++;
        c.complete();
      }
    }
  }
}
