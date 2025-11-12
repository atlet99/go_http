import '../request.dart';
import '../response.dart';

/// Policy for handling HTTP redirects
abstract class RedirectPolicy {
  /// Determine if a redirect should be followed
  bool shouldFollowRedirect(
    Request request,
    Response response,
    int redirectCount,
  );

  /// Get the maximum number of redirects to follow
  int get maxRedirects;
}

/// Default redirect policy
class DefaultRedirectPolicy implements RedirectPolicy {
  DefaultRedirectPolicy({this.maxRedirects = 5});

  @override
  final int maxRedirects;

  @override
  bool shouldFollowRedirect(
    Request request,
    Response response,
    int redirectCount,
  ) {
    if (redirectCount >= maxRedirects) {
      return false;
    }

    // Follow redirects for 3xx status codes
    return response.isRedirect;
  }
}
