import 'dart:convert';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('JsonDecoder', () {
    test('decodes from bytes', () {
      final decoder = JsonDecoder();
      final bytes = Uint8List.fromList(utf8.encode('{"a":1,"b":"x"}'));
      final result = decoder.decode(bytes) as Map<String, dynamic>;
      expect(result['a'], 1);
      expect(result['b'], 'x');
    });

    test('decodes from string', () {
      final decoder = JsonDecoder();
      final result = decoder.decode('{"k": 42}') as Map<String, dynamic>;
      expect(result['k'], 42);
    });
  });

  group('BytesDecoder', () {
    test('passes through Uint8List', () {
      final input = Uint8List.fromList([1, 2, 3]);
      expect(BytesDecoder().decode(input), same(input));
    });

    test('converts List<int> to Uint8List', () {
      final result = BytesDecoder().decode(<int>[4, 5, 6]);
      expect(result, isA<Uint8List>());
      expect(result, [4, 5, 6]);
    });

    test('converts String to bytes', () {
      final result = BytesDecoder().decode('AB');
      expect(result, [65, 66]);
    });

    test('throws on unsupported type', () {
      expect(() => BytesDecoder().decode(42), throwsArgumentError);
    });
  });
}
