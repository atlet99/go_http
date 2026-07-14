import 'dart:async';
import 'dart:convert';

/// Returns a [StreamTransformer] that decodes a byte stream into a string
/// stream, handling chunk boundaries correctly for variable-length encodings
/// (UTF-8, UTF-16, etc.).
///
/// ```dart
/// response.bytes
///   .transform(textStreamDecoder())
///   .listen((chunk) => print(chunk));
/// ```
StreamTransformer<List<int>, String> textStreamDecoder({
  String encoding = 'utf-8',
}) {
  final enc = Encoding.getByName(encoding) ?? utf8;
  return enc.decoder;
}

/// Returns a [StreamTransformer] that splits a string stream into lines.
///
/// ```dart
/// response.bytes
///   .transform(textStreamDecoder())
///   .transform(lineStreamDecoder())
///   .listen((line) => print(line));
/// ```
StreamTransformer<String, String> lineStreamDecoder() {
  return const LineSplitter();
}
