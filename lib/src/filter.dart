import 'dart:convert' show utf8;

import 'response.dart';

/// Matches a [Response] for inclusion or routing.
abstract class ResponseFilter {
  bool matches(Response response);
}

/// Matches responses whose status code falls in a given range.
class StatusCodeFilter extends ResponseFilter {
  StatusCodeFilter.exact(int code)
      : _lo = code,
        _hi = code;

  StatusCodeFilter.between(this._lo, [this._hi = 999]);

  StatusCodeFilter.above(int code)
      : _lo = code + 1,
        _hi = 999;

  StatusCodeFilter.below(int code)
      : _lo = 0,
        _hi = code - 1;

  final int _lo;
  final int _hi;

  @override
  bool matches(Response response) =>
      response.statusCode >= _lo && response.statusCode <= _hi;
}

/// Matches responses whose body text contains the given regex.
class RegexFilter extends ResponseFilter {
  RegexFilter(RegExp pattern) : _pattern = pattern;

  final RegExp _pattern;

  @override
  bool matches(Response response) {
    final body = _bodyText(response);
    return body != null && _pattern.hasMatch(body);
  }

  static String? _bodyText(Response resp) {
    final data = resp.data;
    if (data == null) {
      return null;
    }
    if (data is String) {
      return data;
    }
    if (data is List<int>) {
      return utf8.decode(data, allowMalformed: true);
    }
    return data.toString();
  }
}

/// Composition mode for [Match].
enum MatchMode { any, all }

/// Composes multiple filters with short-circuit logic.
///
/// ```dart
/// final f = Match.any([StatusCodeFilter.between(200, 299), RegexFilter(RegExp(r'admin'))]);
/// ```
class Match extends ResponseFilter {
  Match(this.filters, this.mode);

  /// Returns `true` when **any** filter matches (OR, short-circuit).
  factory Match.any(List<ResponseFilter> filters) =>
      Match(filters, MatchMode.any);

  /// Returns `true` when **all** filters match (AND, short-circuit on first
  /// non-match).
  factory Match.all(List<ResponseFilter> filters) =>
      Match(filters, MatchMode.all);

  final List<ResponseFilter> filters;
  final MatchMode mode;

  @override
  bool matches(Response response) {
    if (filters.isEmpty) {
      return false;
    }
    switch (mode) {
      case MatchMode.any:
        for (final f in filters) {
          if (f.matches(response)) {
            return true;
          }
        }
        return false;
      case MatchMode.all:
        for (final f in filters) {
          if (!f.matches(response)) {
            return false;
          }
        }
        return filters.isNotEmpty;
    }
  }
}
