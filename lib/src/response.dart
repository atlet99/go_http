import 'dart:convert';
import 'dart:typed_data';

import 'enrichment.dart';
import 'errors.dart';
import 'headers.dart';
import 'request.dart';

/// HTTP response representation.
class Response<T> {
  Response({
    required this.request,
    required this.statusCode,
    Object? headers,
    this.data,
    this.statusMessage,
    this.elapsed = Duration.zero,
    this.numBytesDownloaded = 0,
    this.nextRequest,
    this.remoteAddress,
    this.tlsInfo,
    this.enrichment,
    List<Response>? history,
  })  : headers = headers is Headers ? headers : Headers(headers),
        history = history ?? const [];

  final Request request;
  final int statusCode;
  final Headers headers;
  final T? data;
  final String? statusMessage;

  /// Time spent on the full request/response cycle (set by the client).
  final Duration elapsed;

  /// Number of body bytes downloaded (after decompression but before
  /// application-level decoding). Zero until the response body is read.
  final int numBytesDownloaded;

  /// The next request to follow if the client were to follow redirects.
  /// Populated when the response is a redirect (301/302/303/307/308) and the
  /// client has `followRedirects: false` — `null` otherwise.
  final Request? nextRequest;

  /// Redirect chain (intermediate responses), earliest first.
  final List<Response> history;

  /// The IP address of the remote server that handled this response.
  /// Populated by the transport; `null` when unavailable.
  final String? remoteAddress;

  /// TLS handshake details, populated by the transport when available.
  final TlsInfo? tlsInfo;

  /// Optional enrichment (timing breakdown, TLS info, etc.).
  /// Populated when the transport collects it; `null` otherwise.
  final ResponseEnrichment? enrichment;

  /// 1xx — informational.
  bool get isInformational => statusCode >= 100 && statusCode < 200;

  /// 2xx — success.
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// 3xx — redirection.
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// 4xx — client error.
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// 5xx — server error.
  bool get isServerError => statusCode >= 500 && statusCode < 600;

  /// 4xx or 5xx.
  bool get isError => statusCode >= 400 && statusCode < 600;

  /// A real redirect: status in {301,302,303,307,308} AND a `Location` header
  /// is present. (304/300 are 3xx but not navigable redirects.)
  bool get hasRedirectLocation {
    return (statusCode == 301 ||
            statusCode == 302 ||
            statusCode == 303 ||
            statusCode == 307 ||
            statusCode == 308) &&
        _header('location') != null;
  }

  /// Alias for [statusMessage] (RFC 9110 "reason phrase").
  String? get reasonPhrase => statusMessage;

  /// HTTP version string if known (e.g. `"HTTP/1.1"`), otherwise null.
  String? get httpVersion => _header('http-version');

  /// The charset declared by the `Content-Type` response header, or `null`.
  String? get charsetEncoding => _parseCharset(_header('content-type'));

  /// The effective charset used to decode [text]. Priority:
  /// caller-set [encoding] → [charsetEncoding] → [defaultEncoding] → `utf-8`.
  String get encoding => _encoding ?? charsetEncoding ?? _resolveDefaultEncoding() ?? 'utf-8';
  String? _encoding;

  /// Override the charset used by [text].
  set encoding(String value) {
    _encoding = value;
  }

  /// A function that auto-detects encoding from raw body bytes.
  /// Set this to enable chardet or similar detection libraries.
  /// Return `null` to fall through to the next priority (charset from
  /// Content-Type, then `utf-8`).
  String? Function(Uint8List bytes)? defaultEncoding;

  String? _resolveDefaultEncoding() {
    final fn = defaultEncoding;
    final bytes = _bytes;
    if (fn != null && bytes != null) {
      final result = fn(bytes);
      if (result != null && result.isNotEmpty) {
        return result;
      }
    }
    return null;
  }

  /// Decoded body as text, using [encoding].
  String get text {
    final bytes = _bytes;
    if (bytes == null) {
      return '';
    }
    return _decodeWith(bytes, encoding);
  }

  /// Decode the body as JSON, using [text].
  Object? json() {
    final body = text;
    if (body.isEmpty) {
      return null;
    }
    return jsonDecode(body);
  }

