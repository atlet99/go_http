import 'dart:async';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// Example of cancelling a request
Future<void> main() async {
  final client = GoHttpClient();
  final cancelSource = CancellationSource();

  // Cancel the request after 1 second
  Timer(const Duration(seconds: 1), () {
    print('Cancelling request...');
    cancelSource.cancel('User cancelled');
  });

  try {
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/delay/5'),
      cancel: cancelSource.token,
    );

    print('Response: ${response.statusCode}');
  } on CancellationError catch (e) {
    print('Request was cancelled: ${e.reason}');
  } catch (e) {
    print('Error: $e');
  } finally {
    cancelSource.dispose();
    client.dispose();
  }
}
