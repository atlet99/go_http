/// Per-request timing trace populated by the transport.
///
/// Each field is a monotonic microsecond counter captured at a specific phase
/// of the request lifecycle. Convert to `Duration` via
/// `Duration(microseconds: elapsed)`.
///
/// `null` means the phase was not reached or not recorded.
class RequestTrace {
  // ponytail: mutable fields so the transport can incrementally populate
  // without rebuilding the object each time. Getters are public, setters
  // are library-private (used by the transport).

  /// Microsecond when DNS resolution started.
  int? dnsStart;

  /// Microsecond when DNS resolution completed.
  int? dnsDone;

  /// Microsecond when TCP connection started.
  int? connectStart;

  /// Microsecond when TCP connection established.
  int? connectDone;

  /// Microsecond when TLS handshake started.
  int? tlsHandshakeStart;

  /// Microsecond when TLS handshake completed.
  int? tlsHandshakeDone;

  /// Microsecond when the full request was written (after `HttpClientRequest.close`).
  int? wroteRequest;

  /// Microsecond when the first byte of the response was received.
  int? gotFirstResponseByte;

  /// Microsecond when the response body was fully read.
  int? responseDone;
}
