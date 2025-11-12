import 'dart:io';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// Example of downloading a file with progress tracking
Future<void> main() async {
  final client = GoHttpClient();

  try {
    // For now, we'll just download the data
    // Progress tracking will be added in a future version
    final response = await client.get<Uint8List>(
      Uri.parse('https://httpbin.org/bytes/1024'),
    );

    if (response.data != null) {
      final file = File('downloaded_file.bin');
      await file.writeAsBytes(response.data!);
      print('Downloaded ${response.data!.length} bytes to ${file.path}');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.dispose();
  }
}
