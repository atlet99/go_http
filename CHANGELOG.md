# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- `BatchExecutor` — bounded-concurrency batch runner that returns a `Result` per request (one failure never aborts the batch) with an optional progress callback.

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

