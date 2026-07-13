/// Immutable URL, thin wrapper over [Uri] with httpx-style ergonomics.
///
/// - scheme/host are lowercased; the port is `null` for the scheme's default
///   (so `:80` on http reads as "no port", matching the httpx `Url`).
/// - `copyWith` produces a new [Url] without mutating the original.
/// - `join` does RFC 3986 §5.3 reference resolution (`Uri.resolve`).
/// - `toString` masks the password in the userinfo.
///
/// ponytail: IDNA encode/decode of the host is deferred (no stdlib punycode);
/// `rawHost` currently equals the (lower-cased) parsed host.
class Url {
  Url._(this._uri);

  factory Url.parse(String url) => Url._(_normalize(Uri.parse(url.trim())));

  factory Url.fromUri(Uri uri) => Url._(_normalize(uri));

  static const _defaultPorts = {
    'http': 80,
    'https': 443,
    'ws': 80,
    'wss': 443,
  };

  final Uri _uri;

  String get scheme => _uri.scheme;
  String get host => _uri.host.toLowerCase();
  String get rawHost => _uri.host;
  String get path => _uri.path;
  String? get fragment => _uri.fragment.isEmpty ? null : _uri.fragment;

  /// `null` when equal to the scheme's default port.
  int? get port {
    final def = _defaultPorts[_uri.scheme];
    if (def != null && _uri.port == def) {
      return null;
    }
    return _uri.port == 0 ? null : _uri.port;
  }

  QueryParams get query => QueryParams.fromUri(_uri);

  Url copyWith({
    String? scheme,
    String? host,
    Object? port = const _Keep(),
    String? path,
    String? fragment,
    QueryParams? query,
  }) {
    final newUri = _uri.replace(
      scheme: scheme,
      host: host,
      port: port is _Keep ? null : (port as int?),
      path: path,
      fragment: fragment,
      query: query?.toQueryString(),
    );
    return Url._(_normalize(newUri));
  }

  /// Resolve [ref] against this URL (RFC 3986 §5.3).
  Url join(String ref) => Url._(_normalize(_uri.resolve(ref)));

  @override
  String toString() {
    final user = _uri.userInfo.contains(':')
        ? _uri.userInfo.split(':').first
        : _uri.userInfo;
    final authority = user.isEmpty ? _uri.host : '$user@${_uri.host}';
    final portStr = port == null ? '' : ':$port';
    final queryStr = _uri.query.isEmpty ? '' : '?${_uri.query}';
    final fragStr = _uri.fragment.isEmpty ? '' : '#${_uri.fragment}';
    return '${_uri.scheme}://$authority$portStr${_uri.path}$queryStr$fragStr';
  }

  static Uri _normalize(Uri uri) => uri.replace(
        scheme: uri.scheme.toLowerCase(),
        host: uri.host.toLowerCase(),
      );
}

class _Keep {
  const _Keep();
}

/// Immutable multi-value query string (httpx `QueryParams`).
///
/// `merge`/`add`/`set`/`remove` return a **new** instance; the original is
/// never mutated. A bool value is rendered JSON-style (`true`/`false`).
class QueryParams {
  QueryParams([Map<String, String>? map])
      : _m = {
          for (final e in (map ?? {}).entries) e.key: [_coerce(e.value)],
        };

  QueryParams.all(Map<String, List<String>> map)
      : _m = {
          for (final e in map.entries) e.key: e.value.map(_coerce).toList(),
        };

  factory QueryParams.fromUri(Uri uri) =>
      QueryParams.all(uri.queryParametersAll);

  final Map<String, List<String>> _m;

  static String _coerce(Object value) => value.toString();

  bool get isEmpty => _m.isEmpty;
  bool get isNotEmpty => _m.isNotEmpty;

  bool containsKey(String key) => _m.containsKey(key);

  /// First value for [key], or `null`.
  String? operator [](String key) => _m[key]?.first;

  /// Every value for [key] (possibly empty).
  List<String> getList(String key) => List.unmodifiable(_m[key] ?? const []);

  /// All key → values.
  Map<String, List<String>> get all => Map.unmodifiable(_m);

  QueryParams add(String key, Object value) {
    final next = _clone();
    next.putIfAbsent(key, () => []).add(_coerce(value));
    return QueryParams.all(next);
  }

  QueryParams set(String key, Object value) => QueryParams.all({
        ..._m,
        key: [_coerce(value)],
      });

  QueryParams remove(String key) {
    final next = _clone()..remove(key);
    return QueryParams.all(next);
  }

  /// Merge [other] in; shared keys keep both values (other appended).
  QueryParams merge(QueryParams other) {
    final next = _clone();
    for (final e in other._m.entries) {
      next.putIfAbsent(e.key, () => []).addAll(e.value);
    }
    return QueryParams.all(next);
  }

  /// URL-encoded query string (percent-escaped keys and values).
  String toQueryString() => _m.entries
      .expand(
        (e) => e.value.map(
          (v) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(v)}',
        ),
      )
      .join('&');

  Map<String, List<String>> _clone() => {
        for (final e in _m.entries) e.key: [...e.value],
      };
}
