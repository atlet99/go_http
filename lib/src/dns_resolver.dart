import 'dart:io';

/// Pluggable DNS resolver.
///
/// Default: [SystemDnsResolver] wraps `InternetAddress.lookup`.
/// Cache: wrap with [CachedDnsResolver] for TTL-based caching.
///
/// ```dart
/// final resolver = CachedDnsResolver(maxCacheSize: 500, defaultTtlSeconds: 300);
/// final addr = await resolver.lookup('example.com');
/// ```
abstract class DnsResolver {
  /// Resolve [host] to an IP address.
  ///
  /// Throws [DnsLookupError] if the host cannot be resolved.
  Future<InternetAddress> lookup(String host);

  /// Clear any cached entries.
  void clearCache();
}

/// Error thrown when DNS lookup fails.
class DnsLookupError implements Exception {
  DnsLookupError(this.host, [this.message]);
  final String host;
  final String? message;
  @override
  String toString() =>
      'DnsLookupError: $host${message != null ? ' — $message' : ''}';
}

/// System DNS resolver using [InternetAddress.lookup].
class SystemDnsResolver implements DnsResolver {
  @override
  Future<InternetAddress> lookup(String host) async {
    try {
      final results = await InternetAddress.lookup(host);
      if (results.isEmpty) {
        throw DnsLookupError(host, 'No addresses found');
      }
      return results.first;
    } on SocketException catch (e) {
      throw DnsLookupError(host, e.message);
    }
  }

  @override
  void clearCache() {
    // System resolver has no cache to clear
  }
}

/// Cached DNS resolver wrapping an inner [DnsResolver].
///
/// Cache entries have a fixed [defaultTtlSeconds]; [negativeTtlSeconds]
/// controls how long failed lookups are remembered.
///
/// When the cache exceeds [maxCacheSize], expired entries are evicted first,
/// then the oldest 25% of remaining entries.
class CachedDnsResolver implements DnsResolver {
  CachedDnsResolver({
    DnsResolver? inner,
    this.maxCacheSize = 1000,
    this.defaultTtlSeconds = 300,
    this.negativeTtlSeconds = 60,
  }) : _inner = inner ?? SystemDnsResolver();

  final DnsResolver _inner;
  final int maxCacheSize;
  final int defaultTtlSeconds;
  final int negativeTtlSeconds;

  final _cache = <String, _CacheEntry>{};

  @override
  Future<InternetAddress> lookup(String host) async {
    final key = host.toLowerCase();
    final now = DateTime.now();

    final entry = _cache[key];
    if (entry != null && !entry.isExpired(now)) {
      if (entry.isNegative) {
        throw DnsLookupError(host, entry.errorMessage);
      }
      return entry.address!;
    }

    // Miss or expired — resolve
    try {
      final address = await _inner.lookup(host);
      _set(key, _CacheEntry(address, Duration(seconds: defaultTtlSeconds)));
      return address;
    } on Object catch (e) {
      final msg = e.toString();
      _set(key,
          _CacheEntry.negative(Duration(seconds: negativeTtlSeconds), msg,),);
      rethrow;
    }
  }

  void _set(String key, _CacheEntry entry) {
    if (_cache.length >= maxCacheSize) {
      _evict();
    }
    _cache[key] = entry;
  }

  void _evict() {
    final now = DateTime.now();
    // Remove expired entries
    _cache.removeWhere((_, e) => e.isExpired(now));

    // If still over limit, remove oldest 25%
    if (_cache.length >= maxCacheSize) {
      final toRemove = (_cache.length * 0.25).ceil();
      final sorted = _cache.entries.toList()
        ..sort((a, b) => a.value.storedAt.compareTo(b.value.storedAt));
      for (var i = 0; i < toRemove && i < sorted.length; i++) {
        _cache.remove(sorted[i].key);
      }
    }
  }

  @override
  void clearCache() {
    _cache.clear();
  }

  /// Number of entries currently in the cache.
  int get cacheSize => _cache.length;

  /// Number of expired entries that will be evicted on next lookup.
  int get expiredCount {
    final now = DateTime.now();
    return _cache.values.where((e) => e.isExpired(now)).length;
  }
}

class _CacheEntry {
  _CacheEntry(this.address, Duration ttl)
      : storedAt = DateTime.now(),
        expiresAt = DateTime.now().add(ttl),
        isNegative = false,
        errorMessage = null;

  _CacheEntry.negative(Duration ttl, this.errorMessage)
      : storedAt = DateTime.now(),
        expiresAt = DateTime.now().add(ttl),
        isNegative = true,
        address = null;

  final DateTime storedAt;
  final DateTime expiresAt;
  final InternetAddress? address;
  final bool isNegative;
  final String? errorMessage;

  bool isExpired(DateTime now) => now.isAfter(expiresAt);
}
