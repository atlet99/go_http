/// A parsed mapping of scheme → port number, e.g. `{"http": 8080, "https": 443}`.
///
/// Use [PortSpec.parse] to build from a config string like `"http:8080,https:443"`.
class PortSpec {
  PortSpec._(this.ports);

  final Map<String, int> ports;

  /// Parses a comma-separated list of `scheme:port` pairs.
  ///
  /// ```dart
  /// PortSpec.parse('http:8080,https:8443'); // {http: 8080, https: 8443}
  /// ```
  static PortSpec parse(String input) {
    final map = <String, int>{};
    for (final part in input.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon < 1) {
        continue;
      }
      final scheme = trimmed.substring(0, colon).trim().toLowerCase();
      final port = int.tryParse(trimmed.substring(colon + 1).trim());
      if (port != null && port > 0 && port <= 65535) {
        map[scheme] = port;
      }
    }
    return PortSpec._(map);
  }
}
