import 'dart:typed_data';

import 'decoder.dart';

/// Bytes decoder for response data
class BytesDecoder implements Decoder<Uint8List> {
  @override
  Uint8List decode(dynamic data) {
    if (data is Uint8List) {
      return data;
    } else if (data is List<int>) {
      return Uint8List.fromList(data);
    } else if (data is String) {
      return Uint8List.fromList(data.codeUnits);
    }
    throw ArgumentError('Cannot decode data to bytes: ${data.runtimeType}');
  }
}
