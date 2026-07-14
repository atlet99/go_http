import 'dart:io';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('HappyEyeballDialer', () {
    test('ipv4-fallback', () async {
      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = server.port;
      addTearDown(() => server.close());

      final dialer = const HappyEyeballDialer(
        ipv6Delay: Duration(milliseconds: 100),
        dnsTimeout: Duration(seconds: 5),
      );

      final socket = await dialer.dial(
        'localhost',
        port,
        timeout: const Duration(seconds: 10),
      );

      expect(
        socket.remoteAddress.type,
        InternetAddressType.IPv4,
      );
      await socket.close();
    });

    test('dns-resolution-failure', () async {
      final dialer = const HappyEyeballDialer(
        ipv6Delay: Duration.zero,
        dnsTimeout: Duration(seconds: 3),
      );

      await expectLater(
        dialer.dial(
          'nonexistent-host-12345.invalid.',
          80,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('connection-refused', () async {
      final probe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = probe.port;
      await probe.close();

      final dialer = const HappyEyeballDialer(
        ipv6Delay: Duration.zero,
        dnsTimeout: Duration(seconds: 5),
      );

      await expectLater(
        dialer.dial(
          'localhost',
          port,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
