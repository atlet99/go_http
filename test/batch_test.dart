import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('BatchExecutor', () {
    test('collects a Result per request and never throws on failure', () async {
      final transport = FakeTransport([
        ok(200, Uint8List(1)),
        status(500),
        ok(200, Uint8List(1)),
      ]);
      final client = GoHttpClient(transport: transport);
      final batch = BatchExecutor(client, concurrency: 2);

      final results = await batch.run([
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/1')),
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/2')),
        Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/3')),
      ]);

      expect(results, hasLength(3));
      expect(results[0].isOk, isTrue);
      expect(results[1].isError, isTrue);
      expect(results[2].isOk, isTrue);
      client.dispose();
    });

    test('reports progress as it goes', () async {
      final transport = FakeTransport([
        ok(200),
        ok(200),
        ok(200),
      ]);
      final client = GoHttpClient(transport: transport);
      final batch = BatchExecutor(client, concurrency: 1);

      final seen = <int>[];
      await batch.run(
        [
          Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/1')),
          Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/2')),
          Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/3')),
        ],
        onProgress: (d, t) => seen.add(d),
      );

      expect(seen, [1, 2, 3]);
      client.dispose();
    });
  });
}
