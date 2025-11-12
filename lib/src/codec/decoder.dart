/// Abstract interface for response decoders
abstract class Decoder<T> {
  /// Decode response data
  T decode(dynamic data);
}
