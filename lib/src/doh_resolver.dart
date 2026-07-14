import 'dart:convert';
import 'dart:io';

import 'dns_resolver.dart';

/// DNS-over-HTTPS (DoH) resolver.
///
/// Sends DNS queries as JSON over HTTPS to a compliant DoH server
/// (Google DNS, Cloudflare, etc.). Follows the DNS JSON format
/// (`application/dns-json`) which is widely supported.
///
/// Composes with [CachedDnsResolver] for TTL-based caching:
///
/// ```dart
/// final doh = DohDnsResolver(server: 'https://dns.google/resolve');
/// final cached = CachedDnsResolver(inner: doh);
/// final addr = await cached.lookup('example.com');
/// ```
///
/// `ponytail:` ceiling — uses `HttpClient` (no dependency).  For very
/// high-throughput, consider `package:dns_client` with wire-format
/// (`application/dns-message`) for binary efficiency.
class DohDnsResolver implements DnsResolver {
  /// Creates a [DohDnsResolver].
  ///
  /// [server] is the DoH endpoint URL.  Defaults to Google DNS JSON API.
  /// Supported: `https://dns.google/resolve`, `https://cloudflare-dns.com/dns-query`,
  /// or any RFC 8484 / DNS JSON endpoint.
  DohDnsResolver({
    this.server = 'https://dns.google/resolve',
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  final String server;
  final HttpClient _client;

  @override
  Future<InternetAddress> lookup(String host) async {
    final uri = Uri.parse('$server?name=$host&type=A');

    final request = await _client.getUrl(uri);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw DnsLookupError(
        host,
        'DoH request failed: HTTP ${response.statusCode}',
      );
    }

    final json = jsonDecode(body) as Map<String, dynamic>;

    // Status 0 = NOERROR per RFC 1035.
    final status = json['Status'] as int? ?? -1;
    if (status != 0) {
      throw DnsLookupError(
        host,
        'DNS query failed with status $status',
      );
    }

    final answers = json['Answer'] as List<dynamic>?;
    if (answers == null || answers.isEmpty) {
      throw DnsLookupError(host, 'No DNS answers');
    }

    // Find the first A record (type 1) in answers.
    for (final answer in answers) {
      final record = answer as Map<String, dynamic>;
      final type = record['type'] as int?;
      final data = record['data'] as String?;

      if (type == 1 && data != null) {
        return InternetAddress(data, type: InternetAddressType.IPv4);
      }
    }

    // No A record — try AAAA (type 28).
    for (final answer in answers) {
      final record = answer as Map<String, dynamic>;
      final type = record['type'] as int?;
      final data = record['data'] as String?;

      if (type == 28 && data != null) {
        return InternetAddress(data, type: InternetAddressType.IPv6);
      }
    }

    throw DnsLookupError(host, 'No A/AAAA records in DoH response');
  }

  @override
  void clearCache() {
    // No local cache — cache layer is [CachedDnsResolver].
  }
}
