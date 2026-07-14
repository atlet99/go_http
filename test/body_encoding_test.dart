import 'dart:convert' show jsonDecode, utf8;
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

String _body(Object? b) =>
    b is List<int> ? String.fromCharCodes(b) : (b?.toString() ?? '');

void main() {
  group('encodeRequest', () {
    test('json object to application/json bytes (strict)', () {
      final enc = encodeRequest(
        json: {'a': 1, 'b': 'x y'},
        headers: Headers(const {}),
      );
      expect(enc.headers['content-type'], 'application/json');
      expect(
        jsonDecode(_body(enc.body)),
        {'a': 1, 'b': 'x y'},
      );
    });

    test('Map data to application/x-www-form-urlencoded', () {
      final enc = encodeRequest(
        data: {'k': 'v w', 'n': 7},
        headers: Headers(const {}),
      );
      expect(enc.headers['content-type'], 'application/x-www-form-urlencoded');
      expect(enc.body, 'k=v+w&n=7');
    });

    test('string content passes through untouched', () {
      final enc = encodeRequest(
        content: 'raw-body',
        headers: Headers(const {}),
      );
      expect(enc.headers['content-type'], isNull);
      expect(enc.body, 'raw-body');
    });
  });

  group('peekLength', () {
    test('null returns 0', () {
      expect(peekLength(null), 0);
    });

    test('String returns UTF-8 byte length', () {
      expect(peekLength('hello'), 5);
      expect(peekLength('héllo'), 6); // é = 2 bytes
    });

    test('List<int> returns length', () {
      expect(peekLength([1, 2, 3]), 3);
    });

    test('Uint8List returns length', () {
      expect(peekLength(Uint8List.fromList([1, 2, 3])), 3);
    });

    test('Stream returns null', () {
      expect(
        peekLength(Stream<List<int>>.fromIterable([utf8.encode('data')])),
        isNull,
      );
    });
  });

  group('GoHttpClient body encoding', () {
    test('post with Map data is url-encoded', () async {
      final transport = FakeTransport([
        (r) async {
          expect(
            r.headers['content-type'],
            'application/x-www-form-urlencoded',
          );
          expect(_body(r.body), 'a=1&b=2');
          return ok(200)(r);
        },
      ]);
      final client = GoHttpClient(transport: transport);
      await client.post<Uint8List>(
        Uri.parse('https://x.test/'),
        data: {'a': '1', 'b': '2'},
      );
      client.dispose();
    });

    test('post with json sets application/json', () async {
      final transport = FakeTransport([
        (r) async {
          expect(r.headers['content-type'], 'application/json');
          expect(jsonDecode(_body(r.body)), {'a': 1});
          return ok(200)(r);
        },
      ]);
      final client = GoHttpClient(transport: transport);
      await client.post<Uint8List>(
        Uri.parse('https://x.test/'),
        json: {'a': 1},
      );
      client.dispose();
    });
  });
}
