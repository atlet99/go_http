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

  Response responseWith(String setCookieHeader) {
    return Response(
      request: request,
      statusCode: 200,
      headers: {'set-cookie': setCookieHeader},
      data: null,
    );
  }

  test('stores and returns a simple cookie', () {
    store.setCookies(responseWith('session=abc; Path=/'));
    expect(store.getCookies(request.uri), contains('session=abc'));
  });

  test('handles multiple Set-Cookie headers separately', () {
    // Two cookies, one of them with an Expires field containing a comma.
    store.setCookies(
      responseWith(
        'session=abc; Path=/\n'
        'tracker=xyz; Expires=Wed, 21 Oct 2025 07:28:00 GMT; Path=/',
      ),
    );
    final cookies = store.getCookies(request.uri);
    expect(cookies, contains('session=abc'));
    expect(cookies, contains('tracker=xyz'));
  });

  test('does not split cookies on the comma inside Expires', () {
    store.setCookies(
      responseWith('a=1; Expires=Wed, 21 Oct 2025 07:28:00 GMT'),
    );
    final cookies = store.getCookies(request.uri);
    expect(cookies.length, 1);
    expect(cookies.first, startsWith('a=1'));
  });

  test('shares cookies with subdomains when Domain attribute is set', () {
    store.setCookies(
      Response(
        request: Request(
          method: HttpMethod.get,
          uri: Uri.parse('https://login.example.com'),
        ),
        statusCode: 200,
        headers: {'set-cookie': 'id=42; Domain=example.com; Path=/'},
        data: null,
      ),
    );
    expect(
      store.getCookies(Uri.parse('https://api.example.com')),
      contains('id=42'),
    );
  });

  test('clear and clearDomain', () {
    store.setCookies(responseWith('x=1; Path=/'));
    expect(store.getCookies(request.uri), isNotEmpty);
    store.clearDomain('api.example.com');
    expect(store.getCookies(request.uri), isEmpty);
  });
}
