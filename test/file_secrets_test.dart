import 'dart:convert';
import 'dart:io';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('FileSecrets', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('go_http_secrets_');
    });

    tearDown(() {
      tmp.deleteSync(recursive: true);
    });

    Future<String> writeJson(Map<String, dynamic> data) async {
      final f = File('${tmp.path}/secrets.json');
      await f.writeAsString(json.encode(data));
      return f.path;
    }

    test('basicAuth loads username and password', () async {
      final path = await writeJson({
        'username': 'alice',
        'password': 'secret123',
      });
      final auth = await FileSecrets.basicAuth(path);
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('http://example.com'),
      );
      final result = auth.apply(req);
      expect(
        result.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('alice:secret123'))}',
      );
    });

    test('basicAuth with section', () async {
      final path = await writeJson({
        'prod': {'username': 'admin', 'password': 'hunter2'},
      });
      final auth = await FileSecrets.basicAuth(path, section: 'prod');
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('http://example.com'),
      );
      final result = auth.apply(req);
      expect(
        result.headers['authorization'],
        'Basic ${base64.encode(utf8.encode('admin:hunter2'))}',
      );
    });

    test('basicAuth throws when file missing', () async {
      await expectLater(
        FileSecrets.basicAuth('/nonexistent/secrets.json'),
        throwsA(isA<FileSecretsError>()),
      );
    });

    test('basicAuth throws when keys missing', () async {
      final path = await writeJson({'foo': 'bar'});
      await expectLater(
        FileSecrets.basicAuth(path),
        throwsA(isA<FileSecretsError>()),
      );
    });

    test('bearerToken loads and creates header', () async {
      final path = await writeJson({'token': 'eyJhbGci'});
      final auth = await FileSecrets.bearerToken(path);
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('http://example.com'),
      );
      final result = auth.apply(req);
      expect(result.headers['authorization'], 'Bearer eyJhbGci');
    });

    test('bearerToken with custom header name', () async {
      final path = await writeJson({'token': 'x-custom-token'});
      final auth = await FileSecrets.bearerToken(
        path,
        headerName: 'x-api-key',
        headerPrefix: '',
      );
      final req = Request(
        method: HttpMethod.get,
        uri: Uri.parse('http://example.com'),
      );
      final result = auth.apply(req);
      expect(result.headers['x-api-key'], 'x-custom-token');
    });

    test('bearerToken throws when token missing in section', () async {
      final path = await writeJson({
        'dev': {'foo': 'bar'},
      });
      await expectLater(
        FileSecrets.bearerToken(path, section: 'dev'),
        throwsA(isA<FileSecretsError>()),
      );
    });

    test('throws on invalid JSON', () async {
      final f = File('${tmp.path}/bad.json');
      await f.writeAsString('not json');
      await expectLater(
        FileSecrets.basicAuth(f.path),
        throwsA(isA<FileSecretsError>()),
      );
    });

    test('throws when section not found', () async {
      final path = await writeJson({'a': 1});
      await expectLater(
        FileSecrets.bearerToken(path, section: 'missing'),
        throwsA(isA<FileSecretsError>()),
      );
    });
  });
}
