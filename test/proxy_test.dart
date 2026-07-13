import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('Proxy', () {
    test('direct parses to DIRECT', () {
      final p = Proxy.parse('direct://');
      expect(p.isDirect, isTrue);
      expect(p.findProxyUrl, 'DIRECT');
      expect(p.toString(), 'Proxy.direct');
    });

    test('http proxy yields PROXY directive', () {
      final p = Proxy.parse('http://proxy:8080');
      expect(p.scheme, 'http');
      expect(p.authority, 'proxy:8080');
      expect(p.findProxyUrl, 'PROXY proxy:8080');
    });

    test('https proxy yields CONNECT directive', () {
      final p = Proxy.parse('https://proxy:443');
      expect(p.findProxyUrl, 'CONNECT proxy:443');
    });

    test('extracts and masks credentials', () {
      final p = Proxy.parse('http://user:secret@proxy:8080');
      expect(p.username, 'user');
      expect(p.password, 'secret');
      expect(p.toString(), contains('user:***@'));
      expect(p.toString(), isNot(contains('secret')));
    });

    test('rejects unsupported scheme', () {
      expect(
        () => Proxy.parse('ftp://x'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('socks5 is parsed but unsupported by native transport', () {
      final p = Proxy.parse('socks5://h:1080');
      expect(
        () => p.findProxyUrl,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('URLPattern', () {
    test('all:// matches any uri', () {
      final p = URLPattern.parse('all://');
      expect(p.matches(Uri.parse('http://a.com')), isTrue);
      expect(p.matches(Uri.parse('https://b.com:1')), isTrue);
    });

    test('wildcard host matches subdomains', () {
      final p = URLPattern.parse('https://*.internal');
      expect(p.matches(Uri.parse('https://api.internal')), isTrue);
      expect(p.matches(Uri.parse('https://a.b.internal')), isTrue);
      expect(p.matches(Uri.parse('https://other.com')), isFalse);
      expect(p.matches(Uri.parse('http://x.internal')), isFalse);
    });

    test('port and scheme constrain matching', () {
      final p = URLPattern.parse('http://ex.com:8080');
      expect(p.matches(Uri.parse('http://ex.com:8080')), isTrue);
      expect(p.matches(Uri.parse('http://ex.com:9090')), isFalse);
      expect(p.matches(Uri.parse('https://ex.com:8080')), isFalse);
    });

    test('specificity: port > host-length > scheme', () {
      final all = URLPattern.parse('all://');
      final host = URLPattern.parse('https://*.internal');
      final port = URLPattern.parse('https://api.internal:443');
      expect(port.specificity, greaterThan(host.specificity));
      expect(host.specificity, greaterThan(all.specificity));
    });
  });

  group('ProxyMounts', () {
    test('returns most-specific matching proxy', () {
      final mounts = ProxyMounts({
        URLPattern.parse('all://'): Proxy.parse('http://fallback:1'),
        URLPattern.parse('https://*.internal'): Proxy.parse('http://inner:2'),
        URLPattern.parse('https://api.internal:443'):
            Proxy.parse('http://exact:3'),
      });
      final p = mounts.findProxy(Uri.parse('https://api.internal:443'));
      expect(p?.authority, 'exact:3');
    });

    test('null value means explicitly direct', () {
      final mounts = ProxyMounts({
        URLPattern.parse('all://'): null,
      });
      expect(mounts.findProxy(Uri.parse('http://x.com')), isNull);
    });

    test('no match returns null (falls through)', () {
      final mounts = ProxyMounts({
        URLPattern.parse('https://*.internal'): Proxy.parse('http://inner:2'),
      });
      expect(
        mounts.findProxy(Uri.parse('http://public.com')),
        isNull,
      );
    });
  });
}
