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

  /// Fail-fast preset for scanning/probing workloads: 1 retry, short backoff.
  static RetryPolicy scanning() => DefaultRetryPolicy(
        maxAttempts: 2,
        baseDelay: const Duration(milliseconds: 100),
        maxDelay: const Duration(milliseconds: 500),
      );

  /// Max-reliability preset for single critical requests: 4 retries, long
  /// backoff, retries more error codes (5xx + 429).
  static RetryPolicy single() => _SingleRetryPolicy();
}

/// Default retry policy using exponential backoff with **equal jitter**.
///
/// Equal jitter (an AWS-recommended strategy) computes:
/// `temp = min(maxDelay, baseDelay * 2^attempt)`, then
/// `delay = temp/2 + random(0, temp/2)`.
///
/// Unlike decorrelated jitter, equal jitter is stateless, so a single shared
/// [DefaultRetryPolicy] instance is safe to reuse across concurrent requests
/// without delay-state bleeding between them.
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

    // Never retry cancellations
    if (error is CancellationError) {
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
    if (error is HttpStatusError) {
      final statusCode = error.statusCode;
      return statusCode == 429 || // Too Many Requests
          statusCode == 503 || // Service Unavailable
          statusCode == 504; // Gateway Timeout
    }

    return false;
  }

  @override
  Duration getDelay(int attempt) {
    // Exponential backoff with equal jitter (stateless, AWS-recommended).
    final exponential = baseDelay * pow(2, attempt);
    final temp = exponential < maxDelay ? exponential : maxDelay;

    final halfMs = temp.inMilliseconds ~/ 2;
    final jitter = halfMs <= 0 ? 0 : _random.nextInt(halfMs + 1);

    return Duration(milliseconds: halfMs + jitter);
  }
}

/// Aggressive retry policy for single critical requests.
///
/// Retries on any 5xx, on 429, and on all transport errors. Non-idempotent
/// methods get one retry attempt (safe for POST where the server says 5xx
/// before processing).
class _SingleRetryPolicy implements RetryPolicy {
  final Random _random = Random();

  @override
  bool shouldRetry(Request request, Object error, int attempt) {
    if (attempt >= 5) {
      return false;
    }
    if (error is CancellationError) {
      return false;
    }

    // Transport errors: always retry
    if (error is NetworkError || error is TimeoutError) {
      return true;
    }

    // HTTP errors: retry on any 5xx or 429
    if (error is HttpStatusError) {
      final sc = error.statusCode;
      if (sc >= 500 || sc == 429) {
        return true;
      }
    }

    return false;
  }

  @override
  Duration getDelay(int attempt) {
    // Exponential: base 500ms, capped at 8s, equal jitter.
    final ms = (500 * pow(2, attempt)).toInt().clamp(500, 8000);
    final halfMs = ms ~/ 2;
    final jitter = halfMs <= 0 ? 0 : _random.nextInt(halfMs + 1);
    return Duration(milliseconds: halfMs + jitter);
  }
}
