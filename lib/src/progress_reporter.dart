/// Live batch progress: RPS, done/total, ETA.
///
/// Wire into [BatchExecutor.run] via [onProgress] or [onResults]:
/// ```dart
/// final pr = ProgressReporter(total: 100)..start();
/// await batch.run(requests, onProgress: (d, t) {
///   pr.tick();
///   print(pr.summary);
/// });
/// print('Done: ${pr.elapsed}');
/// ```
class ProgressReporter {
  ProgressReporter({required this.total});

  final int total;
  int done = 0;
  final Stopwatch _watch = Stopwatch();

  void start() {
    done = 0;
    _watch
      ..reset()
      ..start();
  }

  void tick() {
    done++;
  }

  Duration get elapsed => _watch.elapsed;

  double get rps {
    final ms = _watch.elapsed.inMilliseconds;
    if (ms <= 0) {
      return 0;
    }
    return done / (ms / 1000);
  }

  Duration? get eta {
    if (done <= 0) {
      return null;
    }
    final remaining = total - done;
    final rate = rps;
    if (rate <= 0) {
      return null;
    }
    return Duration(seconds: (remaining / rate).round());
  }

  String get summary {
    final pct = total > 0 ? (done / total * 100).toStringAsFixed(1) : '--';
    final remaining = eta;
    final etaStr =
        remaining != null ? _formatDuration(remaining) : '--';
    return '$done/$total ($pct%) — '
        '${rps.toStringAsFixed(1)} rps — '
        'ETA $etaStr';
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h}h${m}m';
    }
    if (m > 0) {
      return '${m}m${s}s';
    }
    return '${s}s';
  }
}
