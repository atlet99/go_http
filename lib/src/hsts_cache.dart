import 'response.dart';

/// HSTS policy for a single host (RFC 6797).
class HstsPolicy {
  HstsPolicy({
    required this.host,
    required this.maxAgeSeconds,
    this.includeSubDomains = false,
    this.preload = false,
    DateTime? createdAt,
  }) : _createdAt = createdAt ?? DateTime.now();

  /// Normalised lowercase hostname.
  final String host;

  /// Seconds after which the policy expires.
  final int maxAgeSeconds;

  /// Whether the policy applies to all subdomains.
  final bool includeSubDomains;

  /// Whether the host is in the browser preload list.
  final bool preload;

  final DateTime _createdAt;

  /// `true` when the policy has outlived its [maxAgeSeconds].
  bool get isExpired => DateTime.now().isAfter(
        _createdAt.add(Duration(seconds: maxAgeSeconds)),
      );

  @override
  bool operator ==(Object other) =>
      other is HstsPolicy &&
      host == other.host &&
      maxAgeSeconds == other.maxAgeSeconds &&
      includeSubDomains == other.includeSubDomains &&
      preload == other.preload;

  @override
  int get hashCode => Object.hash(
        host,
        maxAgeSeconds,
        includeSubDomains,
        preload,
      );

  @override
  String toString() => 'HstsPolicy($host, max-age=$maxAgeSeconds'
      '${includeSubDomains ? ', includeSubDomains' : ''}'
      '${preload ? ', preload' : ''})';
}

/// HSTS cache interface.
abstract class HstsCache {
  /// Look up HSTS policy covering [host].
  ///
  /// Checks exact match first, then walks up the domain for
  /// `includeSubDomains` policies. Returns `null` when no policy matches or
  /// the matching policy has expired.
  HstsPolicy? lookup(String host);

  /// Parse `Strict-Transport-Security` from [response] and store the policy.
  ///
  /// Per RFC 6797 §7.2, the header is only accepted when the response was
  /// received over a secure transport (`response.request.uri.scheme ==
  /// 'https'`). A `max-age=0` header removes the stored policy.
  void setHsts(Response response);

  /// Remove expired entries. Returns the number of entries removed.
  int clearExpired();

  /// Remove all entries.
  void clear();
}

/// In-memory HSTS cache.
class MemoryHstsCache implements HstsCache {
  final _policies = <String, HstsPolicy>{};

  @override
  HstsPolicy? lookup(String host) {
    final key = host.toLowerCase();

    // Exact match
    final exact = _policies[key];
    if (exact != null) {
      if (!exact.isExpired) {
        return exact;
      }
      _policies.remove(key);
    }

    // includeSubDomains: walk up the domain labels
    var dot = key.indexOf('.');
    while (dot >= 0 && dot < key.length - 1) {
      final parent = key.substring(dot + 1);
      final parentPolicy = _policies[parent];
      if (parentPolicy != null) {
        if (!parentPolicy.isExpired && parentPolicy.includeSubDomains) {
          return parentPolicy;
        }
        if (parentPolicy.isExpired) {
          _policies.remove(parent);
        }
      }
      dot = key.indexOf('.', dot + 1);
    }

    return null;
  }

  @override
  void setHsts(Response response) {
    final header = response.headers['strict-transport-security'];
    if (header == null) {
      return;
    }

    // RFC 6797 §7.2: only accept over HTTPS
    if (response.request.uri.scheme != 'https') {
      return;
    }

    final host = response.request.uri.host.toLowerCase();
    final policy = _parsePolicy(host, header);
    if (policy == null) {
      return;
    }

    if (policy.maxAgeSeconds == 0) {
      _policies.remove(host);
    } else {
      _policies[host] = policy;
    }
  }

  HstsPolicy? _parsePolicy(String host, String header) {
    int? maxAge;
    var includeSubDomains = false;
    var preload = false;

    for (final part in header.split(';')) {
      final trimmed = part.trim();
      if (trimmed.startsWith('max-age=')) {
        maxAge = int.tryParse(trimmed.substring(8));
      } else if (trimmed == 'includeSubDomains') {
        includeSubDomains = true;
      } else if (trimmed == 'preload') {
        preload = true;
      }
    }

    if (maxAge == null || maxAge < 0) {
      return null;
    }

    return HstsPolicy(
      host: host,
      maxAgeSeconds: maxAge,
      includeSubDomains: includeSubDomains,
      preload: preload,
    );
  }

  @override
  int clearExpired() {
    final before = _policies.length;
    _policies.removeWhere((_, p) => p.isExpired);
    return before - _policies.length;
  }

  @override
  void clear() => _policies.clear();

  int get size => _policies.length;
}
