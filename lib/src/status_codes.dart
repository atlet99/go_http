/// Common HTTP status codes with their canonical reason phrases.
///
/// Carries both the integer value and the [phrase], plus category predicates.
/// For codes not listed here use [StatusCode.fromCode] which returns `null`;
/// callers can always fall back to the raw integer on [Response.statusCode].
enum StatusCode {
  // 2xx
  ok(200, 'OK'),
  created(201, 'Created'),
  accepted(202, 'Accepted'),
  noContent(204, 'No Content'),
  partialContent(206, 'Partial Content'),

  // 3xx
  movedPermanently(301, 'Moved Permanently'),
  found(302, 'Found'),
  seeOther(303, 'See Other'),
  notModified(304, 'Not Modified'),
  temporaryRedirect(307, 'Temporary Redirect'),
  permanentRedirect(308, 'Permanent Redirect'),

  // 4xx
  badRequest(400, 'Bad Request'),
  unauthorized(401, 'Unauthorized'),
  forbidden(403, 'Forbidden'),
  notFound(404, 'Not Found'),
  methodNotAllowed(405, 'Method Not Allowed'),
  requestTimeout(408, 'Request Timeout'),
  conflict(409, 'Conflict'),
  gone(410, 'Gone'),
  lengthRequired(411, 'Length Required'),
  payloadTooLarge(413, 'Payload Too Large'),
  unsupportedMediaType(415, 'Unsupported Media Type'),
  tooManyRequests(429, 'Too Many Requests'),

  // 5xx
  internalServerError(500, 'Internal Server Error'),
  notImplemented(501, 'Not Implemented'),
  badGateway(502, 'Bad Gateway'),
  serviceUnavailable(503, 'Service Unavailable'),
  gatewayTimeout(504, 'Gateway Timeout');

  const StatusCode(this.code, this.phrase);

  /// The integer status code.
  final int code;

  /// The canonical reason phrase (RFC 9110).
  final String phrase;

  /// 1xx — informational.
  bool get isInformational => code >= 100 && code < 200;

  /// 2xx — success.
  bool get isSuccess => code >= 200 && code < 300;

  /// 3xx — redirection.
  bool get isRedirect => code >= 300 && code < 400;

  /// 4xx — client error.
  bool get isClientError => code >= 400 && code < 500;

  /// 5xx — server error.
  bool get isServerError => code >= 500 && code < 600;

  /// 4xx or 5xx.
  bool get isError => code >= 400 && code < 600;

  /// Status codes that carry a redirect location: 301, 302, 303, 307, 308.
  bool get hasRedirectLocation =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;

  /// Look up the enum member for [code], or `null` if unknown.
  static StatusCode? fromCode(int code) {
    for (final value in StatusCode.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  /// Category helpers operating on a raw integer (for codes not in the enum).
  static bool isInformationalCode(int code) => code >= 100 && code < 200;
  static bool isSuccessCode(int code) => code >= 200 && code < 300;
  static bool isRedirectCode(int code) => code >= 300 && code < 400;
  static bool isClientErrorCode(int code) => code >= 400 && code < 500;
  static bool isServerErrorCode(int code) => code >= 500 && code < 600;
  static bool isErrorCode(int code) => code >= 400 && code < 600;
  static bool codeHasRedirectLocation(int code) =>
      code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
}
