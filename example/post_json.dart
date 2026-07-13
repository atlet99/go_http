import 'dart:typed_data';

import 'package:go_http/go_http.dart';

Future<void> main() async {
  final client = GoHttpClient();

  try {
    final response = await client.post<Uint8List>(
      Uri.parse('https://httpbin.org/post'),
      json: {
        'title': 'Hello',
        'body': 'World',
        'userId': 1,
      },
    );

    print('Status: ${response.statusCode}');
    final body = response.json() as Map<String, dynamic>;
    print('JSON:   ${body['json']}');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
