import 'dart:async';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

Future<List<SSEEvent>> parseAll(String input) async {
  final controller = StreamController<String>();
  final events = <SSEEvent>[];

  controller.stream.transform(const SSEParser()).listen(events.add);

  // Feed input as a single chunk.
  controller.add(input);
  await controller.close();
  return events;
}

void main() {
  group('SSEParser', () {
    test('parses a simple data event', () async {
      final events = await parseAll('data: hello\n\n');
      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
      expect(events[0].event, 'message');
    });

    test('parses event with explicit event type', () async {
      final events = await parseAll('event: custom\ndata: payload\n\n');
      expect(events[0].event, 'custom');
      expect(events[0].data, 'payload');
    });

    test('parses event with id', () async {
      final events = await parseAll('id: 42\ndata: payload\n\n');
      expect(events[0].id, '42');
      expect(events[0].hasId, isTrue);
    });

    test('parses event with retry', () async {
      final events = await parseAll('retry: 5000\ndata: payload\n\n');
      expect(events[0].retry, 5000);
      expect(events[0].hasRetry, isTrue);
    });

    test('multi-line data is joined with newline', () async {
      final events =
          await parseAll('data: line1\ndata: line2\ndata: line3\n\n');
      expect(events[0].data, 'line1\nline2\nline3');
    });

    test('strips single leading space from value', () async {
      final events = await parseAll('data: hello world\n\n');
      expect(events[0].data, 'hello world');
    });

    test('ignores comment lines', () async {
      final events = await parseAll(': this is a comment\ndata: hello\n\n');
      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
    });

    test('parses multiple events', () async {
      final input = 'data: first\n\ndata: second\n\ndata: third\n\n';
      final events = await parseAll(input);
      expect(events, hasLength(3));
      expect(events[0].data, 'first');
      expect(events[1].data, 'second');
      expect(events[2].data, 'third');
    });

    test('handles CRLF line endings', () async {
      final events = await parseAll('data: hello\r\n\r\n');
      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
    });

    test('handles CR line endings', () async {
      final events = await parseAll('data: hello\r\r');
      expect(events, hasLength(1));
      expect(events[0].data, 'hello');
    });

    test('handles chunked input with partial lines', () async {
      final controller = StreamController<String>();
      final events = <SSEEvent>[];

      controller.stream.transform(const SSEParser()).listen(events.add);

      // Feed in chunks that split across lines.
      controller.add('data: hel');
      controller.add('lo world\n\n');
      await controller.close();

      expect(events, hasLength(1));
      expect(events[0].data, 'hello world');
    });

    test('handles empty input', () async {
      final events = await parseAll('');
      expect(events, isEmpty);
    });

    test('handles data-only event (no newline before dispatch)', () async {
      // Single line without trailing blank line — flush on close.
      final events = await parseAll('data: no-trailing-newline');
      expect(events, hasLength(1));
      expect(events[0].data, 'no-trailing-newline');
    });

    test('event without data is not emitted', () async {
      // Only event type, no data line — spec says don't fire.
      final events = await parseAll('event: ping\n\n');
      expect(events, isEmpty);
    });

    test('handles unknown fields gracefully', () async {
      final events = await parseAll('data: ok\nunknown: field\n\n');
      expect(events, hasLength(1));
      expect(events[0].data, 'ok');
    });

    test('retry ignores non-integer values', () async {
      final events = await parseAll('retry: abc\ndata: x\n\n');
      expect(events[0].retry, isNull);
    });

    test('retry ignores negative values', () async {
      final events = await parseAll('retry: -1\ndata: x\n\n');
      expect(events[0].retry, isNull);
    });

    test('empty id resets last event ID (not stored)', () async {
      final events =
          await parseAll('id: 1\ndata: first\n\nid: \ndata: second\n\n');
      expect(events[0].id, '1');
      expect(events[1].id, isNull);
    });

    test('toString includes event and data', () {
      const event = SSEEvent(event: 'custom', data: 'hi');
      expect(event.toString(), contains('custom'));
      expect(event.toString(), contains('hi'));
    });
  });
}
