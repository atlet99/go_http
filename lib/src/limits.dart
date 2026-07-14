import 'package:meta/meta.dart';

@immutable
class Limits {
  const Limits({
    this.maxConnections = 100,
    this.maxKeepaliveConnections = 20,
    this.keepaliveExpiry = const Duration(seconds: 5),
    this.poolTimeout = const Duration(seconds: 10),
  });

  static const Limits defaults = Limits();

  final int maxConnections;
  final int maxKeepaliveConnections;
  final Duration keepaliveExpiry;

  /// How long to wait for a pooled connection slot before throwing
  /// [PoolTimeoutError]. `dart:io`'s built-in pool already blocks when
  /// [maxConnections] is reached; this timeout makes the wait observable.
  /// ponytail: not yet wired into IoTransport — connectTimeout implicitly
  /// covers pool starvation. Wire via ResizeableSemaphore if needed.
  final Duration poolTimeout;

  Limits copyWith({
    int? maxConnections,
    int? maxKeepaliveConnections,
    Duration? keepaliveExpiry,
    Duration? poolTimeout,
  }) {
    return Limits(
      maxConnections: maxConnections ?? this.maxConnections,
      maxKeepaliveConnections:
          maxKeepaliveConnections ?? this.maxKeepaliveConnections,
      keepaliveExpiry: keepaliveExpiry ?? this.keepaliveExpiry,
      poolTimeout: poolTimeout ?? this.poolTimeout,
    );
  }

  @override
  String toString() {
    return 'Limits(maxConnections: $maxConnections, '
        'maxKeepaliveConnections: $maxKeepaliveConnections, '
        'keepaliveExpiry: $keepaliveExpiry, poolTimeout: $poolTimeout)';
  }
}
