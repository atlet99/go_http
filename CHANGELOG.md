# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.4] - 2026-07-14

### Added
- **`DelegatingTransport`** (`lib/src/transport/delegating_transport.dart`): abstract base class for composing transport chains — wraps an inner `Transport`, delegates `send`/`dispose`, mutable `inner` field for swapping at runtime.
- **`RateLimitTransport`** (`lib/src/transport/rate_limit_transport.dart`): `DelegatingTransport` that rate-limits requests via a `RateLimitPolicy` (global or per-host token-bucket).
- **Cross-origin redirect header stripping**: `_buildRedirectRequest` now strips `Authorization`, `Cookie`, and `Proxy-Authorization` headers when redirecting to a different origin (RFC 7235 §7.1, RFC 6265 §8.5).
- **SSE parser** (`lib/src/sse/sse_parser.dart`, `lib/src/sse/sse_event.dart`): `SSEParser` `StreamTransformer<String, SSEEvent>` — parses Server-Sent Events per the HTML Living Standard §9.2. Handles chunked input, CRLF/CR/LF line endings, multi-line `data:`, comments, `event:`, `id:`, `retry:` fields, flush on stream close.
- **HTTP trailer headers** (`lib/src/chunked_decoder.dart`): `ChunkedDecoder` `StreamTransformer<List<int>, ChunkedEvent>` — decodes HTTP/1.1 chunked transfer encoding and extracts trailer headers (RFC 7230 §4.1). Emits `ChunkedPart` (body chunks) + `ChunkedComplete` (trailers). `Response.trailers` field for explicit trailer access.
- **`parseJsonInIsolate`** (`lib/src/json_helpers.dart`): decodes JSON in a background isolate via `Isolate.run()` to avoid blocking the event loop on large payloads (10 MB+).
- **`NdjsonParser`** (`lib/src/json_helpers.dart`): `StreamTransformer<String, dynamic>` — parses NDJSON (newline-delimited JSON) streams. Skips blank lines and `//` comments.

### Tests
- Added `DelegatingTransport` + `RateLimitTransport` tests (7 tests): delegation, dispose cascade, inner swap, rate-limit blocking, per-host isolation.
- Added cross-origin redirect tests (3 tests): strips Authorization on cross-origin, keeps on same-origin, strips Cookie.
- Added SSE parser tests (18 tests): simple data, event type, id, retry, multi-line data, leading space stripping, comments, multiple events, CRLF/CR endings, chunked input, empty input, flush-on-close, no-data events, unknown fields, retry edge cases.
- Added HTTP chunked decoder tests (12 tests): single/multiple chunks, trailers, chunk extensions, empty body, chunked input in pieces, trailer-only response, large hex sizes, Response trailers field.
- Added JSON helpers tests (11 tests): parseJsonInIsolate (map, list, nested, null, invalid), NdjsonParser (multiple lines, blank lines, comments, primitives, chunked input, empty input).

## [0.2.3] - 2026-07-13

