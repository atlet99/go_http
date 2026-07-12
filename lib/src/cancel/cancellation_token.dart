import 'dart:async';

/// Token for cancelling operations
class CancellationToken {
  // Synchronous delivery so listeners (e.g. transport abort) react instantly.
  final StreamController<void> _controller = StreamController<void>.broadcast(
    sync: true,
  );
  bool _isCancelled = false;
  String? _reason;

  /// Stream that emits when cancellation is requested
  Stream<void> get stream => _controller.stream;

  /// Check if cancellation has been requested
  bool get isCancelled => _isCancelled;

  /// Get the cancellation reason if available
  String? get reason => _reason;

  /// Request cancellation
  void cancel([String? reason]) {
    if (!_isCancelled) {
      _isCancelled = true;
      _reason = reason;
      _controller.add(null);
    }
  }

  /// Throw a [CancellationException] if cancellation has been requested
  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancellationException(_reason);
    }
  }

  /// Dispose resources
  void dispose() {
    _controller.close();
  }
}

/// Exception thrown when an operation is cancelled
class CancellationException implements Exception {
  CancellationException(this.reason);

  final String? reason;

  @override
  String toString() {
    return reason != null ? 'Cancelled: $reason' : 'Cancelled';
  }
}
