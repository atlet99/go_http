/// Decodes a response body according to its [Content-Encoding].
///
/// On web (where `dart:io` is unavailable) this returns the body unchanged.
/// Browser `fetch` handles gzip decompression natively, so this
/// is a no-op.
List<int> decodeContentEncoding(List<int> body, String? encoding) => body;

/// A single content-encoding decoder.
abstract class ContentDecoder {
  List<int> decode(List<int> data);
  List<int> flush();
}

/// Global registry of [ContentDecoder] factories.
///
/// On web the built-in `gzip` and `deflate` decoders are NOT available
/// because they depend on `dart:io`. Register custom decoders via
/// [registerBrotli] / [registerZstd] when the corresponding packages
/// are available.
final Map<String, ContentDecoder Function()> contentDecoders = {};

void registerBrotli(ContentDecoder Function() factory) {
  contentDecoders['br'] = factory;
}

void registerZstd(ContentDecoder Function() factory) {
  contentDecoders['zstd'] = factory;
}
