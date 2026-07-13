import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('StatusCodeFilter', () {
    test('exact', () {
      final f = StatusCodeFilter.exact(200);
      expect(f.matches(resp(200)), isTrue);
      expect(f.matches(resp(404)), isFalse);
    });

    test('between', () {
      final f = StatusCodeFilter.between(200, 299);
      expect(f.matches(resp(200)), isTrue);
      expect(f.matches(resp(300)), isFalse);
    });

    test('above', () {
      final f = StatusCodeFilter.above(499);
      expect(f.matches(resp(500)), isTrue);
      expect(f.matches(resp(499)), isFalse);
    });

    test('below', () {
      final f = StatusCodeFilter.below(400);
      expect(f.matches(resp(200)), isTrue);
      expect(f.matches(resp(400)), isFalse);
    });
  });

  group('RegexFilter', () {
    test('matches body text', () {
      final f = RegexFilter(RegExp(r'admin'));
      expect(f.matches(resp(200, '{"role":"admin"}')), isTrue);
      expect(f.matches(resp(200, '{"role":"user"}')), isFalse);
    });
  });

  group('Match', () {
    test('any returns true if any filter matches', () {
      final f = Match.any([
        StatusCodeFilter.exact(200),
        StatusCodeFilter.exact(404),
      ]);
      expect(f.matches(resp(200)), isTrue);
      expect(f.matches(resp(500)), isFalse);
    });

    test('all returns true only if every filter matches', () {
      final f = Match.all([
        StatusCodeFilter.between(200, 299),
        RegexFilter(RegExp(r'ok')),
      ]);
      expect(f.matches(resp(200, 'ok')), isTrue);
      expect(f.matches(resp(200, 'nope')), isFalse);
      expect(f.matches(resp(500, 'ok')), isFalse);
    });

    test('empty filters returns false', () {
      expect(Match.any([]).matches(resp(200)), isFalse);
      expect(Match.all([]).matches(resp(200)), isFalse);
    });
  });
}

Response resp(int statusCode, [String? body]) {
  return Response(
    request: Request(method: HttpMethod.get, uri: Uri.parse('https://x.test')),
    statusCode: statusCode,
    data: body != null ? Uint8List.fromList(body.codeUnits) : null,
  );
}
