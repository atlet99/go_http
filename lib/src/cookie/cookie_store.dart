import '../response.dart';

/// Abstract interface for cookie storage
abstract class CookieStore {
  /// Get cookies for a given URI
  List<String> getCookies(Uri uri);

  /// Set cookies from a response
  void setCookies(Response response);

  /// Clear all cookies
  void clear();

  /// Clear cookies for a specific domain
  void clearDomain(String domain);
}
