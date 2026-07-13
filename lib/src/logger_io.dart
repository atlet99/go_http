import 'dart:io' show stderr;

/// Log output to stderr (available on IO platforms).
void stderrLog(Object? value) => stderr.writeln(value);
