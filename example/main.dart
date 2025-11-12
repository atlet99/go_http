import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// Basic example of using go_http
///
/// This example demonstrates basic usage of the HTTP client
/// for performing a GET request.
Future<void> main() async {
  // Create a client instance
  final client = GoHttpClient();

  try {
    // Perform a GET request
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/get'),
    );

    // Print response information
    print('Status Code: ${response.statusCode}');
    print('Headers: ${response.headers}');
    print('Data length: ${response.data?.length ?? 0} bytes');
  } catch (e) {
    print('Error: $e');
  } finally {
    // Important: always dispose of client resources
    client.dispose();
  }
}

