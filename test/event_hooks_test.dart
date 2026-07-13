import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('GoHttpClient eventHooks', () {
    test('fires request and response hooks per attempt', () async {
      final requests = <Request>[];
      final responses = <Response>[];
      final transport = FakeTransport([ok(200, Uint8List(2))]);
      final client = GoHttpClient(
        transport: transport,
        eventHooks: EventHooks(
          request: [requests.add],
          response: [responses.add],
        ),
      );

      await client.get<Uint8List>(Uri.parse('https://x.test/'));

      expect(requests, hasLength(1));
      expect(requests.single.uri.toString(), contains('x.test'));
      expect(responses, hasLength(1));
      expect(responses.single.statusCode, 200);
      client.dispose();
    });

    test('hot-swappable at runtime via setter', () async {
      final seen = <int>[];
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);
      client.eventHooks = EventHooks(response: [(r) => seen.add(r.statusCode)]);

      await client.get<Uint8List>(Uri.parse('https://x.test/'));
      expect(seen, [200]);
      client.dispose();
    });
  });
}
