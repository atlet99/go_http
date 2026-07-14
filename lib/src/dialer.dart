import 'dart:async';
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

/// Happy Eyeballs (RFC 8305) dual-stack TCP dialer.
///
/// Resolves [host] to both IPv6 and IPv4 addresses, races them:
/// - IPv6 connections start immediately (300ms head start).
/// - IPv4 connections start after [ipv6Delay].
/// - First successful connection wins; losers are destroyed.
/// - If all attempts fail, propagates the last error.
///
/// ponytail: no early fallback on v6-all-fail before delay.
/// Add when per-connection latency stats make the 300ms UX gap visible.
class HappyEyeballDialer implements Dialer {
  const HappyEyeballDialer({
    this.ipv6Delay = const Duration(milliseconds: 300),
    this.dnsTimeout = const Duration(seconds: 10),
  });

  /// Head start for IPv6 connections before IPv4 begins.
  final Duration ipv6Delay;

  /// Timeout for the DNS resolution step.
  final Duration dnsTimeout;

  @override
  Future<Socket> dial(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    final addresses = await InternetAddress.lookup(host).timeout(dnsTimeout);

    final v6 = <InternetAddress>[];
    final v4 = <InternetAddress>[];
    for (final addr in addresses) {
      if (addr.type == InternetAddressType.IPv6) {
        v6.add(addr);
      } else if (addr.type == InternetAddressType.IPv4) {
        v4.add(addr);
      }
    }

    if (v6.isEmpty && v4.isEmpty) {
      throw SocketException('No IP addresses resolved for $host');
    }

    final completer = Completer<Socket>();
    var winner = false;
    var failures = 0;
    final total = v6.length + v4.length;

    void tryConnect(InternetAddress addr) {
      if (winner) {
        return;
      }
      Socket.connect(addr, port, timeout: timeout).then((socket) {
        if (winner) {
          socket.destroy();
          return;
        }
        winner = true;
        completer.complete(socket);
      }).catchError((Object e) {
        if (winner) {
          return;
        }
        failures++;
        if (failures >= total) {
          completer.completeError(
            e is SocketException ? e : SocketException('$e'),
          );
        }
      });
    }

    for (final addr in v6) {
      tryConnect(addr);
    }

    if (v4.isNotEmpty) {
      Future.delayed(v6.isEmpty ? Duration.zero : ipv6Delay, () {
        for (final addr in v4) {
          tryConnect(addr);
        }
      });
    }

    return completer.future;
  }
}
