import 'dart:async';
import 'dart:convert';

/// A [StreamTransformer] that decodes HTTP/1.1 chunked transfer encoding
/// and extracts trailer headers.
///
/// Input: raw bytes from the wire (chunked-encoded body).
/// Output: decoded body chunks as [ChunkedPart] events, followed by a
/// final [ChunkedComplete] with the extracted trailers.
///
/// RFC 7230 §4.1:
/// ```text
/// chunked-body   = *chunk
///                  last-chunk
///                  trailer-part
///                  CRLF
///
/// last-chunk     = 1*("0") [ chunk-ext ] CRLF
/// trailer-part   = *( header-field CRLF )
/// ```
///
/// ```dart
/// final result = await socket
///     .transform(ChunkedDecoder())
///     .toList();
/// // result.last is ChunkedComplete with trailers
/// ```
class ChunkedDecoder implements StreamTransformer<List<int>, ChunkedEvent> {
  /// Creates a [ChunkedDecoder].
  const ChunkedDecoder();

  @override
  Stream<ChunkedEvent> bind(Stream<List<int>> stream) {
    return Stream.eventTransformed(stream, (sink) => _ChunkedDecoderSink(sink));
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() {
    return StreamTransformer.castFrom(this);
  }
}

/// An event emitted by [ChunkedDecoder].
sealed class ChunkedEvent {}

/// A decoded body chunk.
class ChunkedPart extends ChunkedEvent {
  /// Creates a [ChunkedPart] with [data].
  ChunkedPart(this.data);

  /// The decoded body bytes for this chunk.
  final List<int> data;
}

/// Signals the end of the chunked body and carries any trailer headers.
class ChunkedComplete extends ChunkedEvent {
  /// Creates a [ChunkedComplete] with [trailers].
  ChunkedComplete(this.trailers);

  /// Trailer headers sent after the last chunk, or empty map.
  final Map<String, String> trailers;
}

class _ChunkedDecoderSink implements EventSink<List<int>> {
  _ChunkedDecoderSink(this._output);

  final EventSink<ChunkedEvent> _output;

  String _buffer = '';
  _ChunkedPhase _phase = _ChunkedPhase.size;
  int _remaining = 0;
  final _trailers = <String, String>{};

  @override
  void add(List<int> chunk) {
    _buffer += utf8.decode(chunk, allowMalformed: true);
    _process();
  }

  void _process() {
    while (true) {
      switch (_phase) {
        case _ChunkedPhase.size:
          if (!_buffer.contains('\r\n')) {
            return;
          }
          final idx = _buffer.indexOf('\r\n');
          final sizeLine = _buffer.substring(0, idx).trim();
          _buffer = _buffer.substring(idx + 2);

          final hex = sizeLine.split(';').first.trim();
          final size = int.tryParse(hex, radix: 16);
          if (size == null || size < 0) {
            _output.addError(
              FormatException('Invalid chunk size: $hex'),
            );
            return;
          }

          _remaining = size;
          if (size == 0) {
            _phase = _ChunkedPhase.trailers;
          } else {
            _phase = _ChunkedPhase.data;
          }

        case _ChunkedPhase.data:
          if (_buffer.length < _remaining + 2) {
            return;
          }
          final data = _buffer.substring(0, _remaining);
          _buffer = _buffer.substring(_remaining + 2); // skip \r\n
          _output.add(ChunkedPart(utf8.encode(data)));
          _phase = _ChunkedPhase.size;

        case _ChunkedPhase.trailers:
          // Accumulate until we see the final blank line.
          while (_buffer.contains('\r\n')) {
            final idx = _buffer.indexOf('\r\n');
            final line = _buffer.substring(0, idx);
            _buffer = _buffer.substring(idx + 2);

            if (line.isEmpty) {
              // Final blank line — done.
              _output.add(
                ChunkedComplete(
                  Map.unmodifiable(_trailers),
                ),
              );
              _output.close();
              return;
            }

            final colonIdx = line.indexOf(':');
            if (colonIdx > 0) {
              final key = line.substring(0, colonIdx).trim();
              var value = line.substring(colonIdx + 1).trim();
              // Strip single leading space.
              if (value.startsWith(' ')) {
                value = value.substring(1);
              }
              _trailers[key] = value;
            }
          }
          return; // wait for more data
      }
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _output.addError(error, stackTrace);
  }

  @override
  void close() {
    // If we were waiting for the final blank line and buffer is empty,
    // emit what we have.
    if (_phase == _ChunkedPhase.trailers && _buffer.trim().isEmpty) {
      _output.add(ChunkedComplete(Map.unmodifiable(_trailers)));
    }
    _output.close();
  }
}

enum _ChunkedPhase { size, data, trailers }
