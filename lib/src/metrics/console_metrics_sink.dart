import '../errors.dart';
import '../logger.dart';
import '../request.dart';
import '../response.dart';
import 'metrics_sink.dart';

/// Console-based metrics sink for debugging and monitoring.
class ConsoleMetricsSink implements MetricsSink {
  ConsoleMetricsSink({
    this.enabled = true,
    this.logger = defaultLog,
  });

  final bool enabled;
  final Logger logger;

  @override
  void onRequestStart(Request request) {
    if (!enabled) {
      return;
    }
    logger('[metrics] Request started: ${request.methodString} ${request.uri}');
  }

  @override
  void onRequestEnd(Request request, Response response) {
    if (!enabled) {
      return;
    }
    logger(
      '[metrics] Request completed: ${request.methodString} ${request.uri} '
      '-> ${response.statusCode}',
    );
  }

  @override
  void onRetry(Request request, int attempt, Duration delay) {
    if (!enabled) {
      return;
    }
    logger(
      '[metrics] Retry attempt $attempt for ${request.methodString} '
      '${request.uri} after ${delay.inMilliseconds}ms',
    );
  }

  @override
  void onError(HttpError error) {
    if (!enabled) {
      return;
    }
    logger(
      '[metrics] Error: ${error.message} for ${error.request.methodString} '
      '${error.request.uri}',
    );
  }
}
