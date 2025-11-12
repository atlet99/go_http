import 'cancellation_token.dart';

/// Source for creating and managing cancellation tokens
class CancellationSource {
  final CancellationToken _token = CancellationToken();

  /// Get the cancellation token
  CancellationToken get token => _token;

  /// Cancel the token
  void cancel([String? reason]) {
    _token.cancel(reason);
  }

  /// Check if cancellation has been requested
  bool get isCancelled => _token.isCancelled;

  /// Dispose resources
  void dispose() {
    _token.dispose();
  }
}
