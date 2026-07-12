import 'dart:io' show Platform, SecurityContext, HttpClient;

/// A proxy endpoint.
///
/// Mirrors `httpx.Proxy`: `http://` / `https://` (= CONNECT) /
/// `socks5://` / `socks5h://`, plus `direct://` / `null` meaning "no
/// proxy for this route".
class Proxy {
  Proxy(
    this.scheme, {
    required this.authority,
    this.username,
    this.password,
  }) {
    if (!const {'direct', 'http', 'https', 'socks5', 'socks5h'}
        .contains(scheme)) {
      throw ArgumentError('Unsupported proxy scheme: $scheme');
    }
  }

  factory Proxy.direct() => Proxy('direct', authority: '');

  factory Proxy.parse(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty ||
        trimmed == 'direct://' ||
        trimmed.toLowerCase() == 'none') {
      return Proxy.direct();
    }
    final uri = Uri.parse(trimmed);
    if (!uri.hasAuthority) {
      throw ArgumentError('Proxy url needs a host: $url');
    }
    String? user;
    String? pass;
    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      user = parts[0];
      pass = parts.length > 1 ? parts.sublist(1).join(':') : null;
    }
    return Proxy(
      uri.scheme,
      authority: '${uri.host}:${uri.port}',
      username: user,
      password: pass,
    );
  }

  final String scheme; // 'direct' | 'http' | 'https' | 'socks5' | 'socks5h'
  final String authority; // 'host:port'
  final String? username;
  final String? password;

  bool get isDirect => scheme == 'direct';

  /// Directive for [HttpClient.findProxy] (`'PROXY host:port'`,
  /// `'CONNECT host:port'`, `'DIRECT'`).
  String get findProxyUrl {
    if (isDirect) {
      return 'DIRECT';
    }
    if (scheme == 'https') {
      return 'CONNECT $authority';
    }
    if (scheme == 'socks5' || scheme == 'socks5h') {
      throw UnsupportedError(
        'SOCKS proxies are not supported by the native transport',
      );
    }
    return 'PROXY $authority';
  }

  @override
  String toString() {
    if (isDirect) {
      return 'Proxy.direct';
    }
    final creds = username != null ? '$username:***@' : '';
    return 'Proxy($scheme://$creds$authority)';
  }
}

/// A URL pattern for proxy routing. `all://` matches any scheme; `*` in the
/// host is a wildcard matching any subdomain labels.
class URLPattern {
  URLPattern(this.scheme, {this.host, this.port})
      : assert(
          const {'all', 'http', 'https'}.contains(scheme),
          'URLPattern scheme must be all/http/https',
        );

  factory URLPattern.parse(String pattern) {
    final uri = Uri.parse(pattern.trim());
    String? host;
    if (uri.host == '*') {
      host = '*';
    } else if (uri.host.isNotEmpty) {
      host = uri.host;
    }
    int? port;
    if (uri.port != 0) {
      port = uri.port;
    }
    return URLPattern(uri.scheme, host: host, port: port);
  }

  final String scheme; // 'all' | 'http' | 'https'
  final String? host; // null = any; '*' = wildcard subdomain
  final int? port; // null = any

  bool matches(Uri uri) {
    if (scheme != 'all' && scheme != uri.scheme) {
      return false;
    }
    if (host != null && !_hostMatches(host!, uri.host)) {
      return false;
    }
    if (port != null && port != uri.port) {
      return false;
    }
    return true;
  }

  /// Higher = more specific. Port > host-length > scheme != 'all'.
  int get specificity {
    var s = 0;
    if (port != null) {
      s += 1000;
    }
    if (host != null) {
      s += host!.length;
    }
    if (scheme != 'all') {
      s += 10;
    }
    return s;
  }
}

/// Per-URL-pattern proxy routing. A `null` value = explicitly direct.
class ProxyMounts {
  ProxyMounts(this.routes);

  final Map<URLPattern, Proxy?> routes;

  /// Most-specific matching mount for [uri], or `null` if none matches.
  /// A matched `null` value means "direct for this pattern".
  Proxy? findProxy(Uri uri) {
    final matched = routes.entries.where((e) => e.key.matches(uri)).toList()
      ..sort((a, b) => b.key.specificity.compareTo(a.key.specificity));
    if (matched.isEmpty) {
      return null;
    }
    return matched.first.value;
  }
}

/// Build a [SecurityContext] from [verify]:
/// `false` → no verification, `String` → CA file path, [SecurityContext] →
/// as-is, `true`/`null` → system roots (honoring `SSL_CERT_FILE` env
/// when [trustEnv]).
SecurityContext buildSecurityContext(Object? verify, bool trustEnv) {
  if (verify == false) {
    return SecurityContext(withTrustedRoots: false);
  }
  if (verify is String) {
    final c = SecurityContext(withTrustedRoots: false);
    c.setTrustedCertificates(verify);
    return c;
  }
  if (verify is SecurityContext) {
    return verify;
  }
  // verify == true (default) or null
  final certFile = trustEnv ? Platform.environment['SSL_CERT_FILE'] : null;
  if (certFile != null) {
    final c = SecurityContext(withTrustedRoots: false);
    c.setTrustedCertificates(certFile);
    return c;
  }
  return SecurityContext.defaultContext;
}

bool _hostMatches(String pattern, String host) {
  if (pattern == '*') {
    return true;
  }
  if (!pattern.contains('*')) {
    return pattern == host;
  }
  const placeholder = '<<STAR>>';
  var escaped = pattern.replaceAll('*', placeholder);
  escaped = escaped.replaceAllMapped(
    RegExp(r'[.+^${}()|[\]\\]'),
    (m) => '\\${m[0]}',
  );
  escaped = escaped.replaceAll(placeholder, '.*');
  return RegExp('^$escaped\$').hasMatch(host);
}
