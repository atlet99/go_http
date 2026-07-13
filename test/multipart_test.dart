import 'dart:convert';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('Multipart', () {
    test('boundary is 32 hex chars', () {
      final mp = Multipart([], []);
      expect(mp.boundary.length, 32);
      expect(
        mp.boundary,
        matches(RegExp(r'^[0-9a-f]{32}$')),
      );
    });

    test('boundaryFromContentType extracts the token', () {
      expect(
        Multipart.boundaryFromContentType(
          'multipart/form-data; boundary=abc123',
        ),
        'abc123',
      );
      expect(
        Multipart.boundaryFromContentType(
          'multipart/form-data; boundary="quoted-bound"',
        ),
        'quoted-bound',
      );
      expect(
        Multipart.boundaryFromContentType('application/json'),
        isNull,
      );
    });

    test('contentType carries the boundary', () {
      final mp = Multipart([], [], boundary: 'BOUND');
      expect(mp.contentType, 'multipart/form-data; boundary=BOUND');
    });

    test('renders fields and files with correct framing', () {
      final mp = Multipart(
        [MultipartField('field1', 'value1')],
        [
          MultipartFile.bytes(
            'file1',
            'a.txt',
            utf8.encode('hello'),
            contentType: 'text/plain',
          ),
        ],
        boundary: 'B',
      );

      final body = String.fromCharCodes(mp.render());
      expect(body, contains('--B\r\n'));
      expect(
        body,
        contains('Content-Disposition: form-data; name="field1"'),
      );
      expect(body, contains('value1'));
      expect(
        body,
        contains(
          'Content-Disposition: form-data; name="file1"; '
          'filename="a.txt"',
        ),
      );
      expect(body, contains('Content-Type: text/plain'));
      expect(body, contains('hello'));
      expect(body, endsWith('--B--\r\n'));
    });

    test('guesses content type from extension, defaults to octet-stream', () {
      expect(
        MultipartFile.bytes('f', 'x.png', [], contentType: null)
            .resolvedContentType,
        'image/png',
      );
      expect(
        MultipartFile.bytes('f', 'x.unknownext', [], contentType: null)
            .resolvedContentType,
        'application/octet-stream',
      );
    });

    test('escapes control chars and quotes in names/filenames', () {
      final mp = Multipart(
        [MultipartField('na"me\r\n', 'v')],
        [
          MultipartFile.bytes('f', 'a"b.txt', [], contentType: null),
        ],
        boundary: 'B',
      );
      final body = String.fromCharCodes(mp.render());
      expect(body, isNot(contains('na"me')));
      expect(body, contains('name="na%22me"'));
      expect(body, contains('filename="a%22b.txt"'));
      expect(body, isNot(contains('\r\nname')));
    });

    test('encodedLength matches rendered bytes', () {
      final mp = Multipart(
        [MultipartField('a', '1'), MultipartField('b', '2')],
        [
          MultipartFile.bytes('f', 'x.bin', [1, 2, 3], contentType: null),
        ],
        boundary: 'B',
      );
      expect(mp.encodedLength, mp.render().length);
    });

    test('stream yields the body in chunks', () async {
      final mp = Multipart(
        [MultipartField('a', '1')],
        [],
        boundary: 'B',
      );
      final chunks = await mp.stream(chunkSize: 8).toList();
      final joined = chunks.expand((c) => c).toList();
      expect(joined, mp.render());
    });
  });

  group('GoHttpClient multipart integration', () {
    test('renders a Multipart body and sets Content-Type', () async {
      final mp = Multipart(
        [MultipartField('field', 'value')],
        [
          MultipartFile.bytes(
            'upload',
            'pic.png',
            [0x89, 0x50, 0x4E, 0x47],
          ),
        ],
        boundary: 'THEBOUND',
      );
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);

      await client.post<Uint8List>(
        Uri.parse('https://x.test/upload'),
        data: mp,
      );

      final sent = transport.sent.single;
      expect(sent.body, mp.render());
      expect(
        sent.headers['content-type'],
        'multipart/form-data; boundary=THEBOUND',
      );
      client.dispose();
    });

    test('does not override an explicit Content-Type', () async {
      final mp = Multipart(
        [MultipartField('f', 'v')],
        [],
        boundary: 'B',
      );
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);

      await client.post<Uint8List>(
        Uri.parse('https://x.test'),
        data: mp,
        options: const RequestOptions(
          headers: {'content-type': 'application/json'},
        ),
      );

      expect(
        transport.sent.single.headers['content-type'],
        'application/json',
      );
      client.dispose();
    });
  });
}
