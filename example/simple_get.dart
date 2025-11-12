import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// Simple GET request example
Future<void> main() async {
  final client = GoHttpClient();

  try {
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/get'),
    );

    print('Status: ${response.statusCode}');
    print('Headers: ${response.headers}');
    print('Data length: ${response.data?.length ?? 0} bytes');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
