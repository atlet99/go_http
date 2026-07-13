import 'package:meta/meta.dart';

@immutable
class Limits {
  const Limits({
    this.maxConnections = 100,
    this.maxKeepaliveConnections = 20,
    this.keepaliveExpiry = const Duration(seconds: 5),
  });

  static const Limits defaults = Limits();

  final int maxConnections;
  final int maxKeepaliveConnections;
  final Duration keepaliveExpiry;

  Limits copyWith({
    int? maxConnections,
    int? maxKeepaliveConnections,
    Duration? keepaliveExpiry,
  }) {
    return Limits(
      maxConnections: maxConnections ?? this.maxConnections,
      maxKeepaliveConnections:
          maxKeepaliveConnections ?? this.maxKeepaliveConnections,
      keepaliveExpiry: keepaliveExpiry ?? this.keepaliveExpiry,
    );
  }

  @override
  String toString() {
    return 'Limits(maxConnections: $maxConnections, '
        'maxKeepaliveConnections: $maxKeepaliveConnections, '
        'keepaliveExpiry: $keepaliveExpiry)';
  }
}
