/// A single Server-Sent Event (SSE).
///
/// Parsed from the wire format defined in the HTML Living Standard §9.2:
/// https://html.spec.whatwg.org/multipage/server-sent-events.html
class SSEEvent {
  /// Creates an [SSEEvent] with the given fields.
  const SSEEvent({
    this.data = '',
    this.event = 'message',
    this.id,
    this.retry,
  });

  /// The event payload. Multiple `data:` lines are joined with `\n`.
  final String data;

  /// The event type. Defaults to `"message"` per the spec.
  final String event;

  /// The event ID, or `null` if none was set.
  final String? id;

  /// The suggested reconnection interval in milliseconds, or `null`.
  final int? retry;

  /// Whether this event carries a [retry] value.
  bool get hasRetry => retry != null;

  /// Whether this event carries an [id].
  bool get hasId => id != null;

  @override
  String toString() => 'SSEEvent(event: $event, data: $data)';
}
