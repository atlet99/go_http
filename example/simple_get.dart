import 'dart:typed_data';

import 'package:go_http/go_http.dart';

Future<void> main() async {
  final client = GoHttpClient();

  try {
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/get'),
    );

    print('Status:  ${response.statusCode}');
    print('Headers: ${response.headers}');
    print('Body:    ${response.text}');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
