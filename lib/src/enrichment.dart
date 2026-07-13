import 'request_trace.dart';
import 'response.dart';

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
    this.subject,
    this.issuer,
    this.fingerprintSha1,
    this.fingerprintSha256,
    this.isSelfSigned,
    this.isWildcard,
    this.validFrom,
    this.validTo,
  });

  /// e.g. `"TLSv1.3"`
  final String? version;

  /// e.g. `"TLS_AES_256_GCM_SHA384"`
  final String? cipherSuite;

  /// PEM-encoded server certificate, if recorded.
  final String? serverCertificate;

  /// Duration of the TLS handshake.
  final Duration? handshakeDuration;

  /// Subject CN/AN from the server certificate.
  final String? subject;

  /// Issuer from the server certificate.
  final String? issuer;

  /// SHA-1 fingerprint of the server certificate (hex pairs, colon-separated).
  final String? fingerprintSha1;

  /// SHA-256 fingerprint of the server certificate (hex pairs,
  /// colon-separated). Computed from the DER-encoded certificate body.
  final String? fingerprintSha256;

  /// True when [issuer] equals [subject] (self-signed certificate).
  final bool? isSelfSigned;

  /// True when the subject contains a wildcard (`*.`), indicating the
  /// certificate covers subdomains.
  final bool? isWildcard;

  /// Certificate validity start date.
  final DateTime? validFrom;

  /// Certificate validity end date.
  final DateTime? validTo;
}

/// SPI for enriching responses with custom data.
///
/// Implementations compute extra metadata per response (e.g. title extraction,
/// content hashing, tech detection) and return it as key-value pairs stored
/// in [ResponseEnrichment.extra].
///
/// Each enricher is gated via the [name] key in the client's enricher list —
/// only registered enrichers run. Implementations should be lazy: do the
/// minimum work in [enrich] and compute heavy fields only when accessed.
abstract class ResponseEnricher {
  const ResponseEnricher();

  String get name;

  Future<Map<String, dynamic>> enrich(Response response);
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
    this.remoteAddress,
    this.extra,
  });

  final ResponseTiming? timing;
  final TlsInfo? tlsInfo;

  /// Raw phase timestamps populated by the transport (microsecond counters).
  final RequestTrace? trace;

  /// The IP address of the remote server that handled the request.
  /// Populated by the transport when available.
  final String? remoteAddress;

  /// Extra key-value pairs contributed by registered [ResponseEnricher]s.
  final Map<String, dynamic>? extra;
}
