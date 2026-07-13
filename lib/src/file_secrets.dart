import 'dart:convert';
import 'dart:io';

import 'auth.dart';

/// Load authentication secrets from a JSON file.
///
/// File format:
/// ```json
/// {"username": "admin", "password": "secret123", "token": "eyJhbG..."}
/// ```
///
/// With named sections:
/// ```json
/// {"production": {"username": "admin", "password": "secret123"}}
/// ```
///
/// Usage:
/// ```dart
/// final auth = await FileSecrets.basicAuth('secrets.json', section: 'prod');
/// final client = GoHttpClient(
///   interceptors: [AuthInterceptor(auth: auth)],
/// );
/// ```
///
/// ponytail: only JSON format; extend with YAML / .netrc if needed.
class FileSecrets {
  FileSecrets._();

  /// Load a JSON file and extract [BasicAuth] credentials.
  ///
  /// Throws [FileSecretsError] if the file is missing, malformed, or the
  /// required keys are absent.
  static Future<BasicAuth> basicAuth(
    String path, {
    String? section,
    String usernameKey = 'username',
    String passwordKey = 'password',
  }) async {
    final data = await _load(path, section);
    final username = data[usernameKey];
    final password = data[passwordKey];
    if (username == null || password == null) {
      throw FileSecretsError(
        'Missing "$usernameKey" or "$passwordKey" in ${_desc(path, section)}',
      );
    }
    return BasicAuth(username, password);
  }

  /// Load a JSON file and create a [FunctionAuth] that sets a Bearer token
  /// via the [Authorization] header.
  static Future<FunctionAuth> bearerToken(
    String path, {
    String? section,
    String tokenKey = 'token',
    String headerName = 'Authorization',
    String headerPrefix = 'Bearer ',
  }) async {
    final data = await _load(path, section);
    final token = data[tokenKey];
    if (token == null) {
      throw FileSecretsError(
        'Missing "$tokenKey" in ${_desc(path, section)}',
      );
    }
    return FunctionAuth((req) {
      return req.copyWith(
        headers: req.headers.copy()
          ..[headerName] = '$headerPrefix$token',
      );
    });
  }

  static Future<Map<String, String>> _load(
    String path,
    String? section,
  ) async {
    final file = File(path);
    String contents;
    try {
      contents = await file.readAsString();
    } on FileSystemException catch (e) {
      throw FileSecretsError('Cannot read secrets file "$path": ${e.message}');
    }

    Object decoded;
    try {
      decoded = json.decode(contents);
    } on FormatException {
      throw FileSecretsError('Invalid JSON in "$path"');
    }

    Map<String, dynamic> map;
    if (section != null) {
      final nested = (decoded as Map?)?[section];
      if (nested == null || nested is! Map) {
        throw FileSecretsError(
          'Section "$section" not found in ${_desc(path)}',
        );
      }
      map = nested.cast<String, dynamic>();
    } else {
      map = (decoded as Map).cast<String, dynamic>();
    }

    return map.map((k, v) => MapEntry(k, v.toString()));
  }

  static String _desc(String path, [String? section]) {
    final base = 'secrets file "$path"';
    return section != null ? '$base section "$section"' : base;
  }
}

/// Error thrown by [FileSecrets] methods.
class FileSecretsError implements Exception {
  FileSecretsError(this.message);
  final String message;
  @override
  String toString() => 'FileSecretsError: $message';
}
