import 'package:go_http/go_http.dart';

Future<void> main() async {
  // HappyEyeballDialer resolves hostname to all IPv6 + IPv4 addresses,
  // starts IPv6 connections immediately and IPv4 after 300ms delay.
  // The first successful connection wins; losers are destroyed.
  final dialer = const HappyEyeballDialer();

  try {
    final socket = await dialer.dial(
      'example.com',
      80,
      timeout: const Duration(seconds: 10),
    );

    print('Connected to ${socket.remoteAddress.address}');
    print(
      'Address family: ${socket.remoteAddress.type}', // InternetAddressType.IPv6 or .IPv4
    );

    socket.destroy();
  } catch (e) {
    print('Connection failed: $e');
  }
}
