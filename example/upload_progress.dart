import 'dart:typed_data';

import 'package:go_http/go_http.dart';

Future<void> main() async {
  final client = GoHttpClient(
    timeout: const Timeout(write: Duration(minutes: 5)),
  );

  final body = Uint8List.fromList(List.filled(256 * 1024, 0xAB)); // 256 KiB

  try {
    final response = await client.post<Uint8List>(
      Uri.parse('https://httpbin.org/post'),
      data: body,
      onSendProgress: (sent, total) {
        final pct = total > 0 ? (sent * 100 ~/ total) : sent;
        print('\rUploaded $sent / $total bytes ($pct%)');
      },
    );

    print('\nStatus:  ${response.statusCode}');
    print('Body:    ${response.text}');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
