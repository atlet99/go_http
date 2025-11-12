import '../errors.dart';
import '../request.dart';
import '../response.dart';

/// Abstract interface for metrics collection
abstract class MetricsSink {
  /// Called when a request starts
  void onRequestStart(Request request);

  /// Called when a request completes successfully
  void onRequestEnd(Request request, Response response);

  /// Called when a request is retried
  void onRetry(Request request, int attempt, Duration delay);

  /// Called when an error occurs
  void onError(HttpError error);
}
