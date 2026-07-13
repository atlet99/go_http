# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-07-13

### Added
- Per-request delay: `RequestOptions.delay` pauses before sending the request (rate-limiting / polite crawling).
- Body byte limits: `RequestOptions.maxBytesToRead` / `maxBytesToSave` throw `MaxBytesReadError` when the decoded response body exceeds the configured threshold.
- Drain-and-close for keep-alive: `IoTransport` drains remaining response bytes before throwing read errors, returning the connection to the pool.
- `RateLimiter` — token-bucket rate limiter with `.take()` → `Future<void>` (configurable tokens/sec and burst).
- `ResizeableSemaphore` — adaptive semaphore with runtime `resize()`, FIFO fair ordering, non-negative `available`.
- `HostCircuitBreaker` — per-host circuit breaker (closed/open/half-open), configurable failure threshold and cooldown, `CircuitOpenError` for fail-fast.
- `RateLimitPolicy.global()` / `.perHost()` — policy wrapper over `RateLimiter` for shared or per-host rate limiting.
- `ResponseEnrichment`, `ResponseTiming`, `TlsInfo` — enrichment data model attached to `Response.enrichment`.
- `RequestTrace` — per-request phase timestamps (wroteRequest, gotFirstResponseByte, responseDone) populated by `IoTransport`.
- `RetryPolicy.scanning()` / `.single()` — retry presets for probing vs critical workloads.
- Idempotency extended: `PUT` and `DELETE` are now retried by default (matching `httpx`/`retryablehttp`).
- Gzip-fallback: `IoTransport` returns raw body instead of crashing when a server sends `Content-Encoding: gzip` on an uncompressed body.
- Auto-scheme fallback: `IoTransport.tryHttpOnHttpsError` (default `false`) retries a failed HTTPS connection once with HTTP.
- Graceful two-step shutdown: `GoHttpClient.shutdown()` (soft — stops new requests, waits for in-flight) and `dispose()` (hard — closes transport immediately). `ClientShutdownError` thrown on new requests after shutdown.

## [0.2.1] - 2026-07-13

### Added
- Public `Headers` collection: case-insensitive, multi-value (`Set-Cookie`, `Vary`, `Link`), `getAll`/`multiItems`, sensitive-header masking in `toString`.
- `UseClientDefault` sentinel for three-state `timeout`/`followRedirects` (`useClientDefault` → client default, `null` → disable, value → override).
- `buildRequest()` / `send()` / `request()` split — `buildRequest` is the merge boundary; `send` dispatches a prepared `Request` without re-merging (escape hatch: `client.send(client.buildRequest(req))`).
- `baseUrl` option on `GoHttpClient` (relative request URIs resolve against it).
- Structured exception hierarchy: `HttpError` → `RequestError` → `TransportError` (`TimeoutError`/`NetworkError`/`ProtocolError`/`ProxyError`/`UnsupportedProtocol`) → typed leaves (`ConnectTimeoutError`, `ReadTimeoutError`, `WriteTimeoutError`, `ConnectError`, …); `HttpStatusError` deliberately does **not** extend `RequestError` so `catch (RequestError)` never swallows a 4xx/5xx.
- Event hooks: `EventHooks` with multicast `request`/`response` callback lists, hot-swappable at runtime via `GoHttpClient.eventHooks`.
- `Url` (immutable wrapper over `Uri`: lowercased scheme/host, default-port collapsed to `null`, `copyWith`, RFC 3986 `join`, password-masked `toString`) and `QueryParams` (immutable multi-value query: `add`/`set`/`remove`/`merge` return new instances, `getList`, JSON-style bool). `RequestOptions.queryParameters` is now a `QueryParams`.
- `Multipart` encoder (zero-dependency `multipart/form-data`): `MultipartFile`/`MultipartField`, `render()`/`stream()`/`encodedLength`, random 16-byte boundary, content-type guessing from extension, HTML5 attribute escaping. `GoHttpClient` auto-serializes a `Multipart` request body and sets `Content-Type`.
- Proxy support: `Proxy` (`http`/`https`/`socks5`/`direct`, parse + masked `toString`), `URLPattern` (wildcard `*` host, `all://` scheme, `specificity`), `ProxyMounts` (most-specific route wins, `null` = explicit direct), and `buildSecurityContext` honoring explicit `verify` / `SSL_CERT_FILE` env. `GoHttpClient` takes `proxyMounts`, `trustEnv`, `verify`; native transport wires `findProxy`, `badCertificateCallback`, and a per-client `SecurityContext`.
- `Result<T>` (never-throw batch outcome: `Result.ok`/`Result.fail`) and pluggable `ResultSink` SPI with `jsonl`/`csv` factories; CSV output sanitizes formula-injection cells (`=`,`+`,`-`,`@`).
- Auth SPI: `Auth` strategy (`BasicAuth`, `FunctionAuth`) applied on the request path, plus `DigestAuth` (RFC 2617/7616, MD5/SHA-256, qop, cnonce, nonce-count) driven by the interceptor's 401 `WWW-Authenticate` challenge via the existing retry path. `AuthInterceptor` now takes an `auth` strategy and still supports the legacy Bearer `tokenProvider`/`tokenRefresher` flow.
- Body encoding: `encodeRequest` dispatch ladder — `json` → `application/json`, `Map` → `application/x-www-form-urlencoded`, raw `String`/bytes/`Multipart` pass through. `post`/`put`/`patch`/`delete` route their `data`/`json` through it.
- Content decoder registry: `ContentDecoder` SPI + `contentDecoders` map (gzip/deflate always, brotli/zstd optional via `registerBrotli`/`registerZstd`), `decodeContentEncoding` for stacked encodings, deflate-ambiguity fix (zlib → raw fallback). `IoTransport` now always sets `autoUncompress=false` and decodes manually. Default `accept-encoding` narrowed to `gzip`.

