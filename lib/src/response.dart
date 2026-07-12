import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';
import 'headers.dart';
import 'request.dart';

/// HTTP response representation.
class Response<T> {
  Response({
    required this.request,
    required this.statusCode,
    Object? headers,
    this.data,
    this.statusMessage,
    this.elapsed = Duration.zero,
    List<Response>? history,
  })  : headers = headers is Headers ? headers : Headers(headers),
        history = history ?? const [];

  final Request request;
  final int statusCode;
  final Headers headers;
  final T? data;
  final String? statusMessage;

  /// Time spent on the full request/response cycle (set by the client).
  final Duration elapsed;

  /// Redirect chain (intermediate responses), earliest first.
  final List<Response> history;

  /// 1xx — informational.
  bool get isInformational => statusCode >= 100 && statusCode < 200;

  /// 2xx — success.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// 3xx — redirection.
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// 4xx — client error.
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// 5xx — server error.
  bool get isServerError => statusCode >= 500 && statusCode < 600;

  /// 4xx or 5xx.
  bool get isError => statusCode >= 400 && statusCode < 600;

  /// A real redirect: status in {301,302,303,307,308} AND a `Location` header
  /// is present. (304/300 are 3xx but not navigable redirects.)
  bool get hasRedirectLocation {
    return (statusCode == 301 ||
            statusCode == 302 ||
            statusCode == 303 ||
            statusCode == 307 ||
            statusCode == 308) &&
        _header('location') != null;
  }

  /// Alias for [statusMessage] (RFC 9110 "reason phrase").
  String? get reasonPhrase => statusMessage;

  /// HTTP version string if known (e.g. `"HTTP/1.1"`), otherwise null.
  String? get httpVersion => _header('http-version');

  /// The charset declared by the `Content-Type` response header, or `null`.
  String? get charsetEncoding => _parseCharset(_header('content-type'));

  /// The effective charset used to decode [text]. Priority:
  /// caller-set [encoding] → [charsetEncoding] → `utf-8`.
  String get encoding => _encoding ?? charsetEncoding ?? 'utf-8';
  String? _encoding;

  /// Override the charset used by [text].
  set encoding(String value) {
    _encoding = value;
  }

  /// Decoded body as text, using [encoding].
  String get text {
    final bytes = _bytes;
    if (bytes == null) {
      return '';
    }
    return _decodeWith(bytes, encoding);
  }

  /// Decode the body as JSON, using [text].
  Object? json() {
    final body = text;
    if (body.isEmpty) {
      return null;
    }
    return jsonDecode(body);
  }

  /// Throw [HttpResponseError] if the status is an error (4xx/5xx), otherwise
  /// return `this` for chaining.
  Response<T> raiseForStatus() {
    if (isError) {
      throw HttpResponseError(request: request, response: this);
    }
    return this;
  }

  // --- internals ---

  Uint8List? get _bytes {
    final d = data;
    if (d is Uint8List) {
      return d;
    }
    if (d is List<int>) {
      return Uint8List.fromList(d);
    }
    if (d is String) {
      return Uint8List.fromList(utf8.encode(d));
    }
    return null;
  }

  String? _header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  static String _decodeWith(Uint8List bytes, String charset) {
    final name = charset.toLowerCase();
    if (name == 'utf-8' || name == 'utf8' || name.isEmpty) {
      return utf8.decode(bytes, allowMalformed: true);
    }
    // ponytail: latin1 covers all 256 byte values (safe fallback for odd
    // legacy charsets); full charset support is a follow-up (1A.6).
    return latin1.decode(bytes);
  }

  static String? _parseCharset(String? contentType) {
    if (contentType == null) {
      return null;
    }
    for (final part in contentType.split(';')) {
      final trimmed = part.trim().toLowerCase();
      if (trimmed.startsWith('charset=')) {
        return trimmed.substring(8).replaceAll('"', '');
      }
    }
    return null;
  }

  Response<R> copyWith<R>({
    Request? request,
    int? statusCode,
    Object? headers,
    R? data,
    String? statusMessage,
    Duration? elapsed,
    List<Response>? history,
  }) {
    return Response<R>(
      request: request ?? this.request,
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      data: data ?? (this.data as R?),
      statusMessage: statusMessage ?? this.statusMessage,
      elapsed: elapsed ?? this.elapsed,
      history: history ?? this.history,
    );
  }
}