  /// Throw [HttpStatusError] if the status is an error (4xx/5xx), otherwise
  /// return `this` for chaining.
  Response<T> raiseForStatus() {
    if (isError) {
      throw HttpStatusError(request: request, response: this);
    }
    return this;
  }

  /// The raw body bytes as a single‑chunk stream. Useful for APIs that consume
  /// a `Stream<List<int>>` regardless of whether the body was loaded eagerly.
  Stream<List<int>> get bytes async* {
    final b = _bytes;
    if (b != null) {
      yield b;
    }
  }

  /// Items from the `Link` response header, keyed by `rel` (or `"_"` for
  /// unnamed links). Empty map when no `Link` header is present.
  ///
  /// Each value is itself a map with entries `"url"`, `"rel"`, and any
  /// `"param"` extensions per RFC 5988 §5.
  ///
  /// ```dart
  /// res.links['next']?['url']  // "https://api.example.com/items?page=2"
  /// ```
  Map<String, Map<String, String>> get links {
    final result = <String, Map<String, String>>{};
    final linkHeaders = _header('link');
    if (linkHeaders == null || linkHeaders.isEmpty) {
      return result;
    }
    for (final raw in linkHeaders.split(',')) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final linkMatch = RegExp(r'<([^>]+)>(.*)').firstMatch(trimmed);
      if (linkMatch == null) {
        continue;
      }
      final url = linkMatch.group(1)!;
      final params = linkMatch.group(2) ?? '';
      final attrs = <String, String>{'url': url};
      for (final param in params.split(';')) {
        final p = param.trim();
        if (p.isEmpty) {
          continue;
        }
        final eq = p.indexOf('=');
        if (eq > 0) {
          final key = p.substring(0, eq).trim().toLowerCase();
          var val = p.substring(eq + 1).trim();
          if ((val.startsWith('"') && val.endsWith('"')) ||
              (val.startsWith("'") && val.endsWith("'"))) {
            val = val.substring(1, val.length - 1);
          }
          attrs[key] = val;
        }
      }
      final rel = attrs['rel'] ?? '_';
      result[rel] = attrs;
    }
    return result;
  }

  // --- internals ---

  Uint8List? get _bytes {
    final d = data;
    if (d is Uint8List) {
      return d;
    }
    if (d is List<int>) {
      return Uint8List.fromList(d);
    }
    if (d is String) {
      return Uint8List.fromList(utf8.encode(d));
    }
    return null;
  }

  String? _header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return null;
  }

  static String _decodeWith(Uint8List bytes, String charset) {
    final name = charset.toLowerCase();
    if (name == 'utf-8' || name == 'utf8' || name.isEmpty) {
      final offset = _bomLength(bytes);
      final slice = offset > 0 ? bytes.sublist(offset) : bytes;
      return utf8.decode(slice, allowMalformed: true);
    }
    if (name == 'windows-1251' || name == 'cp1251') {
      return _decodeSbcs(bytes, _cp1251);
    }
    if (name == 'koi8-r') {
      return _decodeSbcs(bytes, _koi8r);
    }
    if (name == 'iso-8859-5') {
      return _decodeSbcs(bytes, _iso88595);
    }
    // ponytail: latin1 fallback covers all 256 byte values; add more
    // single-byte charsets when needed.
    return latin1.decode(bytes);
  }

  /// Decode bytes using a single-byte charset lookup (bytes 128-255).
  static String _decodeSbcs(Uint8List bytes, List<int> table) {
    final chars = List<int>.generate(bytes.length, (i) {
      final b = bytes[i];
      return b < 128 ? b : table[b - 128];
    });
    return String.fromCharCodes(chars);
  }

  /// cp1251 → Unicode code points for bytes 0x80-0xFF.
  static const _cp1251 = [
    0x0402,
    0x0403,
    0x201A,
    0x0453,
    0x201E,
    0x2026,
    0x2020,
    0x2021,
    0x20AC,
    0x2030,
    0x0409,
    0x2039,
    0x040A,
    0x040C,
    0x040B,
    0x040F,
    0x0452,
    0x2018,
    0x2019,
    0x201C,
    0x201D,
    0x2022,
    0x2013,
    0x2014,
    0x0098,
    0x2122,
    0x0459,
    0x203A,
    0x045A,
    0x045C,
    0x045B,
    0x045F,
    0x00A0,
    0x040E,
    0x045E,
    0x0408,
    0x00A4,
    0x0490,
    0x00A6,
    0x00A7,
    0x0401,
    0x00A9,
    0x0404,
    0x00AB,
    0x00AC,
    0x00AD,
    0x00AE,
    0x0407,
    0x00B0,
    0x00B1,
    0x0406,
    0x0456,
    0x0491,
    0x00B5,
    0x00B6,
    0x00B7,
    0x0451,
    0x2116,
    0x0454,
    0x00BB,
    0x0458,
    0x0405,
    0x0455,
    0x0457,
    0x0410,
    0x0411,
    0x0412,
    0x0413,
    0x0414,
    0x0415,
    0x0416,
    0x0417,
    0x0418,
    0x0419,
    0x041A,
    0x041B,
    0x041C,
    0x041D,
    0x041E,
    0x041F,
    0x0420,
    0x0421,
    0x0422,
    0x0423,
    0x0424,
    0x0425,
    0x0426,
    0x0427,
    0x0428,
    0x0429,
    0x042A,
    0x042B,
    0x042C,
    0x042D,
    0x042E,
    0x042F,
    0x0430,
    0x0431,
    0x0432,
    0x0433,
    0x0434,
    0x0435,
    0x0436,
    0x0437,
    0x0438,
    0x0439,
    0x043A,
    0x043B,
    0x043C,
    0x043D,
    0x043E,
    0x043F,
    0x0440,
    0x0441,
    0x0442,
    0x0443,
    0x0444,
    0x0445,
    0x0446,
    0x0447,
    0x0448,
    0x0449,
    0x044A,
    0x044B,
    0x044C,
    0x044D,
    0x044E,
    0x044F,
  ];

  /// KOI8-R → Unicode code points for bytes 0x80-0xFF.
  static const _koi8r = [
    0x2500,
    0x2502,
    0x250C,
    0x2510,
    0x2514,
    0x2518,
    0x251C,
    0x2524,
    0x252C,
    0x2534,
    0x253C,
    0x2580,
    0x2584,
    0x2588,
    0x258C,
    0x2590,
    0x2591,
    0x2592,
    0x2593,
    0x2320,
    0x25A0,
    0x2219,
    0x221A,
    0x2248,
    0x2264,
    0x2265,
    0x00A0,
    0x2321,
    0x00B0,
    0x00B2,
    0x00B7,
    0x00F7,
    0x2550,
    0x2551,
    0x2552,
    0x0451,
    0x2553,
    0x2554,
    0x2555,
    0x2556,
    0x2557,
    0x2558,
    0x2559,
    0x255A,
    0x255B,
    0x255C,
    0x255D,
    0x255E,
    0x255F,
    0x2560,
    0x2561,
    0x0401,
    0x2562,
    0x2563,
    0x2564,
    0x2565,
    0x2566,
    0x2567,
    0x2568,
    0x2569,
    0x256A,
    0x256B,
    0x256C,
    0x00A9,
    0x044E,
    0x0430,
    0x0431,
    0x0446,
    0x0434,
    0x0435,
    0x0444,
    0x0433,
    0x0445,
    0x0438,
    0x0439,
    0x043A,
    0x043B,
    0x043C,
    0x043D,
    0x043E,
    0x043F,
    0x044F,
    0x0440,
    0x0441,
    0x0442,
    0x0443,
    0x0436,
    0x0432,
    0x044C,
    0x044B,
    0x0437,
    0x0448,
    0x044D,
    0x0449,
    0x0447,
    0x044A,
    0x042E,
    0x0410,
    0x0411,
    0x0426,
    0x0414,
    0x0415,
    0x0424,
    0x0413,
    0x0425,
    0x0418,
    0x0419,
    0x041A,
    0x041B,
    0x041C,
    0x041D,
    0x041E,
    0x041F,
    0x042F,
    0x0420,
    0x0421,
    0x0422,
    0x0423,
    0x0416,
    0x0412,
    0x042C,
    0x042B,
    0x0417,
    0x0428,
    0x042D,
    0x0429,
    0x0427,
    0x042A,
  ];

  /// ISO-8859-5 → Unicode code points for bytes 0x80-0xFF.
  static const _iso88595 = [
    0x0080,
    0x0081,
    0x0082,
    0x0083,
    0x0084,
    0x0085,
    0x0086,
    0x0087,
    0x0088,
    0x0089,
    0x008A,
    0x008B,
    0x008C,
    0x008D,
    0x008E,
    0x008F,
    0x0090,
    0x0091,
    0x0092,
    0x0093,
    0x0094,
    0x0095,
    0x0096,
    0x0097,
    0x0098,
    0x0099,
    0x009A,
    0x009B,
    0x009C,
    0x009D,
    0x009E,
    0x009F,
    0x00A0,
    0x0401,
    0x0402,
    0x0403,
    0x0404,
    0x0405,
    0x0406,
    0x0407,
    0x0408,
    0x0409,
    0x040A,
    0x040B,
    0x040C,
    0x00AD,
    0x040E,
    0x040F,
    0x0410,
    0x0411,
    0x0412,
    0x0413,
    0x0414,
    0x0415,
    0x0416,
    0x0417,
    0x0418,
    0x0419,
    0x041A,
    0x041B,
    0x041C,
    0x041D,
    0x041E,
    0x041F,
    0x0420,
    0x0421,
    0x0422,
    0x0423,
    0x0424,
    0x0425,
    0x0426,
    0x0427,
    0x0428,
    0x0429,
    0x042A,
    0x042B,
    0x042C,
    0x042D,
    0x042E,
    0x042F,
    0x0430,
    0x0431,
    0x0432,
    0x0433,
    0x0434,
    0x0435,
    0x0436,
    0x0437,
    0x0438,
    0x0439,
    0x043A,
    0x043B,
    0x043C,
    0x043D,
    0x043E,
    0x043F,
    0x0440,
    0x0441,
    0x0442,
    0x0443,
    0x0444,
    0x0445,
    0x0446,
    0x0447,
    0x0448,
    0x0449,
    0x044A,
    0x044B,
    0x044C,
    0x044D,
    0x044E,
    0x044F,
    0x2116,
    0x0451,
    0x0452,
    0x0453,
    0x0454,
    0x0455,
    0x0456,
    0x0457,
    0x0458,
    0x0459,
    0x045A,
    0x045B,
    0x045C,
    0x00A7,
    0x045E,
    0x045F,
  ];

  /// Returns the byte-length of a leading BOM, or 0.
  // ponytail: only UTF-8 BOM (3 bytes). UTF-16/32 BOM stripping is a
  // follow-up when the charset decoder supports those encodings.
  static int _bomLength(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return 3;
    }
    return 0;
  }

  static String? _parseCharset(String? contentType) {
    if (contentType == null) {
      return null;
    }
    for (final part in contentType.split(';')) {
      final trimmed = part.trim().toLowerCase();
      if (trimmed.startsWith('charset=')) {
        return trimmed.substring(8).replaceAll('"', '');
      }
    }
    return null;
  }

  Response<R> copyWith<R>({
    Request? request,
    int? statusCode,
    Object? headers,
    R? data,
    String? statusMessage,
    Duration? elapsed,
    int? numBytesDownloaded,
    Request? nextRequest,
    String? remoteAddress,
    TlsInfo? tlsInfo,
    ResponseEnrichment? enrichment,
    List<Response>? history,
  }) {
    return Response<R>(
      request: request ?? this.request,
      statusCode: statusCode ?? this.statusCode,
      headers: headers ?? this.headers,
      data: data ?? (this.data as R?),
      statusMessage: statusMessage ?? this.statusMessage,
      elapsed: elapsed ?? this.elapsed,
      numBytesDownloaded: numBytesDownloaded ?? this.numBytesDownloaded,
      nextRequest: nextRequest ?? this.nextRequest,
      remoteAddress: remoteAddress ?? this.remoteAddress,
      tlsInfo: tlsInfo ?? this.tlsInfo,
      enrichment: enrichment ?? this.enrichment,
      history: history ?? this.history,
    );
  }
}