### Changed
- Updated `README.md` — complete rewrite reflecting all current APIs (proxy, auth, decoders, batch, multipart, structured timeouts, headers, mock transport, error hierarchy, etc.)
- Deleted `example/main.dart` (duplicate of `simple_get.dart`); added `example/post_json.dart` demonstrating `json:` parameter
- Updated `example/download_progress.dart` to use `onProgress` callback
- Updated `Makefile`: replaced `example-main` target with `example-post-json`

## [0.2.0] - 2026-07-12

### Fixed
- **Timeouts now actually work**: `connectTimeout`/`sendTimeout`/`receiveTimeout` are enforced per phase on native (`dart:io`) and as an overall request timeout on web. Exceeding a timeout throws `TimeoutError` (previously these options were silently ignored).
- **Web binary responses**: `WebTransport` now reads `responseType = 'arraybuffer'`, so binary data (images, gzipped bodies, files) is no longer corrupted.
- **Multi-value `Set-Cookie`**: cookies with `Expires`/multiple headers are parsed correctly (no longer split on the comma inside `Expires`). The `Domain` attribute is honored for subdomain matching.
- **Error interceptors** now run exactly once per attempt (previously twice for HTTP errors).
- **Auth refresh retry**: `AuthInterceptor` now retries the request once after refreshing the token on `401` (previously refreshed but never retried).
- **Dead redirect code** removed; `followRedirects`/`maxRedirects` are now wired into the IO transport.
- Header keys normalized to lowercase in both transports for case-insensitive lookups.
- `IoTransport` no longer mutates a caller-supplied `HttpClient`.

### Added
- `RetrySignal` control-flow type returned by interceptors to request a bounded retry.
- `Decoder<T>` support (`decoder:` parameter) on all request methods for real type-safe decoding.
- `ProgressCallback` (`onReceiveProgress:`) on all request methods, with byte progress on native and web.
- Convenience methods: `put`, `delete`, `patch`, `head`, `options`.
- Injectable `Logger` sink for `LoggingInterceptor` and `ConsoleMetricsSink`.
- `maxAuthRetries` option on `GoHttpClient`.
- `queryParameters` from `RequestOptions` are now applied to the request URI.

### Changed
- Retry backoff switched to stateless **exponential backoff with equal jitter** (AWS-recommended; safe to share a single policy across concurrent requests). Previously claimed "decorrelated jitter" but implemented a different, stateful algorithm.
- `CancellationToken` event delivery is now synchronous (instant listener notification).

### Tests
- Added comprehensive test suite: retry policy, cookie store, cancellation, decoders, and client flow (retries, auth refresh, cancellation, error-interceptor cardinality, decoders, query params, convenience methods) via a fake transport.

## [0.1.1] - 2025-11-13

### Added
- Basic example (`example/main.dart`) for pub.dev package validation
- Makefile with development commands for code analysis, formatting, running examples, and version management

## [0.1.0] - 2025-01-13

### Added
- Basic HTTP client with GET and POST methods
- Request cancellation support via `CancellationToken`
- Retry policy with decorrelated jitter backoff algorithm
- Interceptors for request/response/error handling
- Built-in `LoggingInterceptor` and `AuthInterceptor`
- Cookie store with `MemoryCookieStore` implementation
- Metrics collection with `ConsoleMetricsSink`
- Cross-platform support (Dart CLI, Flutter, Web)
- IO transport for native platforms
- Web transport for browser platforms
- Redirect policy support
- Type-safe response handling with generics
- Comprehensive error types (`NetworkError`, `HttpResponseError`, `TimeoutError`, `CancellationError`)

### Security
- Retries only for idempotent HTTP methods (GET, HEAD, OPTIONS)
- Sensitive headers are masked in logs
- TLS verification enabled by default

