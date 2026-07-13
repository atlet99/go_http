import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  late MemoryCookieStore store;
  late Request request;

  setUp(() {
    store = MemoryCookieStore();
    request = Request(
      method: HttpMethod.get,
      uri: Uri.parse('https://api.example.com/path'),
    );
  });

  Response responseWith(List<String> setCookies, {Uri? requestUri}) {
    final headers = Headers();
    for (final c in setCookies) {
      headers.add('set-cookie', c);
    }
    return Response(
      request: Request(
        method: HttpMethod.get,
        uri: requestUri ?? request.uri,
      ),
      statusCode: 200,
      headers: headers,
      data: null,
    );
  }

  test('stores and returns a simple cookie', () {
    store.setCookies(responseWith(['session=abc; Path=/']));
    expect(store.getCookies(request.uri), contains('session=abc'));
  });

  test('handles multiple Set-Cookie headers separately', () {
    store.setCookies(
      responseWith([
        'session=abc; Path=/',
        'tracker=xyz; Expires=Wed, 21 Oct 2037 07:28:00 GMT; Path=/',
      ]),
    );
    final cookies = store.getCookies(request.uri);
    expect(cookies, contains('session=abc'));
    expect(cookies, contains('tracker=xyz'));
  });

  test('does not split cookies on the comma inside Expires', () {
    store.setCookies(
      responseWith(['a=1; Expires=Wed, 21 Oct 2037 07:28:00 GMT']),
    );
    final cookies = store.getCookies(request.uri);
    expect(cookies.length, 1);
    expect(cookies.first, startsWith('a=1'));
  });

  test('shares cookies with subdomains when Domain attribute is set', () {
    store.setCookies(
      responseWith(
        ['id=42; Domain=example.com; Path=/'],
        requestUri: Uri.parse('https://login.example.com'),
      ),
    );
    expect(
      store.getCookies(Uri.parse('https://api.example.com')),
      contains('id=42'),
    );
  });

  test('clear and clearDomain', () {
    store.setCookies(responseWith(['x=1; Path=/']));
    expect(store.getCookies(request.uri), isNotEmpty);
    store.clearDomain('api.example.com');
    expect(store.getCookies(request.uri), isEmpty);
  });

  // --- RFC 6265 compliance tests ---

  test('Path matching: cookie only returned for matching path', () {
    store.setCookies(responseWith(['x=1; Path=/api']));
    expect(
      store.getCookies(Uri.parse('https://api.example.com/api')),
      contains('x=1'),
    );
    expect(
      store.getCookies(Uri.parse('https://api.example.com/api/v1')),
      contains('x=1'),
    );
    expect(
      store.getCookies(Uri.parse('https://api.example.com/other')),
      isEmpty,
    );
  });

  test('Path matching: root path matches everything', () {
    store.setCookies(responseWith(['x=1; Path=/']));
    expect(
      store.getCookies(Uri.parse('https://api.example.com/any/path')),
      contains('x=1'),
    );
  });

  test('Secure cookie not sent over HTTP', () {
    store.setCookies(responseWith(['x=1; Secure; Path=/']));
    expect(
      store.getCookies(Uri.parse('https://api.example.com/')),
      contains('x=1'),
    );
    expect(
      store.getCookies(Uri.parse('http://api.example.com/')),
      isEmpty,
    );
  });

  test('Expired cookie not returned', () {
    store.setCookies(
      responseWith(['x=1; Expires=Mon, 01 Jan 2020 00:00:00 GMT; Path=/']),
    );
    expect(store.getCookies(request.uri), isEmpty);
  });

  test('Max-Age cookie expired', () {
    store.setCookies(responseWith(['x=1; Max-Age=0; Path=/']));
    expect(store.getCookies(request.uri), isEmpty);
  });

  test('Max-Age future cookie is returned', () {
    store.setCookies(responseWith(['x=1; Max-Age=3600; Path=/']));
    expect(store.getCookies(request.uri), contains('x=1'));
  });

  test('removes old cookie on re-set with same name/domain/path', () {
    store.setCookies(responseWith(['x=old; Path=/']));
    store.setCookies(responseWith(['x=new; Path=/']));
    final cookies = store.getCookies(request.uri);
    expect(cookies, contains('x=new'));
    expect(cookies, isNot(contains('x=old')));
  });

  test('most specific path wins', () {
    store.setCookies(responseWith(['x=root; Path=/']));
    store.setCookies(responseWith(['x=api; Path=/api']));
    expect(
      store.getCookies(Uri.parse('https://api.example.com/api')),
      orderedEquals(['x=api', 'x=root']),
    );
  });

  test('DefaultPath is directory of request URI', () {
    store.setCookies(
      responseWith(
        ['x=1'],
        requestUri: Uri.parse('https://example.com/a/b/c'),
      ),
    );
    expect(
      store.getCookies(Uri.parse('https://example.com/a/b/d')),
      contains('x=1'),
    );
    expect(
      store.getCookies(Uri.parse('https://example.com/a/')),
      isEmpty,
    );
  });

  test('Domain matching: exact', () {
    store.setCookies(
      responseWith(
        ['x=1; Domain=example.com; Path=/'],
        requestUri: Uri.parse('https://sub.example.com'),
      ),
    );
    expect(
      store.getCookies(Uri.parse('https://example.com/')),
      contains('x=1'),
    );
    expect(
      store.getCookies(Uri.parse('https://other.com/')),
      isEmpty,
    );
  });

  test('count', () {
    expect(store.count, 0);
    store.setCookies(responseWith(['a=1; Path=/', 'b=2; Path=/']));
    expect(store.count, 2);
  });
}
