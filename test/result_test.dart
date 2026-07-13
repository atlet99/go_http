import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('Result', () {
    test('ok carries the response, fail carries the error', () {
      final resp = Response<Uint8List>(
        request: Request(
          method: HttpMethod.get,
          uri: Uri.parse('https://x.test/'),
        ),
        statusCode: 200,
        headers: Headers(const {}),
        data: null,
      );
      final ok = Result.ok(resp);
      expect(ok.isOk, isTrue);
      expect(ok.isError, isFalse);
      expect(ok.response.statusCode, 200);

      final fail = Result.fail('boom');
      expect(fail.isError, isTrue);
      expect(fail.error, 'boom');
      expect(() => fail.response, throwsStateError);
    });
  });

  group('ResultSink', () {
    test('jsonl writes one JSON object per line', () async {
      final file = File(
        '${Directory.systemTemp.path}/go_http_jsonl_${DateTime.now().microsecondsSinceEpoch}.jsonl',
      );
      final sink = ResultSink.jsonl(file.path);
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);
      final resp = await client.get<Uint8List>(Uri.parse('https://x.test/'));
      sink.write(Result.ok(resp));
      sink.write(Result.fail('nope'));
      await sink.close();
      client.dispose();

      final lines = file.readAsLinesSync();
      expect(lines, hasLength(2));
      expect(jsonDecode(lines.first)['ok'], isTrue);
      expect(jsonDecode(lines[1])['ok'], isFalse);
      expect(jsonDecode(lines[1])['error'], 'nope');
      file.deleteSync();
    });

    test('csv sanitizes formula-injection cells', () async {
      final file = File(
        '${Directory.systemTemp.path}/go_http_csv_${DateTime.now().microsecondsSinceEpoch}.csv',
      );
      final sink = ResultSink.csv(file.path);
      sink.write(Result.fail('=cmd|/C evil'));
      await sink.close();

      final lines = file.readAsLinesSync();
      expect(lines.first, 'ok,url,status,error');
      expect(lines[1], contains("'=cmd|/C evil"));
      file.deleteSync();
    });

    test('two-phase write creates temp file and renames on close', () async {
      final path =
          '${Directory.systemTemp.path}/go_http_twophase_${DateTime.now().microsecondsSinceEpoch}.jsonl';
      final sink = ResultSink.jsonl(path);
      final r = Response(
        request: Request(
          method: HttpMethod.get,
          uri: Uri.parse('https://x.test'),
        ),
        statusCode: 200,
      );
      sink.write(Result.ok(r));
      // Before close: temp file exists, target does not
      expect(File('$path.tmp').existsSync(), isTrue);
      expect(File(path).existsSync(), isFalse);
      await sink.close();
      // After close: target exists, temp is gone
      expect(File('$path.tmp').existsSync(), isFalse);
      expect(File(path).existsSync(), isTrue);
      File(path).deleteSync();
    });
  });
}
