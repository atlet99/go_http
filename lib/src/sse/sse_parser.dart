import 'dart:async';

import 'sse_event.dart';

/// A [StreamTransformer] that parses a text stream into [SSEEvent]s.
///
/// Handles chunked input correctly — partial lines are buffered until the next
/// chunk arrives.  Follows the algorithm in the HTML Living Standard §9.2.6:
/// https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
///
/// ```dart
/// response.bytes
///   .transform(utf8.decoder)
///   .transform(const SSEParser())
///   .listen((event) => print(event.data));
/// ```
class SSEParser implements StreamTransformer<String, SSEEvent> {
  /// Creates an [SSEParser].
  const SSEParser();

  @override
  Stream<SSEEvent> bind(Stream<String> stream) {
    return Stream.eventTransformed(stream, _SSEParserSink.new);
  }

  @override
  StreamTransformer<RS, RT> cast<RS, RT>() {
    return StreamTransformer.castFrom(this);
  }
}

class _SSEParserSink implements EventSink<String> {
  _SSEParserSink(this._output);

  final EventSink<SSEEvent> _output;

  // Buffered partial line from previous chunk.
  String _buffer = '';

  // Accumulated fields for the current event.
  String _dataBuffer = '';
  String _eventType = 'message';
  String? _eventId;
  int? _retry;

  bool _hasData = false;

  @override
  void add(String chunk) {
    // Prepend any leftover from the last chunk.
    final text = _buffer + chunk;

    // Split on any line ending (LF, CR, CRLF).
    final lines = text.split(RegExp(r'\r\n|\r|\n'));

    // The last element may be a partial line — keep it buffered.
    _buffer = lines.removeLast();

    for (final line in lines) {
      _processLine(line);
    }
  }

  void _processLine(String line) {
    // Empty line → dispatch the accumulated event.
    if (line.isEmpty) {
      if (_hasData) {
        _output.add(
          SSEEvent(
            data: _dataBuffer,
            event: _eventType,
            id: _eventId,
            retry: _retry,
          ),
        );
      }
      _reset();
      return;
    }

    // Comment line (starts with ':') — ignore per spec.
    if (line.startsWith(':')) {
      return;
    }

    // Split on the first ':' only.
    final colonIndex = line.indexOf(':');
    String field;
    String value;
    if (colonIndex == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIndex);
      value = line.substring(colonIndex + 1);
      // Strip a single leading space from the value.
      if (value.startsWith(' ')) {
        value = value.substring(1);
      }
    }

    switch (field) {
      case 'data':
        if (_hasData) {
          _dataBuffer += '\n$value';
        } else {
          _dataBuffer = value;
          _hasData = true;
        }
      case 'event':
        _eventType = value;
      case 'id':
        // An empty id resets the last event ID (don't store empty).
        if (value.isNotEmpty) {
          _eventId = value;
        }
      case 'retry':
        final parsed = int.tryParse(value);
        if (parsed != null && parsed >= 0) {
          _retry = parsed;
        }
      default:
      // Unknown fields are ignored per spec.
    }
  }

  void _reset() {
    _dataBuffer = '';
    _eventType = 'message';
    _eventId = null;
    _retry = null;
    _hasData = false;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _output.addError(error, stackTrace);
  }

  @override
  void close() {
    // Process any remaining partial line left in the buffer.
    if (_buffer.isNotEmpty) {
      _processLine(_buffer);
      _buffer = '';
    }
    // Flush any remaining buffered data as a final event.
    if (_hasData) {
      _output.add(
        SSEEvent(
          data: _dataBuffer,
          event: _eventType,
          id: _eventId,
          retry: _retry,
        ),
      );
      _reset();
    }
    _output.close();
  }
}
