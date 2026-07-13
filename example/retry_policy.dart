import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// Example of using custom retry policy
Future<void> main() async {
  final client = GoHttpClient(
    retryPolicy: DefaultRetryPolicy(
      maxAttempts: 5,
      baseDelay: const Duration(milliseconds: 500),
      maxDelay: const Duration(seconds: 5),
    ),
    metrics: ConsoleMetricsSink(),
  );

  try {
    // Default retry policy triggers on network errors, timeouts,
    // and HTTP 429/503/504 (only for idempotent methods).
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/status/503'),
    );

    print('Status: ${response.statusCode}');
  } catch (e) {
    print('Error after retries: $e');
  } finally {
    client.dispose();
  }
}
