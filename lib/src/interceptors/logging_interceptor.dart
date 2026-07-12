import '../errors.dart';
import '../logger.dart';
import '../request.dart';
import '../response.dart';
import 'interceptor.dart';

/// Interceptor for logging HTTP requests and responses.
class LoggingInterceptor extends Interceptor {
  LoggingInterceptor({
    this.logRequest = true,
    this.logResponse = true,
    this.logError = true,
    this.logger = defaultLog,
    List<String>? sensitiveHeaders,
  }) : _sensitiveHeaders = sensitiveHeaders ?? _defaultSensitive;

  final bool logRequest;
  final bool logResponse;
  final bool logError;
  final Logger logger;
  final List<String> _sensitiveHeaders;

  static const List<String> _defaultSensitive = [
    'authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'x-auth-token',
  ];

  @override
  Future<Request> onRequest(Request request) async {
    if (logRequest) {
      _logRequest(request);
    }
    return request;
  }

  @override
  Future<Response> onResponse(Response response) async {
    if (logResponse) {
      _logResponse(response);
    }
    return response;
  }

  @override
  Future<Object> onError(HttpError error) async {
    if (logError) {
      _logError(error);
    }
    return Future.error(error);
  }

  void _logRequest(Request request) {
    final headers = _maskSensitiveHeaders(request.headers);
    logger('[go_http] -> ${request.methodString} ${request.uri}');
    if (headers.isNotEmpty) {
      logger('[go_http]    Headers: $headers');
    }
    if (request.body != null) {
      logger('[go_http]    Body: ${request.body}');
    }
  }

  void _logResponse(Response response) {
    logger('[go_http] <- ${response.statusCode} ${response.request.uri}');
    if (response.headers.isNotEmpty) {
      logger('[go_http]    Headers: ${_maskSensitiveHeaders(response.headers)}');
    }
  }

  void _logError(HttpError error) {
    logger('[go_http] X  Error: ${error.message}');
    if (error.originalError != null) {
      logger('[go_http]    Original: ${error.originalError}');
    }
  }

  Map<String, String> _maskSensitiveHeaders(Map<String, String> headers) {
    final masked = <String, String>{};
    headers.forEach((key, value) {
      if (_sensitiveHeaders.contains(key.toLowerCase())) {
        masked[key] = '***';
      } else {
        masked[key] = value;
      }
    });
    return masked;
  }
}
