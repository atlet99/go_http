import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:go_http/src/decoders.dart' as decoders;
import 'package:test/test.dart';

void main() {
  group('decodeContentEncoding', () {
    test('null encoding returns body unchanged', () {
      final input = Uint8List.fromList([1, 2, 3]);
      expect(decoders.decodeContentEncoding(input, null), same(input));
    });

    test('empty encoding returns body unchanged', () {
      final input = Uint8List.fromList([1, 2, 3]);
      expect(decoders.decodeContentEncoding(input, ''), same(input));
    });

    test('identity encoding returns body unchanged', () {
      final input = Uint8List.fromList([1, 2, 3]);
      expect(decoders.decodeContentEncoding(input, 'identity'), same(input));
    });

    test('unknown encoding passes through silently', () {
      final input = Uint8List.fromList([1, 2, 3]);
      final result = decoders.decodeContentEncoding(input, 'x-unknown');
      expect(result, [1, 2, 3]);
    });

    test('gzip decode works', () {
      final original = utf8.encode('hello world') as List<int>;
      final compressed = GZipCodec().encode(original);
      final result = decoders.decodeContentEncoding(compressed, 'gzip');
      expect(utf8.decode(result), 'hello world');
    });

    test('deflate (zlib) decode works', () {
      final original = utf8.encode('deflate test');
      final compressed = ZLibCodec(raw: false).encode(original);
      final result = decoders.decodeContentEncoding(compressed, 'deflate');
      expect(utf8.decode(result), 'deflate test');
    });

    test('deflate (raw) decode works via fallback', () {
      final original = utf8.encode('raw deflate');
      final compressed = ZLibCodec(raw: true).encode(original);
      final result = decoders.decodeContentEncoding(compressed, 'deflate');
      expect(utf8.decode(result), 'raw deflate');
    });

    test('stacked gzip, deflate', () {
      final original = utf8.encode('stacked encoding');
      final deflated = ZLibCodec(raw: false).encode(original);
      final gzipped = GZipCodec().encode(deflated);
      final result = decoders.decodeContentEncoding(gzipped, 'gzip, deflate');
      expect(utf8.decode(result), 'stacked encoding');
    });
  });

  group('ContentDecoder registry', () {
    test('gzip and deflate are registered by default', () {
      expect(decoders.contentDecoders.containsKey('gzip'), isTrue);
      expect(decoders.contentDecoders.containsKey('deflate'), isTrue);
    });

    test('br and zstd are absent by default', () {
      expect(decoders.contentDecoders.containsKey('br'), isFalse);
      expect(decoders.contentDecoders.containsKey('zstd'), isFalse);
    });

    test('registerBrotli adds br decoder', () {
      decoders.registerBrotli(() => _IdentityDecoder());
      expect(decoders.contentDecoders.containsKey('br'), isTrue);
      final decoder = decoders.contentDecoders['br']!();
      expect(decoder.decode([1, 2, 3]), [1, 2, 3]);
      // Clean up
      decoders.contentDecoders.remove('br');
    });

    test('registerZstd adds zstd decoder', () {
      decoders.registerZstd(() => _IdentityDecoder());
      expect(decoders.contentDecoders.containsKey('zstd'), isTrue);
      final decoder = decoders.contentDecoders['zstd']!();
      expect(decoder.decode([1, 2, 3]), [1, 2, 3]);
      // Clean up
      decoders.contentDecoders.remove('zstd');
    });
  });
}

/// A passthrough decoder for testing.
class _IdentityDecoder extends decoders.ContentDecoder {
  @override
  List<int> decode(List<int> data) => data;

  @override
  List<int> flush() => [];
}
