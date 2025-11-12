import 'dart:math';

import '../errors.dart';
import '../request.dart';

/// Policy for retrying failed requests
abstract class RetryPolicy {
  /// Determine if a request should be retried
  bool shouldRetry(
    Request request,
    Object error,
    int attempt,
  );

  /// Calculate the delay before the next retry attempt
  Duration getDelay(int attempt);
}

/// Default retry policy with decorrelated jitter backoff
class DefaultRetryPolicy implements RetryPolicy {
  DefaultRetryPolicy({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 300),
    this.maxDelay = const Duration(milliseconds: 2000),
  });

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random = Random();

  @override
  bool shouldRetry(
    Request request,
    Object error,
    int attempt,
  ) {
    // Don't retry if max attempts reached
    if (attempt >= maxAttempts) {
      return false;
    }

    // Only retry idempotent methods
    if (!request.isIdempotent) {
      return false;
    }

    // Retry on network errors
    if (error is NetworkError) {
      return true;
    }

    // Retry on timeout errors
    if (error is TimeoutError) {
      return true;
    }

    // Retry on specific HTTP status codes
    if (error is HttpResponseError) {
      final statusCode = error.statusCode;
      return statusCode == 429 || // Too Many Requests
          statusCode == 503 || // Service Unavailable
          statusCode == 504; // Gateway Timeout
    }

    return false;
  }

  @override
  Duration getDelay(int attempt) {
    // Decorrelated jitter backoff algorithm
    // delay = random_between(0, min(max_delay, base_delay * 2^attempt))
    final exponentialDelay = baseDelay * pow(2, attempt);
    final cappedDelay =
        exponentialDelay < maxDelay ? exponentialDelay : maxDelay;

    // Generate random delay between 0 and capped delay
    final randomFactor = _random.nextDouble();
    final delay = Duration(
      milliseconds: (cappedDelay.inMilliseconds * randomFactor).round(),
    );

    return delay;
  }
}
