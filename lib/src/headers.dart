/// Case-insensitive, multi-value HTTP headers collection.
///
/// Lookup ([operator []]) is case-insensitive and joins multiple values for the
/// same header name with `", "` per RFC 7230 §3.2.2. Use [getAll] to retrieve
/// every value for a header without joining (essential for `Set-Cookie`,
/// `WWW-Authenticate`, `Vary`, `Link`). Sensitive headers are obfuscated in
/// [toString] so credentials never leak into logs.
///
/// Mirrors `httpx.Headers` semantics.
class Headers {
  Headers([Object? source])
      : _items = source is Headers
            ? List.of(source._items)
            : source == null
                ? <MapEntry<String, String>>[]
                : _entriesFromMap(source);

  Headers.fromEntries(Iterable<MapEntry<String, String>> entries)
      : _items = entries.toList();

  Headers._(this._items);

  /// Parses one or more `Key: Value` lines (LF-separated).
  ///
  /// ```dart
  /// final h = Headers.parse('Content-Type: application/json\nX-Custom: foo');
  /// ```
  factory Headers.parse(String input) {
    final entries = <MapEntry<String, String>>[];
    for (final line in input.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon < 1) {
        continue;
      }
      entries.add(MapEntry(
        trimmed.substring(0, colon).trim().toLowerCase(),
        trimmed.substring(colon + 1).trim(),
      ),);
    }
    return Headers.fromEntries(entries);
  }

  static List<MapEntry<String, String>> _entriesFromMap(Object source) {
    final map = source as Map<Object?, Object?>;
    return map.entries
        .map((e) => MapEntry(e.key.toString(), e.value.toString()))
        .toList();
  }

  final List<MapEntry<String, String>> _items;

  /// The joined value for [name], or `null` if absent. Multi-values are joined
  /// with `", "` (RFC 7230 §3.2.2).
  String? operator [](String name) {
    final lower = name.toLowerCase();
    final matches = _items
        .where((e) => e.key.toLowerCase() == lower)
        .map((e) => e.value)
        .toList(growable: false);
    if (matches.isEmpty) {
      return null;
    }
    if (matches.length == 1) {
      return matches.first;
    }
    return matches.join(', ');
  }

  /// Replace all values for [name] with [value].
  void operator []=(String name, String value) {
    final lower = name.toLowerCase();
    _items.removeWhere((e) => e.key.toLowerCase() == lower);
    _items.add(MapEntry(name, value));
  }

  /// Append [value] to the existing values for [name].
  void add(String name, String value) {
    _items.add(MapEntry(name, value));
  }

  /// Every value for [name], in insertion order, without joining.
  List<String> getAll(String name) {
    final lower = name.toLowerCase();
    return _items
        .where((e) => e.key.toLowerCase() == lower)
        .map((e) => e.value)
        .toList(growable: false);
  }

  /// All (key, value) pairs, including duplicates, in insertion order.
  List<MapEntry<String, String>> get multiItems => List.unmodifiable(_items);

  /// Whether a header named [name] exists (case-insensitive).
  bool containsKey(String name) => this[name] != null;

  /// Remove every value for [name]; returns the previously-joined value.
  String? remove(String name) {
    final value = this[name];
    final lower = name.toLowerCase();
    _items.removeWhere((e) => e.key.toLowerCase() == lower);
    return value;
  }

  /// A single-joined-value [Map] view (one entry per distinct name).
  Map<String, String> toMap() {
    final map = <String, String>{};
    for (final entry in _items) {
      final lower = entry.key.toLowerCase();
      String? existingKey;
      for (final k in map.keys) {
        if (k.toLowerCase() == lower) {
          existingKey = k;
          break;
        }
      }
      if (existingKey != null) {
        map[existingKey] = '${map[existingKey]}, ${entry.value}';
      } else {
        map[entry.key] = entry.value;
      }
    }
    return map;
  }

  /// Iterate joined values, one per distinct header name.
  void forEach(void Function(String key, String value) action) {
    toMap().forEach(action);
  }

  /// Joined entries, one per distinct header name.
  Iterable<MapEntry<String, String>> get entries => toMap().entries;

  Iterable<String> get keys => toMap().keys;
  Iterable<String> get values => toMap().values;
  int get length => toMap().length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// A shallow copy of this collection.
  Headers copy() => Headers._(List.of(_items));

  /// Merge [other] into a copy of this collection; values in [other] replace
  /// same-named keys but append new ones (httpx `update` semantics).
  Headers merge(Map<String, String> other) {
    final merged = copy();
    other.forEach((key, value) {
      merged[key] = value;
    });
    return merged;
  }

  static const Set<String> _sensitive = {
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  };

  @override
  String toString() {
    final buf = StringBuffer('{');
    var first = true;
    for (final entry in _items) {
      if (!first) {
        buf.write(', ');
      }
      first = false;
      final value = _sensitive.contains(entry.key.toLowerCase())
          ? '[secure]'
          : entry.value;
      buf.write('${entry.key}: $value');
    }
    buf.write('}');
    return buf.toString();
  }
}
