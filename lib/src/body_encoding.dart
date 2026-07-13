import 'dart:convert' show jsonEncode, utf8;

import 'headers.dart';

/// Result of [encodeRequest]: final headers (with `Content-Type` set when
/// applicable) and the transport-ready body.
class EncodedBody {
  EncodedBody(this.headers, this.body);

  final Headers headers;
  final Object? body;
}

/// Unified request-body dispatch ladder (httpx `_content.py`).
///
/// - [json] set → `application/json` (`jsonEncode` throws on `NaN`/
///   `Infinity`; bytes are UTF-8).
/// - [data] is a `Map` → `application/x-www-form-urlencoded`.
/// - [content] (`String` / bytes / [Stream] / [Multipart]) → used as-is.
/// - otherwise → empty body, headers unchanged.
///
/// ponytail: `ensure_ascii:false` nuance (`jsonEncode` ASCII-escapes by
/// default) is deferred — output is ASCII-safe UTF-8.
EncodedBody encodeRequest({
  Object? content,
  Object? data,
  Object? json,
  Headers? headers,
}) {
  final h = (headers ?? Headers({})).copy();
  if (json != null) {
    h['content-type'] ??= 'application/json';
    return EncodedBody(h, utf8.encode(jsonEncode(json)));
  }
  if (data is Map) {
    h['content-type'] ??= 'application/x-www-form-urlencoded';
    final body = data.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key.toString())}=${Uri.encodeQueryComponent(e.value.toString())}',
        )
        .join('&');
    return EncodedBody(h, body);
  }
  // content (bytes / string / stream / multipart) → as-is,
  // or [data] when it was passed as a non-Map raw body.
  return EncodedBody(h, content ?? data);
}

/// Returns the byte length of [body] when known deterministically,
/// or `null` when the length cannot be determined without consuming the body
/// (e.g. a [Stream]).
///
/// Useful for deciding between `Content-Length` and chunked transfer encoding:
/// - `String` → UTF-8 encoded length
/// - `List<int>` / `Uint8List` → length
/// - `Stream<List<int>>` → `null` (unknown, use chunked)
int? peekLength(Object? body) {
  if (body == null) {
    return 0;
  }
  if (body is String) {
    return utf8.encode(body).length;
  }
  if (body is List<int>) {
    return body.length;
  }
  if (body is Stream<List<int>>) {
    return null;
  }
  return null;
}