### Added
- **Rich Response API**: `response.numBytesDownloaded` — body byte count after decompression; `response.nextRequest` — computed redirect request (when `followRedirects: false`); `response.links` — parsed `Link:` header as a `Map<String, Map<String, String?>>` keyed by `rel`; `response.bytes` — body as `Stream<List<int>>`; `response.httpVersion` — protocol version string; `response.reasonPhrase` — alias for `statusMessage`; `response.defaultEncoding` — function override for charset detection (e.g. chardet integration).
- **Limits pool config**: `Limits` class with `maxConnections` (100), `maxKeepaliveConnections` (20), `keepaliveExpiry` (5s), `copyWith`, `toString`. Wired into `ClientConfig.limits` and `IoTransport` (`maxConnectionsPerHost`, `idleTimeout`).
- **Cookies RFC 6265 jar**: `PersistentCookie` class with domain/path/secure/httponly/expires metadata. Full `Set-Cookie` header parser supporting `Domain`, `Path`, `Secure`, `HttpOnly`, `Max-Age`, `Expires`. RFC 6265 §5.1.3 domain-matching, §5.1.4 path-matching, §5.2.6 Secure-only enforcement, expiry with auto-removal.
- **StatusCode enum expansion**: Added `resetContent` (205), `multipleChoices` (300).
- **Obfuscated `toString`**: `Request.toString()` — one-line with method + URI, body truncated to 100 chars or shown as `N bytes` / `<stream>` (no sensitive data leak). `Response.toString()` — one-line `"200 OK GET /path"` using `StatusCode.phrase`, no headers or body.
- **Incremental text/line decoder**: `textStreamDecoder()` transforms `Stream<List<int>>` → `Stream<String>` with correct chunk-boundary handling for multi-byte encodings. `lineStreamDecoder()` splits a string stream by newlines. Both are `StreamTransformer`-based.
- **Streaming request bodies**: `Stream<List<int>>` accepted as `Request.body` and piped via `HttpClientRequest.addStream()`. Transports that don't support streaming will throw an appropriate error.
- **Top-level convenience API** (`lib/src/api.dart`): `get()`, `post()`, `put()`, `delete()`, `patch()`, `head()`, `options()` — standalone functions backed by a cached default `GoHttpClient`. Import `go_http` and call `get('https://...')` directly without creating a client.
- **Upload progress** (`onSendProgress`): `ProgressCallback` on every request method. `IoTransport` counts bytes as they are written — streaming bodies are wrapped with a counting transform (`Stream.map`), non-streaming bodies report 100% at once. Wired through `Transport.send()`, `MockTransport`, and `FakeTransport`.
- **`Retry-After` header respect**: `GoHttpClient._sendWithRetry` overrides exponential backoff on `429 Too Many Requests` / `503 Service Unavailable` when the server sends a `Retry-After` header (seconds or HTTP-date). Capped at 60s to prevent runaway waits.
- **`Request.extensions`**: `Map<String, Object?>` on `Request` for transport-specific metadata without interface changes. Preserved through `copyWith`.
- **`peekLength` helper** (`lib/src/body_encoding.dart`): returns byte length for common body types without materialising the entire body — `null`→0, `String`→UTF-8 bytes, `List<int>`→list length, `Stream`→`null`.
- **`poolTimeout` in `Limits`**: new field (default 10s) for the maximum time to wait for a connection from the pool. Wired into `copyWith`, `toString`, and `fromJson`.
- **Per-host certificate pinning** (`lib/src/pinning.dart`): `PinnedCertificates` config class — `Map<String, List<String>>` mapping hostnames to base64-encoded SHA-256 fingerprints. Wired into `ClientConfig` and `IoTransport._buildClient` via `badCertificateCallback`.
- **`HappyEyeballDialer`** (`lib/src/dialer.dart`): RFC 8305 dual-stack TCP dialer — resolves both IPv6 and IPv4 addresses, starts IPv6 immediately with a 300ms head start before racing IPv4, first successful connection wins and losers are destroyed.
- **HSTS cache** (`lib/src/hsts_cache.dart`): `HstsPolicy`, `HstsCache`, `MemoryHstsCache` — RFC 6797 Strict-Transport-Security. Parses `max-age`/`includeSubDomains`/`preload` from response headers, stores per-host policies with expiry, walks subdomain chains for `includeSubDomains` matches.
- **Makefile targets**: `fix` (dart fix —dry-run), `fix-all` (apply fixes + format), `test` (dart test), `check-all` (format → analyze → test).

### Changed
- **WASM-ready**: `web_transport.dart` migrated from `dart:html` to `package:web` + `dart:js_interop`. Unblocks compilation to WASM for Flutter Web. `Request` and `Headers` naming conflicts resolved via `hide` in the import.
- `MemoryCookieStore` rewritten: RFC 6265 Set-Cookie parsing, per-cookie metadata, domain/path/secure filtering, cookie expiry, automatic dedup on re-set, default-path inference. `getCookies()` returns all matching cookies sorted by path specificity.
- `README.md` — added Happy Eyeballs section (RFC 8305), HSTS section (RFC 6797), new `example/happy_eyeball.dart`.

