import 'dart:async';
import 'dart:convert';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

Future<List<ChunkedEvent>> decodeChunked(String raw) async {
  final controller = StreamController<List<int>>();
  final events = <ChunkedEvent>[];

  controller.stream.transform(const ChunkedDecoder()).listen(events.add);

  // Feed raw bytes.
  controller.add(utf8.encode(raw));
  await controller.close();
  // Allow microtasks to flush.
  await Future<void>.delayed(Duration.zero);
  return events;
}

void main() {
  group('ChunkedDecoder', () {
    test('decodes a single chunk', () async {
      final events = await decodeChunked('5\r\nHello\r\n0\r\n\r\n');
      expect(events, hasLength(2));
      expect(events[0], isA<ChunkedPart>());
      expect(utf8.decode((events[0] as ChunkedPart).data), 'Hello');
      expect(events[1], isA<ChunkedComplete>());
      expect((events[1] as ChunkedComplete).trailers, isEmpty);
    });

    test('decodes multiple chunks', () async {
      final events =
          await decodeChunked('5\r\nHello\r\n6\r\n World\r\n0\r\n\r\n');
      expect(events, hasLength(3)); // part, part, complete
      expect(utf8.decode((events[0] as ChunkedPart).data), 'Hello');
      expect(utf8.decode((events[1] as ChunkedPart).data), ' World');
    });

    test('decodes with trailers', () async {
      final raw = '5\r\nHello\r\n0\r\n'
          'Server-Timing: total;dur=123.4\r\n'
          'X-Request-Id: abc123\r\n'
          '\r\n';
      final events = await decodeChunked(raw);
      expect(events, hasLength(2));
      final complete = events[1] as ChunkedComplete;
      expect(complete.trailers['Server-Timing'], 'total;dur=123.4');
      expect(complete.trailers['X-Request-Id'], 'abc123');
    });

    test('strips single leading space from trailer value', () async {
      final raw = '2\r\nOK\r\n0\r\n'
          'Key: value with space\r\n'
          '\r\n';
      final events = await decodeChunked(raw);
      final complete = events[1] as ChunkedComplete;
      expect(complete.trailers['Key'], 'value with space');
    });

    test('ignores chunk extensions', () async {
      // chunk-ext after size is ignored per spec.
      final raw = '5;ext=val\r\nHello\r\n0\r\n\r\n';
      final events = await decodeChunked(raw);
      expect(events, hasLength(2));
      expect(utf8.decode((events[0] as ChunkedPart).data), 'Hello');
    });

    test('handles empty body', () async {
      final events = await decodeChunked('0\r\n\r\n');
      expect(events, hasLength(1));
      expect(events[0], isA<ChunkedComplete>());
      expect((events[0] as ChunkedComplete).trailers, isEmpty);
    });

    test('handles chunked input arriving in pieces', () async {
      final controller = StreamController<List<int>>();
      final events = <ChunkedEvent>[];

      controller.stream.transform(const ChunkedDecoder()).listen(events.add);

      // Feed in chunks that split mid-data.
      controller.add(utf8.encode('5\r\nHel'));
      controller.add(utf8.encode('lo\r\n0\r\n'));
      controller.add(utf8.encode('X-Custom: test\r\n\r\n'));
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(2));
      expect(utf8.decode((events[0] as ChunkedPart).data), 'Hello');
      final complete = events[1] as ChunkedComplete;
      expect(complete.trailers['X-Custom'], 'test');
    });

    test('trailer-only response (no body)', () async {
      final raw = '0\r\ngrpc-status: 0\r\ngrpc-message: OK\r\n\r\n';
      final events = await decodeChunked(raw);
      expect(events, hasLength(1));
      final complete = events[0] as ChunkedComplete;
      expect(complete.trailers['grpc-status'], '0');
      expect(complete.trailers['grpc-message'], 'OK');
    });

    test('large hex chunk size', () async {
      // 1A in hex = 26 in decimal.
      final data = 'A' * 26;
      final raw = '1a\r\n$data\r\n0\r\n\r\n';
      final events = await decodeChunked(raw);
      expect(events, hasLength(2));
      expect(utf8.decode((events[0] as ChunkedPart).data), data);
    });

    test('Response trailers field defaults to empty', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final res = Response(request: req, statusCode: 200);
      expect(res.trailers, isEmpty);
    });

    test('Response trailers field is preserved through copyWith', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final res = Response(
        request: req,
        statusCode: 200,
        trailers: {'X-Id': '123'},
      );
      final copy = res.copyWith();
      expect(copy.trailers['X-Id'], '123');
    });

    test('Response copyWith can override trailers', () {
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('https://example.com'),
      );
      final res = Response(request: req, statusCode: 200);
      final copy = res.copyWith(trailers: {'X-Id': '456'});
      expect(copy.trailers['X-Id'], '456');
    });
  });
}
