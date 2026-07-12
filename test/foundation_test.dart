import 'dart:convert';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart' hide Timeout;

void main() {
  group('Timeout', () {
    test('all() sets every phase to the same duration', () {
      const t = Timeout.all(Duration(seconds: 5));
      expect(t.connect, const Duration(seconds: 5));
      expect(t.read, const Duration(seconds: 5));
      expect(t.write, const Duration(seconds: 5));
      expect(t.pool, const Duration(seconds: 5));
    });

    test('disabled() nulls every phase and isDisabled is true', () {
      const t = Timeout.disabled();
      expect(t.connect, isNull);
      expect(t.read, isNull);
      expect(t.write, isNull);
      expect(t.pool, isNull);
      expect(t.isDisabled, isTrue);
    });

    test('named phases are independent', () {
      const t =
          Timeout(connect: Duration(seconds: 1), read: Duration(seconds: 2));
      expect(t.write, isNull);
      expect(t.pool, isNull);
      expect(t.isDisabled, isFalse);
    });

    test('merge lets other win for non-null fields', () {
      const base = Timeout.all(Duration(seconds: 5));
      const override = Timeout(connect: Duration(seconds: 1));
      final merged = base.merge(override);
      expect(merged.connect, const Duration(seconds: 1));
      expect(merged.read, const Duration(seconds: 5));
    });
  });

  group('StatusCode', () {
    test('carries code and phrase', () {
      expect(StatusCode.ok.code, 200);
      expect(StatusCode.ok.phrase, 'OK');
      expect(StatusCode.notFound.code, 404);
      expect(StatusCode.notFound.phrase, 'Not Found');
    });

    test('category predicates', () {
      expect(StatusCode.ok.isSuccess, isTrue);
      expect(StatusCode.ok.isError, isFalse);
      expect(StatusCode.notFound.isClientError, isTrue);
    });

    test('hasRedirectLocation only for navigable redirects', () {
      expect(StatusCode.movedPermanently.hasRedirectLocation, isTrue);
      expect(StatusCode.found.hasRedirectLocation, isTrue);
      expect(StatusCode.notModified.hasRedirectLocation, isFalse);
    });

    test('fromCode returns member or null', () {
      expect(StatusCode.fromCode(200), StatusCode.ok);
      expect(StatusCode.fromCode(599), isNull);
    });
  });

  group('MockTransport', () {
    test('invokes the handler and records calls', () async {
      final transport = MockTransport((request) async {
        return Response(
          request: request,
          statusCode: 201,
          data: Uint8List.fromList([9]),
        );
      });

      final client = GoHttpClient(transport: transport);
      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));

      expect(res.statusCode, 201);
      expect(res.data, [9]);
      expect(transport.callCount, 1);
      expect(transport.sent.single.method, HttpMethod.get);
      client.dispose();
    });
  });

  group('Response enrichment', () {
    Response<Uint8List> responseWith({
      int status = 200,
      Uint8List? data,
      Map<String, String>? headers,
    }) {
      return Response<Uint8List>(
        request: Request(
          method: HttpMethod.get,
          uri: Uri.parse('https://x.test'),
        ),
        statusCode: status,
        headers: headers ?? const {},
        data: data ?? Uint8List(0),
      );
    }

    test('text decodes utf-8 body', () {
      final res = responseWith(
        data: Uint8List.fromList(utf8.encode('hello — привет')),
      );
      expect(res.text, 'hello — привет');
    });

    test('json() decodes a JSON body', () {
      final res = responseWith(
        data: Uint8List.fromList(utf8.encode('{"k": 42}')),
      );
      expect((res.json() as Map<String, dynamic>)['k'], 42);
    });

    test('encoding derived from Content-Type charset', () {
      final res = responseWith(
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
      expect(res.charsetEncoding, 'utf-8');
      expect(res.encoding, 'utf-8');
    });

    test('encoding falls back to utf-8 without charset', () {
      final res = responseWith();
      expect(res.charsetEncoding, isNull);
      expect(res.encoding, 'utf-8');
    });

    test('encoding can be overridden', () {
      final res = responseWith();
      res.encoding = 'iso-8859-1';
      expect(res.encoding, 'iso-8859-1');
    });

    test('isError covers 4xx and 5xx', () {
      expect(responseWith(status: 404).isError, isTrue);
      expect(responseWith(status: 500).isError, isTrue);
      expect(responseWith(status: 200).isError, isFalse);
    });

    test('hasRedirectLocation requires Location header', () {
      expect(
        responseWith(status: 301, headers: {'Location': '/x'})
            .hasRedirectLocation,
        isTrue,
      );
      expect(
        responseWith(status: 301).hasRedirectLocation,
        isFalse,
      );
      expect(
        responseWith(status: 304).hasRedirectLocation,
        isFalse,
      );
    });

    test('raiseForStatus returns self on success', () {
      final res = responseWith(status: 200);
      expect(res.raiseForStatus(), same(res));
    });

    test('raiseForStatus throws on 4xx', () {
      final res = responseWith(status: 404);
      expect(() => res.raiseForStatus(), throwsA(isA<HttpResponseError>()));
    });

    test('header lookups are case-insensitive', () {
      final res = responseWith(
        headers: {'CoNtEnT-TyPe': 'text/plain; charset=latin1'},
      );
      expect(res.charsetEncoding, 'latin1');
    });
  });
}
