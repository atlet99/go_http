import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/// Decode [json] in a background isolate to avoid blocking the event loop.
///
/// Returns the decoded object (typically `Map` or `List`).  Useful for
/// large payloads (10 MB+) where `jsonDecode` would stall the UI/main isolate.
///
/// ```dart
/// final data = await parseJsonInIsolate(largeJsonString);
/// ```
///
/// `ponytail:` cost = isolate spawn + byte copy.  For small payloads the
/// overhead exceeds the benefit; use `jsonDecode` directly unless profiling
/// shows a bottleneck.
Future<Object?> parseJsonInIsolate(String json) {
  return Isolate.run(() => jsonDecode(json));
}

/// A [StreamTransformer] that parses NDJSON (newline-delimited JSON).
///
/// Each line is independently decoded via `jsonDecode`.  Blank lines and
/// lines starting with `//` (comments) are silently skipped.
///
/// ```dart
/// response.bytes
///     .transform(utf8.decoder)
///     .transform(const NdjsonParser())
///     .listen((obj) => print(obj));
/// ```
class NdjsonParser implements StreamTransformer<String, dynamic> {
  /// Creates an [NdjsonParser].
  const NdjsonParser();

  @override
  Stream<dynamic> bind(Stream<String> stream) {
    return stream
        .transform(const LineSplitter())
        .where(
          (line) => line.trim().isNotEmpty && !line.trimLeft().startsWith('//'),
        )
        .map((line) => jsonDecode(line));
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() {
    return StreamTransformer.castFrom(this);
  }
}
