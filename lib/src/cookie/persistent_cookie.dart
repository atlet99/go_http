/// A stored cookie with RFC 6265 metadata for domain/path/secure/httponly
/// matching and expiry enforcement.
class PersistentCookie {
  const PersistentCookie({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    this.secure = false,
    this.httponly = false,
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httponly;
  final DateTime? expires;

  bool get isSession => expires == null;

  bool get isExpired {
    if (expires == null) {
      return false;
    }
    return DateTime.now().isAfter(expires!);
  }

  bool matches(Uri uri) {
    if (expires != null && DateTime.now().isAfter(expires!)) {
      return false;
    }
    if (secure && uri.scheme != 'https') {
      return false;
    }
    return _domainMatches(uri.host) && _pathMatches(uri.path);
  }

  bool _domainMatches(String host) {
    final h = host.toLowerCase();
    final d = domain.toLowerCase();
    if (h == d) {
      return true;
    }
    return h.endsWith('.$d');
  }

  bool _pathMatches(String requestPath) {
    final rp = requestPath.isEmpty ? '/' : requestPath;
    if (path == '/') {
      return true;
    }
    if (rp == path) {
      return true;
    }
    if (rp.startsWith(path) && rp[path.length] == '/') {
      return true;
    }
    return false;
  }

  String toHeaderValue() => '$name=$value';

  @override
  String toString() =>
      'PersistentCookie($name=$value; domain=$domain; path=$path'
      '${secure ? '; secure' : ''}${httponly ? '; httponly' : ''}'
      '${expires != null ? '; expires=${expires!.toIso8601String()}' : ''})';
}
