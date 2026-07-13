import 'request_trace.dart';

/// Per-phase timing for a single HTTP request.
///
/// All fields are `DateTime?` — a field is `null` if the phase was skipped or
/// the transport did not report it.
class ResponseTiming {
  const ResponseTiming({
    this.dnsStart,
    this.dnsDone,
    this.connectStart,
    this.connectDone,
    this.tlsHandshakeStart,
    this.tlsHandshakeDone,
    this.wroteRequest,
    this.gotFirstResponseByte,
  });

  final DateTime? dnsStart;
  final DateTime? dnsDone;
  final DateTime? connectStart;
  final DateTime? connectDone;
  final DateTime? tlsHandshakeStart;
  final DateTime? tlsHandshakeDone;
  final DateTime? wroteRequest;
  final DateTime? gotFirstResponseByte;
}

/// TLS handshake details.
class TlsInfo {
  const TlsInfo({
    this.version,
    this.cipherSuite,
    this.serverCertificate,
    this.handshakeDuration,
  });

  /// e.g. `"TLSv1.3"`
  final String? version;

  /// e.g. `"TLS_AES_256_GCM_SHA384"`
  final String? cipherSuite;

  /// PEM-encoded server certificate, if recorded.
  final String? serverCertificate;

  /// Duration of the TLS handshake.
  final Duration? handshakeDuration;
}

/// Optional enrichment data attached to a [Response].
///
/// Populated by the transport and client when enrichment is enabled.
/// `null` fields indicate the data is unavailable for the request.
class ResponseEnrichment {
  const ResponseEnrichment({
    this.timing,
    this.tlsInfo,
    this.trace,
  });

  final ResponseTiming? timing;
  final TlsInfo? tlsInfo;

  /// Raw phase timestamps populated by the transport (microsecond counters).
  final RequestTrace? trace;
}