### Tests
- Added comprehensive test suite: Limits (8 tests), RFC 6265 cookies (16 tests), Request/Response toString (7 tests), text/line stream decoders (5 tests), streaming request body, expanded StatusCode enum.
- Added tests for `peekLength` (5 tests), `Request.extensions` (2 tests), certificate pinning (`PinnedCertificates` equality/hash), `Retry-After` parsing, `nextRequest`/`elapsed`/`numBytesDownloaded` on Response, and `Limits.poolTimeout`.
- Added `HappyEyeballDialer` integration tests (3 tests): IPv4 fallback via localhost, DNS resolution failure, connection refused.
- Added HSTS cache tests (16 tests): policy expiry/equality, `setHsts`/`lookup` (exact, subdomain, preload, max-age=0, HTTP ignore, expired, unknown), `clearExpired`/`clear`, header parsing edge cases, client integration (buildRequest upgrade).

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
- `Dialer` abstract class + `SocketDialer` — pluggable socket-level dialer interface (integration with `IoTransport` pending transport rewrite).
- IP-override: `RequestOptions.dialAddress` — connect to a specific IP:port while keeping the original hostname in the `Host` header.
- Dialed-IP exposure: `Response.remoteAddress` and `ResponseEnrichment.remoteAddress` — IP address of the remote server that handled the request.
- `TlsInfo` enrichment: `subject`, `issuer`, `fingerprintSha1`, `validFrom`, `validTo` fields; populated by `IoTransport` from `HttpClientResponse.certificate`.
- `GoHttpClient.validate()` — returns `List<ValidationError>` with config issues (timeout <= 0, redirects < 0, etc.). Non-throwing, suitable for UI/config check.
- `AggregateError` — multierr equivalent collecting multiple errors into one (for close-multiple-resources patterns).
- `ValidationError` class — field + message pair for config validation results.
- Two-level config: `ClientConfig` (transport/timeout/TLS/proxy/cookies) + `ExecutorConfig` (interceptors/metrics/hooks/enrichers), both `validate()`, both optional and backward-compatible in `GoHttpClient` constructor.
- `ProgressReporter` — per-batch progress with RPS, percentage, elapsed, and ETA (`ProgressReporter.summary`).
- `ResponseEnricher` SPI — `abstract class ResponseEnricher` registered via `ExecutorConfig.enrichers`, called per response in enrichment pipeline. Extra data lands in `ResponseEnrichment.extra`.
- `ResponseFilter` interface + `StatusCodeFilter`, `RegexFilter`, `Match` (OR/AND short-circuit) — ready for inclusion/exclusion in batch pipelines.
- `BearerAuth` — stateless `BearerAuth('token')` strategy for `AuthInterceptor`. Legacy `tokenProvider`/`tokenRefresher` marked `@Deprecated`.
- `stderrLog` — log helper writing to `dart:io` stderr (fallback to `print` on Web). `LoggingInterceptor` now defaults to `stderrLog`, keeping stdout clean for JSONL/result output.
- `ClientConfig.fromJson()` + `mergeEnv()` — load config from JSON map, override from `GO_HTTP_*` env vars.
- `PortSpec.parse('http:8080,https:443')` — nmap-style scheme→port mapping.
- `Headers.parse('Content-Type: application/json')` factory — one or more `Key: Value` lines.
- `ClientConfig.copyWith()` — produce a modified copy preserving other fields.
- Two-phase file writing — `ResultSink.jsonl()`/`.csv()` write to a temp file (`O_EXCL` + incrementing suffix) and atomically rename on `close()`, preventing parallel-writer corruption.
- `ClientConfig.minTlsVersion` / `maxTlsVersion` — reserved config surface for TLS version constraints (forward-compat, SDK pending).
- `ResultCallback` typedef + `List<ResultCallback>? onResults` param on `BatchExecutor.run()` — chain multiple callbacks alongside legacy `onResult`.

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

