import 'dart:io';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';

Future<void> main() async {
  final client = GoHttpClient(
    timeout: const Timeout(read: Duration(minutes: 5)),
  );

  try {
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/bytes/65536'),
      onProgress: (received, total) {
        final pct = total > 0 ? (received * 100 ~/ total) : received;
        print('\rDownloaded $received / $total bytes ($pct%)');
      },
    );

    if (response.data != null) {
      await File('downloaded.bin').writeAsBytes(response.data!);
      print('\nSaved ${response.data!.length} bytes to downloaded.bin');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
