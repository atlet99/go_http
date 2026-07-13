import 'dart:convert' show jsonEncode, utf8;
import 'dart:io' show File, IOSink;

import 'package:meta/meta.dart';

import 'request.dart';
import 'response.dart';

/// Outcome of a single request in a batch — success carries a [Response],
/// failure carries an error (never thrown). Mirrors httpx/runner `Result`,
/// where one bad target must not abort 100k good ones.
@immutable
class Result<T> {
  Result._(this._ok, this._response, this._error, this._request);

  factory Result.ok(Response<T> response) =>
      Result._(true, response, null, null);

  factory Result.fail(Object error, {Request? request}) =>
      Result._(false, null, error, request);

  final bool _ok;
  final Response<T>? _response;
  final Object? _error;
  final Request? _request;

  bool get isOk => _ok;
  bool get isError => !_ok;

  Response<T> get response {
    final r = _response;
    if (r == null) {
      throw StateError('Result is an error');
    }
    return r;
  }

  Object get error {
    final e = _error;
    if (e == null) {
      throw StateError('Result is ok');
    }
    return e;
  }

  R when<R>({
    required R Function(Response<T>) ok,
    required R Function(Object error, Request? request) fail,
  }) =>
      _ok ? ok(_response as Response<T>) : fail(_error!, _request);
}

/// Pluggable output SPI — one writer owns its [IOSink] (single-writer
/// file I/O, no shared locks). `write` is called per result; `close` flushes.
abstract class ResultSink {
  factory ResultSink.jsonl(String path) => JsonlSink(File(path).openWrite());

  factory ResultSink.csv(String path) => CsvSink(File(path).openWrite());

  void write(Result result);

  Future<void> close();
}

/// Newline-delimited JSON sink.
class JsonlSink implements ResultSink {
  JsonlSink(this._sink);

  final IOSink _sink;

  @override
  void write(Result result) {
    _sink.add(utf8.encode('${jsonEncode(_toMap(result))}\n'));
  }

  @override
  Future<void> close() => _sink.close();

  static Map<String, Object?> _toMap(Result result) => result.when(
        ok: (resp) => {
          'ok': true,
          'url': resp.request.uri.toString(),
          'status': resp.statusCode,
          'method': resp.request.method.name,
          'headers': resp.headers.toMap(),
          'bodyBytes':
              resp.data is List<int> ? (resp.data as List<int>).length : null,
          'elapsedMs': resp.elapsed.inMilliseconds,
        },
        fail: (err, req) => {
          'ok': false,
          'url': req?.uri.toString(),
          'error': err.toString(),
        },
      );
}

/// CSV sink with CSV-injection sanitization (prefix `=`,`+`,`-`,`@`
/// cells with a single quote). Columns are fixed for simplicity.
class CsvSink implements ResultSink {
  CsvSink(this._sink, {this.columns = const ['ok', 'url', 'status', 'error']})
      : _wroteHeader = false;

  final IOSink _sink;
  final List<String> columns;
  bool _wroteHeader;

  @override
  void write(Result result) {
    if (!_wroteHeader) {
      _sink.add(utf8.encode('${columns.join(',')}\n'));
      _wroteHeader = true;
    }
    final row = result.when(
      ok: (resp) => [
        'true',
        resp.request.uri.toString(),
        resp.statusCode.toString(),
        '',
      ],
      fail: (err, req) => [
        'false',
        req?.uri.toString() ?? '',
        '',
        err.toString(),
      ],
    );
    _sink.add(utf8.encode('${row.map(_csvCell).join(',')}\n'));
  }

  @override
  Future<void> close() => _sink.close();

  static String _csvCell(String value) {
    var v = value;
    if (v.startsWith(RegExp(r'[=+\-@]'))) {
      v = "'$v";
    }
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      v = '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
