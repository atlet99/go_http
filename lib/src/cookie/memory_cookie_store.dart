import '../response.dart';
import 'cookie_store.dart';

/// In-memory cookie store implementation
class MemoryCookieStore implements CookieStore {
  final Map<String, List<String>> _cookies = {};

  @override
  List<String> getCookies(Uri uri) {
    final domain = uri.host;
    final cookies = <String>[];

    // Get cookies for exact domain
    cookies.addAll(_cookies[domain] ?? []);

    // Get cookies for parent domains
    final parts = domain.split('.');
    for (var i = 1; i < parts.length; i++) {
      final parentDomain = parts.sublist(i).join('.');
      cookies.addAll(_cookies[parentDomain] ?? []);
    }

    return cookies;
  }

  @override
  void setCookies(Response response) {
    final setCookieHeaders = response.headers['set-cookie'];
    if (setCookieHeaders == null) {
      return;
    }

    final uri = response.request.uri;
    final domain = uri.host;

    // Parse Set-Cookie headers
    final cookies = setCookieHeaders.split(',').map((c) => c.trim()).toList();
    for (final cookie in cookies) {
      // Simple cookie parsing (extract name=value)
      final parts = cookie.split(';').first.split('=');
      if (parts.length == 2) {
        final cookieName = parts[0].trim();
        final cookieValue = parts[1].trim();

        // Store cookie
        _cookies.putIfAbsent(domain, () => []).add('$cookieName=$cookieValue');
      }
    }
  }

  @override
  void clear() {
    _cookies.clear();
  }

  @override
  void clearDomain(String domain) {
    _cookies.remove(domain);
  }
}
