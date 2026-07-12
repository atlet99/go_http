import 'dart:math';
import 'dart:typed_data';

/// A non-file field of a `multipart/form-data` request.
class MultipartField {
  MultipartField(this.name, this.value, {Map<String, String>? headers})
      : headers = headers ?? const {};

  final String name;
  final String value;
  final Map<String, String> headers;
}

/// A file field of a `multipart/form-data` request.
///
/// Mirrors `httpx`'s `(filename, file[, content_type, headers])` tuple shapes
/// as a Dart class with optional [contentType]/[headers].
class MultipartFile {
  MultipartFile(
    this.field,
    this.fileName,
    this.data, {
    this.contentType,
    Map<String, String>? headers,
  }) : headers = headers ?? const {};

  factory MultipartFile.bytes(
    String field,
    String fileName,
    List<int> data, {
    String? contentType,
    Map<String, String>? headers,
  }) =>
      MultipartFile(
        field,
        fileName,
        data,
        contentType: contentType,
        headers: headers,
      );

  final String field;
  final String fileName;
  final List<int> data;
  final String? contentType;
  final Map<String, String> headers;

  String get resolvedContentType => contentType ?? _guessContentType(fileName);
}

/// Standalone `multipart/form-data` encoder — no external dependencies.
///
/// Build the parts, then send the rendered body with `contentType` as the
/// `Content-Type` header (the [GoHttpClient] does this automatically when a
/// [Multipart] is passed as the request body).
class Multipart {
  Multipart(
    this.fields,
    this.files, {
    String? boundary,
  }) : boundary = boundary ?? _generateBoundary();

  final List<MultipartField> fields;
  final List<MultipartFile> files;
  final String boundary;

  /// `multipart/form-data; boundary=...`
  String get contentType => 'multipart/form-data; boundary=$boundary';

  /// Total encoded length (known up-front — the transport sends
  /// `Content-Length`, no chunked encoding required).
  int get encodedLength {
    var n = 0;
    for (final f in fields) {
      n += _renderField(boundary, f).length;
    }
    for (final f in files) {
      n += _renderFile(boundary, f).length;
    }
    n += '--$boundary--\r\n'.length;
    return n;
  }

  /// Render the whole body to bytes.
  Uint8List render() {
    final out = <int>[];
    for (final f in fields) {
      out.addAll(_renderField(boundary, f));
    }
    for (final f in files) {
      out.addAll(_renderFile(boundary, f));
    }
    out.addAll('--$boundary--\r\n'.codeUnits);
    return Uint8List.fromList(out);
  }

  /// Stream the rendered body in [chunkSize] chunks (default 64 KiB).
  Stream<List<int>> stream({int chunkSize = 64 * 1024}) async* {
    final bytes = render();
    for (var i = 0; i < bytes.length; i += chunkSize) {
      yield bytes.sublist(i, min(i + chunkSize, bytes.length));
    }
  }

  /// Extract the boundary token from an existing `Content-Type` header, or
  /// `null` if none is present.
  static String? boundaryFromContentType(String? contentType) {
    if (contentType == null) {
      return null;
    }
    final match = _boundaryRegExp.firstMatch(contentType);
    return match?.group(2);
  }
}

final _boundaryRegExp = RegExp(r'boundary=("?)([^";]+)\1');

String _generateBoundary() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

List<int> _renderField(String boundary, MultipartField f) {
  final sb = StringBuffer()
    ..write('--')
    ..write(boundary)
    ..write('\r\n')
    ..write('Content-Disposition: form-data; name="${_escapeAttr(f.name)}"');
  for (final e in f.headers.entries) {
    sb.write('\r\n${e.key}: ${e.value}');
  }
  sb.write('\r\n\r\n');
  sb.write(f.value);
  sb.write('\r\n');
  return sb.toString().codeUnits;
}

List<int> _renderFile(String boundary, MultipartFile f) {
  final sb = StringBuffer()
    ..write('--')
    ..write(boundary)
    ..write('\r\n')
    ..write(
      'Content-Disposition: form-data; name="${_escapeAttr(f.field)}"; '
      'filename="${_escapeAttr(f.fileName)}"',
    )
    ..write('\r\n')
    ..write('Content-Type: ${f.resolvedContentType}');
  for (final e in f.headers.entries) {
    sb.write('\r\n${e.key}: ${e.value}');
  }
  sb.write('\r\n\r\n');
  return <int>[
    ...sb.toString().codeUnits,
    ...f.data,
    ...'\r\n'.codeUnits,
  ];
}

/// HTML5 form-data attribute escaping: drop CR/LF/control chars and percent-
/// encode `"` so it cannot break the quoted `name="..."` / `filename="..."`.
String _escapeAttr(String s) {
  final buf = StringBuffer();
  for (final r in s.runes) {
    if (r == 0x0D || r == 0x0A) {
      continue; // drop CR/LF
    }
    if (r == 0x22) {
      buf.write('%22'); // escape quote
      continue;
    }
    if (r < 0x20 || r == 0x7F) {
      continue; // drop other control chars
    }
    buf.writeCharCode(r);
  }
  return buf.toString();
}

const _extensionMime = {
  'txt': 'text/plain',
  'html': 'text/html',
  'htm': 'text/html',
  'css': 'text/css',
  'json': 'application/json',
  'js': 'application/javascript',
  'xml': 'application/xml',
  'csv': 'text/csv',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'mp3': 'audio/mpeg',
  'mp4': 'video/mp4',
  'wav': 'audio/wav',
  'bin': 'application/octet-stream',
};

String _guessContentType(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot >= 0 && dot < fileName.length - 1) {
    final ext = fileName.substring(dot + 1).toLowerCase();
    final mime = _extensionMime[ext];
    if (mime != null) {
      return mime;
    }
  }
  return 'application/octet-stream';
}
