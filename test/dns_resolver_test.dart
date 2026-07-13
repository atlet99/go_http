import 'dart:io';
import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

/// Fake DNS resolver for testing.
/// Returns [InternetAddress] for all hosts except [errorHost].
class _FakeDnsResolver implements DnsResolver {
  _FakeDnsResolver({this.errorHost}) : _callCount = 0;
  final String? errorHost;
  int _callCount = 0;

  int get callCount => _callCount;

  @override
  Future<InternetAddress> lookup(String host) async {
    _callCount++;
    if (host == errorHost) {
      throw DnsLookupError(host, 'simulated failure');
    }
    return InternetAddress(
      '93.184.216.34',
      type: InternetAddressType.IPv4,
    );
  }

  @override
  void clearCache() {}
}

void main() {
  group('CachedDnsResolver', () {
    late _FakeDnsResolver inner;
    late CachedDnsResolver resolver;

    setUp(() {
      inner = _FakeDnsResolver();
      resolver = CachedDnsResolver(inner: inner, defaultTtlSeconds: 300);
    });

    test('returns address for a host', () async {
      final addr = await resolver.lookup('example.com');
      expect(addr.address, '93.184.216.34');
    });

    test('caches result — inner called once for same host', () async {
      await resolver.lookup('example.com');
      await resolver.lookup('example.com');
      expect(inner.callCount, 1);
    });

    test('misses cache for different hosts', () async {
      await resolver.lookup('example.com');
      try {
        await resolver.lookup('other.com');
      } catch (_) {}
      expect(inner.callCount, 2);
    });

    test('re-resolves after TTL expiry', () async {
      resolver = CachedDnsResolver(
        inner: inner,
        defaultTtlSeconds: 0,
      );
      await resolver.lookup('example.com');
      await resolver.lookup('example.com');
      expect(inner.callCount, 2);
    });

    test('negative cache re-throws without recalling inner', () async {
      inner = _FakeDnsResolver(errorHost: 'bad.host');
      resolver = CachedDnsResolver(inner: inner, negativeTtlSeconds: 60);

      await expectLater(
        resolver.lookup('bad.host'),
        throwsA(isA<DnsLookupError>()),
      );
      await expectLater(
        resolver.lookup('bad.host'),
        throwsA(isA<DnsLookupError>()),
      );
      expect(inner.callCount, 1);
    });

    test('clearCache removes entries', () async {
      await resolver.lookup('example.com');
      resolver.clearCache();
      await resolver.lookup('example.com');
      expect(inner.callCount, 2);
    });

    test('evicts oldest entries when cache exceeds maxSize', () async {
      resolver = CachedDnsResolver(
        inner: inner,
        maxCacheSize: 2,
        defaultTtlSeconds: 3600,
      );

      await resolver.lookup('host-a.com');
      await resolver.lookup('host-b.com');
      await resolver.lookup('host-c.com'); // triggers eviction

      expect(resolver.cacheSize, lessThanOrEqualTo(2));
    });

    test('expiredCount returns correct count', () async {
      resolver = CachedDnsResolver(
        inner: inner,
        defaultTtlSeconds: 0,
      );
      await resolver.lookup('example.com');
      expect(resolver.expiredCount, 1);
    });

    test('cacheSize returns current entry count', () async {
      await resolver.lookup('a.com');
      await resolver.lookup('b.com');
      expect(resolver.cacheSize, 2);
    });
  });

  group('SystemDnsResolver', () {
    test('resolves localhost', () async {
      final resolver = SystemDnsResolver();
      final addr = await resolver.lookup('localhost');
      expect(addr.address, isNotNull);
    });

    test('throws DnsLookupError for unknown host', () async {
      final resolver = SystemDnsResolver();
      await expectLater(
        resolver.lookup('nonexistent.example.invalid'),
        throwsA(isA<DnsLookupError>()),
      );
    });
  });
}
