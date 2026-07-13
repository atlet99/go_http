import 'dart:io';

/// Pluggable socket dialer.
///
/// The default [SocketDialer] uses [Socket.connect]. Custom implementations
/// can provide virtual IP binding, DNS-over-HTTPS, connection pooling,
/// SOCKS proxying, or any other transport-layer logic.
///
/// ponytail: Defined for the type contract. Integration with [IoTransport]
/// requires a transport rewrite (dart:io HttpClient has no connection factory
/// hook in Dart 3.x).
abstract class Dialer {
  /// Open a TCP connection to [host]:[port].
  Future<Socket> dial(
    String host,
    int port, {
    Duration? timeout,
  });
}

/// Default [Dialer] using [Socket.connect].
class SocketDialer implements Dialer {
  @override
  Future<Socket> dial(
    String host,
    int port, {
    Duration? timeout,
  }) {
    return Socket.connect(host, port, timeout: timeout);
  }
}
