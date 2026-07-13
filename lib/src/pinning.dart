import 'package:meta/meta.dart';

/// Per-host certificate pinning configuration.
///
/// Maps each hostname to a set of acceptable SHA-256 fingerprints of the
/// server's DER-encoded X.509 certificate (base64-encoded, without the
/// `sha256/` prefix).
///
/// The actual fingerprint check happens in the transport layer
/// ([IoTransport]) which has access to `dart:io`'s [X509Certificate].
@immutable
class PinnedCertificates {
  const PinnedCertificates({this.pins = const {}});

  /// Host → list of SHA-256 fingerprints (base64-encoded).
  final Map<String, List<String>> pins;

  @override
  bool operator ==(Object other) =>
      other is PinnedCertificates && _mapEquals(pins, other.pins);

  @override
  int get hashCode => Object.hashAll(
        pins.entries.expand((e) => [e.key, ...e.value]),
      );

  static bool _mapEquals(
    Map<String, List<String>> a,
    Map<String, List<String>> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      final bVal = b[entry.key];
      if (bVal == null) {
        return false;
      }
      if (!_listEquals(entry.value, bVal)) {
        return false;
      }
    }
    return true;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
