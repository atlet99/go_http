import 'package:meta/meta.dart';

/// Structured timeout configuration for the four phases of an HTTP request.
///
/// Each phase is independently configurable; `null` means "no timeout for this
/// phase". This mirrors the design of Python `httpx.Timeout`, giving a clear
/// 3-state semantics at the per-request level:
///
///   * parameter omitted (`null`) → inherit the client default
///   * [Timeout.disabled] → explicitly disable every phase
///   * a value → use that value
///
/// Phase mapping to the transport layer:
///   * [connect] – establishing the connection
///   * [write]   – sending the request ("send timeout")
///   * [read]    – receiving the response ("receive timeout")
///   * [pool]    – waiting for a free connection from the pool
@immutable
class Timeout {
  const Timeout({
    this.connect,
    this.read,
    this.write,
    this.pool,
  });

  /// All four phases set to the same [duration].
  const Timeout.all(Duration duration)
      : connect = duration,
        read = duration,
        write = duration,
        pool = duration;

  /// Explicitly disable every phase (no timeouts at all).
  const Timeout.disabled()
      : connect = null,
        read = null,
        write = null,
        pool = null;

  /// Default: 10s connect, 30s read/write, 10s pool.
  static const Timeout defaultTimeout = Timeout(
    connect: Duration(seconds: 10),
    read: Duration(seconds: 30),
    write: Duration(seconds: 30),
    pool: Duration(seconds: 10),
  );

  final Duration? connect;
  final Duration? read;
  final Duration? write;
  final Duration? pool;

  /// Whether every phase is unbounded.
  bool get isDisabled =>
      connect == null && read == null && write == null && pool == null;

  /// Merge another [other] over `this`: non-null fields in [other] win.
  Timeout merge(Timeout other) {
    return Timeout(
      connect: other.connect ?? connect,
      read: other.read ?? read,
      write: other.write ?? write,
      pool: other.pool ?? pool,
    );
  }

  Timeout copyWith({
    Duration? connect,
    Duration? read,
    Duration? write,
    Duration? pool,
  }) {
    return Timeout(
      connect: connect ?? this.connect,
      read: read ?? this.read,
      write: write ?? this.write,
      pool: pool ?? this.pool,
    );
  }

  @override
  String toString() {
    if (connect == read && read == write && write == pool) {
      return 'Timeout(${connect?.inSeconds}s)';
    }
    return 'Timeout(connect: $connect, read: $read, write: $write, pool: $pool)';
  }
}
