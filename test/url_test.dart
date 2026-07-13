import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('Url', () {
    test('lowercases scheme and host', () {
      final u = Url.parse('HTTPS://Example.COM/Path');
      expect(u.scheme, 'https');
      expect(u.host, 'example.com');
      expect(u.path, '/Path');
    });

    test('hides default port (:80 on http reads as null)', () {
      final u = Url.parse('http://example.com:80/');
      expect(u.port, isNull);
      expect(u.toString(), contains('http://example.com/'));
      expect(u.toString(), isNot(contains(':80')));
    });

    test('keeps non-default port', () {
      final u = Url.parse('https://example.com:8443/');
      expect(u.port, 8443);
      expect(u.toString(), contains(':8443'));
    });

    test('copyWith returns a new Url without mutating the original', () {
      final u = Url.parse('http://example.com/a');
      final v = u.copyWith(path: '/b', scheme: 'https');
      expect(u.path, '/a');
      expect(u.scheme, 'http');
      expect(v.path, '/b');
      expect(v.scheme, 'https');
      expect(v.host, 'example.com');
    });

    test('join resolves relative references (RFC 3986)', () {
      final base = Url.parse('http://example.com/api/v1/');
      expect(base.join('users').toString(), 'http://example.com/api/v1/users');
      final abs = base.join('http://other.com/x');
      expect(abs.host, 'other.com');
    });

    test('toString masks the password in userinfo', () {
      final u = Url.parse('https://user:secret@example.com/');
      final s = u.toString();
      expect(s, contains('user@example.com'));
      expect(s, isNot(contains('secret')));
    });

    test('query accessor returns a QueryParams view', () {
      final u = Url.parse('http://x/?a=1&a=2&b=3');
      expect(u.query.getList('a'), ['1', '2']);
      expect(u.query['b'], '3');
    });
  });

  group('QueryParams', () {
    test('is immutable: add/set/remove return new instances', () {
      final q = QueryParams({'a': '1'});
      final added = q.add('a', '2');
      expect(q.getList('a'), ['1']);
      expect(added.getList('a'), ['1', '2']);
      expect(q, isNot(same(added)));
    });

    test('set replaces all values for a key', () {
      final q = QueryParams({'a': '1'}).add('a', '2').set('a', '3');
      expect(q.getList('a'), ['3']);
    });

    test('remove drops the key', () {
      final q = QueryParams({'a': '1', 'b': '2'}).remove('a');
      expect(q.containsKey('a'), isFalse);
      expect(q['b'], '2');
    });

    test('merge keeps both values on shared keys', () {
      final q =
          QueryParams({'a': '1'}).merge(QueryParams({'a': '2', 'b': '3'}));
      expect(q.getList('a'), ['1', '2']);
      expect(q['b'], '3');
    });

    test('bool values render JSON-style', () {
      final q = QueryParams({'ok': 'true'}).add('flag', true);
      expect(q['flag'], 'true');
      expect(q.toQueryString(), contains('flag=true'));
    });

    test('toQueryString percent-encodes keys and values', () {
      final q = QueryParams({'a b': 'c&d'});
      expect(q.toQueryString(), 'a+b=c%26d');
    });

    test('round-trips through Uri via Url', () {
      final q = QueryParams({'x': '1'}).add('x', '2');
      final u = Url.parse('http://h/').copyWith(query: q);
      expect(u.query.getList('x'), ['1', '2']);
    });
  });
}
