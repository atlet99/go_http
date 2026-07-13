import '../response.dart';
import 'cookie_store.dart';
import 'persistent_cookie.dart';

/// In-memory cookie store with RFC 6265 compliance.
///
/// Cookies are stored with full metadata (domain, path, secure, httponly,
/// expiry) and filtered on retrieval according to RFC 6265 §5.1.3–5.2.6.
///
/// ponytail: no public-suffix list — example.com cookies can be set from
/// sub.example.com. Add a PSL dependency if origin-based restriction is needed.
class MemoryCookieStore implements CookieStore {
  final List<PersistentCookie> _cookies = [];

  @override
  List<String> getCookies(Uri uri) {
    final matching = _cookies.where((c) => c.matches(uri)).toList()
      ..sort((a, b) => b.path.length.compareTo(a.path.length));

    return matching.map((c) => c.toHeaderValue()).toList();
  }

  @override
  void setCookies(Response response) {
    final requestUri = response.request.uri;

    for (final header in response.headers.getAll('set-cookie')) {
      final trimmed = header.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final cookie = _parseSetCookie(trimmed, requestUri);
      if (cookie == null) {
        continue;
      }

      _cookies.removeWhere(
        (c) =>
            c.name == cookie.name &&
            c.domain == cookie.domain &&
            c.path == cookie.path,
      );

      if (cookie.expires != null && cookie.isExpired) {
        continue;
      }

      _cookies.add(cookie);
    }
  }

  PersistentCookie? _parseSetCookie(String header, Uri requestUri) {
    final parts = header.split(';');
    if (parts.isEmpty) {
      return null;
    }

    final nv = parts[0].trim();
    final eq = nv.indexOf('=');
    if (eq <= 0) {
      return null;
    }

    final name = nv.substring(0, eq).trim();
    final value = nv.substring(eq + 1).trim();
    if (name.isEmpty) {
      return null;
    }

    var domain = requestUri.host.toLowerCase();
    var path = _defaultPath(requestUri);
    var secure = false;
    var httponly = false;
    DateTime? expires;
    Duration? maxAge;

    for (var i = 1; i < parts.length; i++) {
      final attr = parts[i].trim();
      final aeq = attr.indexOf('=');
      final attrName = aeq >= 0
          ? attr.substring(0, aeq).trim().toLowerCase()
          : attr.toLowerCase();
      final attrValue = aeq >= 0 ? attr.substring(aeq + 1).trim() : '';

      if (attrName == 'domain') {
        var d = attrValue.toLowerCase();
        if (d.startsWith('.')) {
          d = d.substring(1);
        }
        if (d.isNotEmpty) {
          domain = d;
        }
      } else if (attrName == 'path') {
        if (attrValue.isNotEmpty && attrValue.startsWith('/')) {
          path = attrValue;
        }
      } else if (attrName == 'secure') {
        secure = true;
      } else if (attrName == 'httponly') {
        httponly = true;
      } else if (attrName == 'max-age') {
        final seconds = int.tryParse(attrValue);
        if (seconds != null) {
          if (seconds <= 0) {
            expires = DateTime.fromMillisecondsSinceEpoch(0);
          } else {
            maxAge = Duration(seconds: seconds);
          }
        }
      } else if (attrName == 'expires') {
        if (maxAge == null) {
          expires = _parseHttpDate(attrValue);
        }
      }
    }

    if (maxAge != null) {
      expires = DateTime.now().add(maxAge);
    }

    return PersistentCookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      secure: secure,
      httponly: httponly,
      expires: expires,
    );
  }

  String _defaultPath(Uri uri) {
    final p = uri.path;
    if (p.isEmpty || p[0] != '/') {
      return '/';
    }
    final lastSlash = p.lastIndexOf('/');
    if (lastSlash <= 0) {
      return '/';
    }
    return p.substring(0, lastSlash);
  }

  DateTime? _parseHttpDate(String value) {
    try {
      var s = value.trim();
      final comma = s.indexOf(',');
      if (comma >= 0) {
        s = s.substring(comma + 1).trim();
      }
      if (s.endsWith(' GMT')) {
        s = s.substring(0, s.length - 4);
      }

      const months = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'aug': 8,
        'sep': 9,
        'oct': 10,
        'nov': 11,
        'dec': 12,
      };

      final parts = s.split(' ');
      final clean = parts.where((p) => p.isNotEmpty).toList();
      if (clean.length < 3) {
        return null;
      }

      final day = int.tryParse(clean[0]);
      final month = months[clean[1].toLowerCase().padRight(3).substring(0, 3)];
      final year = int.tryParse(clean[2]);
      final timeParts = (clean.length > 3 ? clean[3] : '00:00:00').split(':');
      final hour = int.tryParse(timeParts[0]) ?? 0;
      final min = int.tryParse(timeParts[1]) ?? 0;
      final sec = int.tryParse(timeParts[2]) ?? 0;

      if (day == null || month == null || year == null) {
        return null;
      }
      return DateTime.utc(year, month, day, hour, min, sec);
    } catch (_) {
      return null;
    }
  }

  @override
  void clear() => _cookies.clear();

  @override
  void clearDomain(String domain) {
    _cookies.removeWhere(
      (c) => c.domain == domain.toLowerCase(),
    );
  }

  /// Number of cookies currently stored (for testing).
  int get count => _cookies.length;
}
