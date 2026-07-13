import 'package:meta/meta.dart';

import 'request.dart';
import 'response.dart';

/// Fired synchronously right before a request is dispatched.
typedef RequestHook = void Function(Request request);

/// Fired synchronously after a response is received (and interceptors run).
typedef ResponseHook = void Function(Response response);

/// Lightweight, multicast request/response callbacks — simpler than the
/// interceptor chain for logging/tracing, and hot-swappable at runtime.
///
/// Hooks fire once per client attempt (retry). Internal redirect hops inside
/// the transport are not separately hooked.
@immutable
class EventHooks {
  const EventHooks({this.request = const [], this.response = const []});

  final List<RequestHook> request;
  final List<ResponseHook> response;

  EventHooks copyWith({
    List<RequestHook>? request,
    List<ResponseHook>? response,
  }) =>
      EventHooks(
        request: request ?? this.request,
        response: response ?? this.response,
      );
}
