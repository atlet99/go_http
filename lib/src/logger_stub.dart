/// Fallback log output to stdout (used on Web where `dart:io` is unavailable).
void stderrLog(Object? value) => print(value);
