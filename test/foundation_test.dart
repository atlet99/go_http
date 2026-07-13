import 'dart:convert';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart' hide Timeout;

import 'fake_transport.dart';

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
      expect(() => res.raiseForStatus(), throwsA(isA<HttpStatusError>()));
    });

    test('header lookups are case-insensitive', () {
      final res = responseWith(
        headers: {'CoNtEnT-TyPe': 'text/plain; charset=latin1'},
      );
      expect(res.charsetEncoding, 'latin1');
    });

    test('text strips UTF-8 BOM', () {
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('abc')]);
      expect(responseWith(data: bom).text, 'abc');
    });

    test('text decodes cp1251', () {
      // cp1251 bytes for "Привет"
      final bytes = Uint8List.fromList([
        0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2,
      ]);
      final res = responseWith(data: bytes);
      res.encoding = 'cp1251';
      expect(res.text, 'Привет');
    });

    test('text decodes koi8-r', () {
      // KOI8-R bytes for "Привет"
      final bytes = Uint8List.fromList([
        0xF0, 0xD2, 0xC9, 0xD7, 0xC5, 0xD4,
      ]);
      final res = responseWith(data: bytes);
      res.encoding = 'koi8-r';
      expect(res.text, 'Привет');
    });
  });

  group('Headers', () {
    test('case-insensitive lookup and []= replace', () {
      final h = Headers({'Content-Type': 'a'});
      expect(h['content-type'], 'a');
      h['CONTENT-TYPE'] = 'b';
      expect(h['content-type'], 'b');
      expect(h.length, 1);
    });

    test('add appends a value; getAll returns each', () {
      final h = Headers();
      h.add('Set-Cookie', 'a=1');
      h.add('Set-Cookie', 'b=2');
      expect(h.getAll('set-cookie'), ['a=1', 'b=2']);
      expect(h['set-cookie'], 'a=1, b=2');
      expect(h.length, 1);
    });

    test('multiItems yields every value in order', () {
      final h = Headers()
        ..add('x', '1')
        ..add('x', '2')
        ..add('y', '3');
      expect(h.multiItems.map((e) => e.value).toList(), ['1', '2', '3']);
    });

    test('merge replaces same-named keys, keeps others', () {
      final merged = Headers({'a': '1', 'b': '2'}).merge({'a': '9'});
      expect(merged['a'], '9');
      expect(merged['b'], '2');
    });

    test('sensitive headers are obfuscated in toString', () {
      final h = Headers({'Authorization': 'secret', 'X-Other': 'v'});
      expect(h.toString(), contains('[secure]'));
      expect(h.toString(), isNot(contains('secret')));
    });
  });

  group('ClientConfig', () {
    test('defaults carries sensible defaults', () {
      expect(ClientConfig.defaults.connectTimeout, const Duration(seconds: 10));
      expect(ClientConfig.defaults.sendTimeout, const Duration(seconds: 30));
      expect(ClientConfig.defaults.receiveTimeout, const Duration(seconds: 30));
      expect(ClientConfig.defaults.followRedirects, isTrue);
      expect(ClientConfig.defaults.maxRedirects, 5);
      expect(ClientConfig.defaults.autoDecompress, isTrue);
      expect(ClientConfig.defaults.maxAuthRetries, 1);
      expect(ClientConfig.defaults.trustEnv, isTrue);
      expect(
        ClientConfig.defaults.defaultHeaders['accept-encoding'],
        'gzip, deflate, br',
      );
    });

    test('validate returns empty for defaults', () {
      expect(ClientConfig.defaults.validate(), isEmpty);
    });

    test('validate catches negative maxRedirects', () {
      const cfg = ClientConfig(maxRedirects: -1);
      final errors = cfg.validate();
      expect(errors.any((e) => e.field == 'maxRedirects'), isTrue);
    });

    test('validate catches zero connectTimeout', () {
      const cfg = ClientConfig(connectTimeout: Duration.zero);
      final errors = cfg.validate();
      expect(errors.any((e) => e.field == 'connectTimeout'), isTrue);
    });

    test('const can be created with overrides', () {
      const cfg = ClientConfig(followRedirects: false, maxRedirects: 0);
      expect(cfg.followRedirects, isFalse);
      expect(cfg.maxRedirects, 0);
    });
  });

  group('ExecutorConfig', () {
    test('defaults has no interceptors', () {
      expect(ExecutorConfig.defaults.interceptors, isEmpty);
    });

    test('defaults validate returns empty', () {
      expect(ExecutorConfig.defaults.validate(), isEmpty);
    });

    test('const with interceptors', () {
      final counter = CountingInterceptor();
      const cfg = ExecutorConfig();
      expect(cfg.interceptors, isEmpty);
      final cfg2 = ExecutorConfig(interceptors: [counter]);
      expect(cfg2.interceptors.length, 1);
    });
  });

  group('GoHttpClient config wiring', () {
    test('clientConfig is used as base configuration', () async {
      const cfg = ClientConfig(
        connectTimeout: Duration(seconds: 2),
        sendTimeout: Duration(seconds: 3),
      );
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(clientConfig: cfg, transport: transport);
      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      client.dispose();
    });

    test('individual params override clientConfig', () async {
      const cfg = ClientConfig(followRedirects: false);
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(
        clientConfig: cfg,
        transport: transport,
        followRedirects: true,
      );
      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.statusCode, 200);
      client.dispose();
    });

    test('executorConfig provides interceptors', () async {
      final counter = CountingInterceptor();
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(
        executorConfig: ExecutorConfig(interceptors: [counter]),
        transport: transport,
      );
      await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(counter.onRequestCount, 1);
      client.dispose();
    });

    test('GoHttpClient.defaults() creates a client without throwing', () {
      expect(() => GoHttpClient.defaults(), isNot(throwsA(anything)));
    });
  });
}
