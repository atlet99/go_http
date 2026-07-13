import 'dart:io';

/// Decodes a response body according to its [Content-Encoding].
List<int> decodeContentEncoding(List<int> body, String? encoding) {
  if (encoding == null || encoding.isEmpty) {
    return body;
  }
  final names = encoding.split(',');
  final decoders = <ContentDecoder>[];
  for (final name in names) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.isEmpty || trimmed == 'identity') {
      continue;
    }
    final factory = contentDecoders[trimmed];
    if (factory != null) {
      decoders.add(factory());
    }
  }
  if (decoders.isEmpty) {
    return body;
  }
  if (decoders.length == 1) {
    return decoders[0].decode(body);
  }
  return MultiDecoder(decoders).decode(body);
}

/// A single content-encoding decoder.
abstract class ContentDecoder {
  List<int> decode(List<int> data);
  List<int> flush();
}

/// Global registry of [ContentDecoder] factories, keyed by encoding name.
///
/// `gzip` and `deflate` are always present (backed by `dart:io`).
/// `br` and `zstd` are absent by default — register them with
/// [registerBrotli] / [registerZstd] when the corresponding packages
/// are available.
final Map<String, ContentDecoder Function()> contentDecoders = {
  'gzip': () => _GzipDecoder(),
  'deflate': () => _DeflateDecoder(),
};

/// Register a brotli decoder factory (e.g. from `package:brotli`).
void registerBrotli(ContentDecoder Function() factory) {
  contentDecoders['br'] = factory;
}

/// Register a zstd decoder factory (e.g. from `package:zstd`).
void registerZstd(ContentDecoder Function() factory) {
  contentDecoders['zstd'] = factory;
}

/// GZIP decoder backed by `dart:io` [GZipCodec].
class _GzipDecoder extends ContentDecoder {
  @override
  List<int> decode(List<int> data) => GZipCodec().decode(data);

  @override
  List<int> flush() => [];
}

/// DEFLATE decoder with ambiguity fallback.
///
/// HTTP `Content-Encoding: deflate` nominally means raw DEFLATE (RFC 1951),
/// but many servers send zlib-wrapped (RFC 1950). This decoder tries zlib
/// first, then falls back to raw on format error.
class _DeflateDecoder extends ContentDecoder {
  @override
  List<int> decode(List<int> data) {
    try {
      return ZLibCodec(raw: false).decode(data);
    } on FormatException {
      return ZLibCodec(raw: true).decode(data);
    }
  }

  @override
  List<int> flush() => [];
}

/// Decodes stacked content-encodings left-to-right.
///
/// Not exported — instantiated by [decodeContentEncoding] when more than
/// one encoding is present.
class MultiDecoder extends ContentDecoder {
  MultiDecoder(List<ContentDecoder> decoders) : _decoders = decoders;

  final List<ContentDecoder> _decoders;

  @override
  List<int> decode(List<int> data) {
    var result = data;
    for (final d in _decoders) {
      result = d.decode(result);
    }
    return result;
  }

  @override
  List<int> flush() => [];
}
