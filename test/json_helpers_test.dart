import 'dart:async';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('parseJsonInIsolate', () {
    test('decodes a map', () async {
      final result = await parseJsonInIsolate('{"a":1,"b":"x"}');
      expect(result, isA<Map>());
      final map = result as Map;
      expect(map['a'], 1);
      expect(map['b'], 'x');
    });

    test('decodes a list', () async {
      final result = await parseJsonInIsolate('[1,2,3]');
      expect(result, [1, 2, 3]);
    });

    test('decodes nested structures', () async {
      final json = '{"items":[{"id":1},{"id":2}],"count":2}';
      final result = await parseJsonInIsolate(json);
      final map = result as Map;
      expect(map['count'], 2);
      final items = map['items'] as List;
      expect(items, hasLength(2));
    });

    test('returns null for null input', () async {
      final result = await parseJsonInIsolate('null');
      expect(result, isNull);
    });

    test('throws on invalid JSON', () async {
      expect(() => parseJsonInIsolate('{bad}'), throwsFormatException);
    });
  });

  group('NdjsonParser', () {
    test('parses multiple JSON lines', () async {
      final input = '{"a":1}\n{"b":2}\n{"c":3}\n';
      final results =
          await Stream.value(input).transform(const NdjsonParser()).toList();
      expect(results, hasLength(3));
      expect((results[0] as Map)['a'], 1);
      expect((results[1] as Map)['b'], 2);
      expect((results[2] as Map)['c'], 3);
    });

    test('skips blank lines', () async {
      final input = '{"a":1}\n\n{"b":2}\n';
      final results =
          await Stream.value(input).transform(const NdjsonParser()).toList();
      expect(results, hasLength(2));
    });

    test('skips comment lines', () async {
      final input = '// header comment\n{"a":1}\n// middle\n{"b":2}\n';
      final results =
          await Stream.value(input).transform(const NdjsonParser()).toList();
      expect(results, hasLength(2));
      expect((results[0] as Map)['a'], 1);
      expect((results[1] as Map)['b'], 2);
    });

    test('parses primitive values', () async {
      final input = '42\n"hello"\ntrue\nnull\n';
      final results =
          await Stream.value(input).transform(const NdjsonParser()).toList();
      expect(results, [42, 'hello', true, null]);
    });

    test('handles chunked input', () async {
      final controller = StreamController<String>();
      final results = <dynamic>[];

      controller.stream.transform(const NdjsonParser()).listen(results.add);

      controller.add('{"x":');
      controller.add('1}\n');
      controller.add('{"y":2}\n');
      await controller.close();
      await Future<void>.delayed(Duration.zero);

      expect(results, hasLength(2));
      expect((results[0] as Map)['x'], 1);
      expect((results[1] as Map)['y'], 2);
    });

    test('empty input produces no events', () async {
      final results =
          await Stream.value('').transform(const NdjsonParser()).toList();
      expect(results, isEmpty);
    });
  });
}
