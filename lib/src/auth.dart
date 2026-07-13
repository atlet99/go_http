import 'dart:convert' show base64, utf8;
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show md5, sha256;

import 'request.dart';

/// Pluggable auth strategy (httpx `AuthStrategy`, 1A.7).
///
/// Stateless transform of a [Request]; multi-step flows (digest) are
/// driven by [AuthInterceptor]'s 401 challenge path rather than a `send`
/// callback, to reuse the existing retry machinery. ponytail: this is the
/// simpler `Request apply(Request)` shape from 1A.7, not the async
/// `apply(req, send)` generator from 1B.10.
abstract class Auth {
  Request apply(Request request);
}

/// `Basic` auth: `Authorization: Basic base64(user:pass)`.
class BasicAuth extends Auth {
  BasicAuth(this.username, this.password);

  final String username;
  final String password;

  @override
  Request apply(Request request) {
    final token = base64.encode(utf8.encode('$username:$password'));
    return request.copyWith(
      headers: request.headers.copy()..['Authorization'] = 'Basic $token',
    );
  }
}

/// Auth from a plain function — the least-code way to attach a header.
class FunctionAuth extends Auth {
  FunctionAuth(this.transform);

  final Request Function(Request) transform;

  @override
  Request apply(Request request) => transform(request);
}

/// `Digest` auth — RFC 2617 / 7616 (MD5 / SHA-256, qop, cnonce,
/// nonce-count). The first request goes out without auth; the interceptor
/// reads the `401` `WWW-Authenticate` challenge and calls [buildHeader].
class DigestAuth extends Auth {
  DigestAuth(this.username, this.password);

  final String username;
  final String password;

  @override
  Request apply(Request request) => request;

  String buildHeader(Request request, String challenge) {
    final p = _parseChallenge(challenge);
    final realm = p['realm'] ?? '';
    final nonce = p['nonce'] ?? '';
    final opaque = p['opaque'];
    final algorithm = (p['algorithm'] ?? 'MD5').toUpperCase();
    final qopRaw = p['qop'];
    final qop = qopRaw?.split(',').map((e) => e.trim()).firstWhere(
          (e) => e == 'auth' || e == 'auth-int',
          orElse: () => 'auth',
        );

    var uri = request.uri.path.isEmpty ? '/' : request.uri.path;
    if (request.uri.query.isNotEmpty) {
      uri += '?${request.uri.query}';
    }

    final ha1 = _h('$username:$realm:$password', algorithm);
    final ha2 = qop == 'auth-int'
        ? _h('${request.method.name}:$uri:${_h('', algorithm)}', algorithm)
        : _h('${request.method.name}:$uri', algorithm);
    final cnonce = _cnonce();
    final nc = '00000001';
    final response = qopRaw == null
        ? _h('$ha1:$nonce:$ha2', algorithm)
        : _h('$ha1:$nonce:$nc:$cnonce:$qop:$ha2', algorithm);

    final fields = [
      'username="$username"',
      'realm="$realm"',
      'nonce="$nonce"',
      'uri="$uri"',
      'response="$response"',
      if (algorithm != 'MD5') 'algorithm=$algorithm',
      if (opaque != null) 'opaque="$opaque"',
      if (qopRaw != null) 'qop=$qop',
      if (qopRaw != null) 'nc=$nc',
      if (qopRaw != null) 'cnonce="$cnonce"',
    ];
    return 'Digest ${fields.join(', ')}';
  }

  static Map<String, String> _parseChallenge(String challenge) {
    final map = <String, String>{};
    final body =
        challenge.startsWith('Digest') ? challenge.substring(6) : challenge;
    final re = RegExp(r'(\w+)=(?:"([^"]*)"|([^,]*))');
    for (final m in re.allMatches(body)) {
      map[m.group(1)!] = (m.group(2) ?? m.group(3))!.trim();
    }
    return map;
  }

  static String _h(String s, String algorithm) {
    final bytes = utf8.encode(s);
    final digest = algorithm == 'SHA-256' || algorithm == 'SHA256'
        ? sha256.convert(bytes).bytes
        : md5.convert(bytes).bytes;
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _cnonce() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }
}
