import 'dart:typed_data';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

import 'fake_transport.dart';

void main() {
  group('ResponseEnrichment', () {
    test('has null timing and tlsInfo by default', () {
      final e = const ResponseEnrichment();
      expect(e.timing, isNull);
      expect(e.tlsInfo, isNull);
    });

    test('carries timing data when provided', () {
      final now = DateTime.now();
      final timing = ResponseTiming(
        dnsStart: now,
        dnsDone: now.add(const Duration(milliseconds: 10)),
        wroteRequest: now.add(const Duration(milliseconds: 20)),
        gotFirstResponseByte: now.add(const Duration(milliseconds: 50)),
      );
      final e = ResponseEnrichment(timing: timing);
      expect(e.timing?.dnsStart, now);
      expect(e.timing?.wroteRequest, now.add(const Duration(milliseconds: 20)));
      expect(
        e.timing?.gotFirstResponseByte,
        now.add(const Duration(milliseconds: 50)),
      );
      expect(e.timing?.connectStart, isNull);
    });

    test('TlsInfo carries handshake details', () {
      const tls = TlsInfo(
        version: 'TLSv1.3',
        cipherSuite: 'TLS_AES_256_GCM_SHA384',
        handshakeDuration: Duration(milliseconds: 15),
      );
      expect(tls.version, 'TLSv1.3');
      expect(tls.cipherSuite, 'TLS_AES_256_GCM_SHA384');
      expect(tls.handshakeDuration, const Duration(milliseconds: 15));
    });

    test('TlsInfo carries certificate fingerprints and flags', () {
      const tls = TlsInfo(
        fingerprintSha1: 'AA:BB:CC',
        fingerprintSha256: '11:22:33:44',
        isSelfSigned: true,
        isWildcard: true,
      );
      expect(tls.fingerprintSha1, 'AA:BB:CC');
      expect(tls.fingerprintSha256, '11:22:33:44');
      expect(tls.isSelfSigned, isTrue);
      expect(tls.isWildcard, isTrue);
    });

    test('Response enrichment field is null by default', () async {
      final transport = FakeTransport([
        ok(200, Uint8List.fromList([1, 2, 3])),
      ]);
      final client = GoHttpClient(transport: transport);
      final res = await client.get<Uint8List>(Uri.parse('https://x.test'));
      expect(res.enrichment, isA<ResponseEnrichment>());
      expect(res.enrichment?.timing, isNull);
      client.dispose();
    });

    test('remoteAddress is null by default', () async {
      final transport = FakeTransport([ok(200)]);
      final client = GoHttpClient(transport: transport);
      final res = await client.get(Uri.parse('https://x.test'));
      expect(res.enrichment?.remoteAddress, isNull);
      client.dispose();
    });

    test('remoteAddress flows from transport to enrichment', () async {
      final transport = FakeTransport([
        okWithAddr('10.0.0.1'),
      ]);
      final client = GoHttpClient(transport: transport);
      final res = await client.get(Uri.parse('https://x.test'));
      expect(res.enrichment?.remoteAddress, '10.0.0.1');
      client.dispose();
    });
  });
}
