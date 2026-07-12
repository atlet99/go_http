import '../response.dart';
import 'cookie_store.dart';

/// In-memory cookie store implementation.
///
/// Cookies are keyed by their effective domain: the `Domain` attribute from the
/// `Set-Cookie` header if present, otherwise the request host. Multiple
/// `Set-Cookie` headers are preserved as separate entries.
class MemoryCookieStore implements CookieStore {
  final Map<String, Map<String, String>> _cookies = {};

  @override
  List<String> getCookies(Uri uri) {
    final domain = uri.host.toLowerCase();
    final cookies = <String>[];

    // Exact domain match
    cookies.addAll(_cookies[domain]?.values ?? const []);

    // Parent domains (so a cookie set on example.com applies to sub.example.com)
    final parts = domain.split('.');
    for (var i = 1; i < parts.length; i++) {
      final parentDomain = parts.sublist(i).join('.');
      cookies.addAll(_cookies[parentDomain]?.values ?? const []);
    }

    return cookies;
  }

  @override
  void setCookies(Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null) {
      return;
    }

    final requestHost = response.request.uri.host.toLowerCase();

    // Each Set-Cookie header is kept on its own line by the transport.
    for (final cookie in raw.split('\n')) {
      final trimmed = cookie.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      // name=value is the first segment before ';'
      final firstSemicolon = trimmed.indexOf(';');
      final nv =
          (firstSemicolon >= 0 ? trimmed.substring(0, firstSemicolon) : trimmed)
              .trim();
      final eq = nv.indexOf('=');
      if (eq <= 0) {
        continue;
      }

      final name = nv.substring(0, eq).trim();
      final value = nv.substring(eq + 1).trim();
      if (name.isEmpty) {
        continue;
      }

      // Determine the effective domain from the Domain attribute (if any)
      final domain = _extractDomain(trimmed) ?? requestHost;

      _cookies.putIfAbsent(domain, () => {})[name] = '$name=$value';
    }
  }

  String? _extractDomain(String cookie) {
    for (final attr in cookie.split(';')) {
      final a = attr.trim();
      if (a.toLowerCase().startsWith('domain=')) {
        var domain = a.substring(7).trim().toLowerCase();
        // Strip a single leading dot (RFC 6265 allows ".example.com").
        if (domain.startsWith('.')) {
          domain = domain.substring(1);
        }
        return domain;
      }
    }
    return null;
  }

  @override
  void clear() {
    _cookies.clear();
  }

  @override
  void clearDomain(String domain) {
    _cookies.remove(domain.toLowerCase());
  }
}
