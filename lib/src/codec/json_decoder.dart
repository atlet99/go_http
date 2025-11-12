import 'dart:convert';

import 'decoder.dart';

/// JSON decoder for response data
class JsonDecoder implements Decoder<dynamic> {
  @override
  dynamic decode(dynamic data) {
    if (data is String) {
      return jsonDecode(data);
    } else if (data is List<int>) {
      return jsonDecode(utf8.decode(data));
    }
    return data;
  }
}
