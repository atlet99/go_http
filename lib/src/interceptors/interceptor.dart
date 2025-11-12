import '../errors.dart';
import '../request.dart';
import '../response.dart';

/// Base class for HTTP interceptors
abstract class Interceptor {
  /// Intercept and modify the request before it is sent
  Future<Request> onRequest(Request request) async => request;

  /// Intercept and modify the response after it is received
  Future<Response> onResponse(Response response) async => response;

  /// Intercept and handle errors
  Future<Object> onError(HttpError error) async => Future.error(error);
}
