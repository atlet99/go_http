import 'dart:typed_data';

import 'package:go_http/go_http.dart';

Future<void> main() async {
  try {
    // No client needed — GoHttpClient is instantiated and cached internally.
    final response = await get<Uint8List>(
      Uri.parse('https://httpbin.org/get'),
    );

    print('Status:  ${response.statusCode}');
    print('Body:    ${response.text}');
  } catch (e) {
    print('Error: $e');
  }
}
