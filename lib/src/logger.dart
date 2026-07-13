export 'logger_stub.dart' if (dart.library.io) 'logger_io.dart';

typedef Logger = void Function(Object? value);

void defaultLog(Object? value) => print(value);
