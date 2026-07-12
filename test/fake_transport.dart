import 'dart:typed_data';

import 'package:go_http/go_http.dart';

/// A handler invoked by [FakeTransport] for each request.
typedef FakeHandler = Future<Response> Function(Request request);

/// In-memory [Transport] used to test [GoHttpClient] without real I/O.
///
/// Each call to [send] consumes the next handler in [_handlers]; if the client
/// retries more times than there are handlers, the last handler is reused.
class FakeTransport implements Transport {
  FakeTransport(List<FakeHandler> handlers) : _handlers = List.from(handlers);

  final List<FakeHandler> _handlers;
  final List<Request> sent = [];
  int _index = 0;

  @override
  Future<Response> send(
    Request request, {
    CancellationToken? cancel,
    Duration? connectTimeout,
    Duration? sendTimeout,
    Duration? receiveTimeout,
    bool? followRedirects,
    int? maxRedirects,
    bool? autoDecompress,
    ProgressCallback? onProgress,
  }) async {
    cancel?.throwIfCancelled();
    sent.add(request);
    final handler =
        _index < _handlers.length ? _handlers[_index] : _handlers.last;
    _index++;
    return handler(request);
  }

  @override
  void dispose() {}

  int get callCount => _index;
}

FakeHandler ok([
  int code = 200,
  Uint8List? data,
  Map<String, String>? headers,
]) =>
    (r) async => Response(
          request: r,
          statusCode: code,
          headers: headers ?? const {},
          data: data ?? Uint8List(0),
        );

FakeHandler status(int code) => ok(code);

FakeHandler networkError([String message = 'boom']) =>
    (r) async => throw NetworkError(request: r, message: message);

/// An interceptor that counts how many times each hook runs.
class CountingInterceptor extends Interceptor {
  int onRequestCount = 0;
  int onResponseCount = 0;
  int onErrorCount = 0;

  @override
  Future<Request> onRequest(Request request) async {
    onRequestCount++;
    return request;
  }

  @override
  Future<Response> onResponse(Response response) async {
    onResponseCount++;
    return response;
  }

  @override
  Future<Object> onError(HttpError error) async {
    onErrorCount++;
    return Future.error(error);
  }
}
