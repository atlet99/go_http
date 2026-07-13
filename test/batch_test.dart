import 'dart:async';
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

    test('callback chaining calls multiple onResults in order', () async {
      final transport = FakeTransport([ok(200), ok(200)]);
      final client = GoHttpClient(transport: transport);
      final batch = BatchExecutor(client, concurrency: 1);

      final order = <String>[];
      await batch.run(
        [
          Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/1')),
          Request(method: HttpMethod.get, uri: Uri.parse('https://x.test/2')),
        ],
        onResult: (_) => order.add('legacy'),
        onResults: [
          (_) => order.add('cb1'),
          (_) => order.add('cb2'),
        ],
      );

      expect(order, ['legacy', 'cb1', 'cb2', 'legacy', 'cb1', 'cb2']);
      client.dispose();
    });
  });

  group('ProgressReporter', () {
    test('tracks done and total', () {
      final pr = ProgressReporter(total: 10)..start();
      pr.tick();
      pr.tick();
      expect(pr.done, 2);
      expect(pr.summary, contains('2/10'));
    });

    test('rps is zero before any tick', () {
      final pr = ProgressReporter(total: 10)..start();
      expect(pr.rps, 0);
    });

    test('eta is null when nothing done', () {
      final pr = ProgressReporter(total: 10)..start();
      expect(pr.eta, isNull);
    });

    test('summary contains percentage, rps, and ETA', () async {
      final pr = ProgressReporter(total: 5)..start();
      // Simulate a small delay so rps > 0
      for (var i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 1));
        pr.tick();
      }
      expect(pr.summary, contains('3/5 (60.0%)'));
      expect(pr.summary, contains('rps'));
      expect(pr.summary, contains('ETA'));
    });

    test('elapsed returns watch duration', () async {
      final pr = ProgressReporter(total: 1)..start();
      await Future.delayed(const Duration(milliseconds: 5));
      expect(pr.elapsed.inMilliseconds >= 5, isTrue);
    });

    test('start resets done and watch', () async {
      final pr = ProgressReporter(total: 5)..start();
      pr.tick();
      pr.tick();
      await Future.delayed(const Duration(milliseconds: 2));
      pr.start(); // reset
      expect(pr.done, 0);
      expect(pr.elapsed.inMilliseconds < 5, isTrue);
    });
  });
}
