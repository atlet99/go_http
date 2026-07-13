# go_http

**Reliable HTTP client for Dart — built for control, cancellation and consistency.**

[![pub package](https://img.shields.io/pub/v/go_http.svg)](https://pub.dev/packages/go_http)
[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)

`go_http` is a modern, cross-platform HTTP client for Dart inspired by Python
[httpx](https://github.com/encode/httpx). It provides fine-grained control over
requests, structured timeouts, per-phase cancellation, pluggable auth and
transport, batch execution, and a powerful interceptor system.

## Features

- **Cross-platform** — works identically on Dart CLI, Flutter Mobile/Desktop, and Web
- **Cancellation** — every request can be cancelled mid-flight with `CancellationToken`
- **Retry Policy** — smart retry with equal-jitter exponential backoff, `Retry-After` header respect
- **Structured timeouts** — per-phase (`connect`, `read`, `write`, `pool`) via `Timeout`
- **Upload progress** — `onSendProgress` callback tracks bytes written (streaming and non-streaming bodies)
- **Interceptors** — request/response/error chain (`LoggingInterceptor`, `AuthInterceptor`)
- **Auth SPI** — `BasicAuth`, `DigestAuth` (RFC 2617/7616, MD5/SHA-256, qop, cnonce), `FunctionAuth`
- **Bearer token refresh** — auto-refresh on 401 and single retry
- **Cookie Store** — RFC-matching jar with `MemoryCookieStore` (domain/path, multi-value `Set-Cookie`)
- **Headers** — case-insensitive multi-value collection, sensitive-value masking in `toString`
- **Content-Encoding** — gzip + deflate (with raw fallback), brotli/zstd via `registerBrotli`/`registerZstd`
- **Body encoding** — `json` → `application/json`, `Map` → `application/x-www-form-urlencoded`, `peekLength` helper
- **Multipart** — `multipart/form-data` encoder (zero dependencies, streaming)
- **Proxy** — per-URL-pattern mounts (`ProxyMounts`, `URLPattern`), `NO_PROXY` support, `SOCKS5`
- **Certificate pinning** — per-host SHA-256 fingerprint validation (`PinnedCertificates`)
- **Top-level API** — `get()`, `post()`, `put()`, `delete()`, `patch()`, `head()`, `options()` — no client boilerplate
- **URL & QueryParams** — immutable `Url` (httpx-style `copyWith`/`join`), immutable `QueryParams`
- **Event hooks** — multicast request/response callbacks, hot-swappable at runtime
- **Batch executor** — bounded-concurrency batch execution with per-result `Result<T>`
- **Result sinks** — `JsonlSink`, `CsvSink` (with formula-injection sanitization)
- **Type-safe decoders** — pluggable `Decoder<T>` (`JsonDecoder`, `BytesDecoder`, custom)
- **Response model** — `text`, `json()`, `raiseForStatus()`, charset-aware decoding, `hasRedirectLocation`, `history`
- **MockTransport** — handler-backed transport for testing
- **Exception hierarchy** — 30+ typed error classes (`ConnectTimeoutError`, `ReadTimeoutError`, `ProxyError`, `HttpStatusError`, …)
- **Status codes** — `StatusCode` enum with 33 entries and category predicates
- **Metrics** — timeline events via `MetricsSink` / `ConsoleMetricsSink`
- **Base URL** — relative request URIs resolved against a client-level `baseUrl`
- **Two-level config** — `ClientConfig` (transport/timeout/TLS) + `ExecutorConfig` (interceptors/hooks/enrichers)
- **Progress reporter** — per-batch RPS/percentage/ETA via `ProgressReporter`
- **Response enricher SPI** — pluggable enrichers returning custom metadata in `ResponseEnrichment.extra`
- **Response filters** — `StatusCodeFilter`, `RegexFilter`, `Match` (OR/AND) for inclusion/exclusion
- **Log routing** — `stderrLog` helper keeps stdout clean for JSONL/result output
- **BearerAuth** — stateless `BearerAuth('token')` strategy with deprecated legacy flow
- **PortSpec & Headers.parse** — nmap-style `http:8080,https:443` and `Key: Value` parser

## Installation

```yaml
dependencies:
  go_http: ^0.2.3
```

```bash
dart pub get
```

## Quick Start

### GET (top-level API)

```dart
import 'package:go_http/go_http.dart';

void main() async {
  final response = await get<Uint8List>(
    Uri.parse('https://httpbin.org/get'),
  );
  print('Status: ${response.statusCode}');
  print('Body: ${response.text}');
}
```

No client boilerplate — `GoHttpClient` is cached internally. Available:
`get`, `post`, `put`, `delete`, `patch`, `head`, `options`.

```dart
import 'package:go_http/go_http.dart';

final client = GoHttpClient();

try {
  final response = await client.get<Uint8List>(
    Uri.parse('https://httpbin.org/get'),
  );
  print('Status: ${response.statusCode}');
  print('Body: ${response.text}');
} finally {
  client.dispose();
}
```

### POST with JSON

```dart
import 'package:go_http/go_http.dart';

final client = GoHttpClient();

try {
  final response = await client.post<Uint8List>(
    Uri.parse('https://httpbin.org/post'),
    json: {'name': 'John', 'email': 'john@example.com'},
  );
  print('Created: ${response.statusCode}');
  print(response.json());
} finally {
  client.dispose();
}
```

### POST with form-encoded data

```dart
final response = await client.post<Uint8List>(
  Uri.parse('https://httpbin.org/post'),
  data: {'key1': 'value1', 'key2': 'value2'},
);
```

## Core Concepts

### buildRequest / send / request

The client exposes a **3-layer API** (mirroring httpx):

1. `buildRequest(Request)` — merge client config (default headers, cookies, query params, base URL) onto a raw `Request`
2. `send<T>(Request, ...)` — dispatch a prepared `Request` through the full pipeline (interceptors, transport, retry, redirect). Does **not** re-merge.
3. `request<T>(Request, ...)` = `send(buildRequest(req))` — convenience for the common case

Escape hatch: mutate a prepared request before sending.

```dart
final req = client.buildRequest(Request.get(uri));
req.headers.add('x-custom', '1');
final res = await client.send(req);
```

### Cancellation

```dart
import 'dart:async';

final client = GoHttpClient();
final cancelSource = CancellationSource();

Timer(const Duration(seconds: 2), () {
  cancelSource.cancel('Taking too long');
});

try {
  final response = await client.get<Uint8List>(
    Uri.parse('https://httpbin.org/delay/5'),
    cancel: cancelSource.token,
  );
} on CancellationError catch (e) {
  print('Cancelled: ${e.reason}');
} finally {
  cancelSource.dispose();
  client.dispose();
}
```

### Structured Timeouts

```dart
final client = GoHttpClient(
  timeout: const Timeout(
    connect: Duration(seconds: 10),
    read: Duration(seconds: 30),
    write: Duration(seconds: 30),
    pool: Duration(seconds: 10),
  ),
);

// Per-request override: disable connect timeout only
final response = await client.get<Uint8List>(
  uri,
  options: RequestOptions(
    timeout: Timeout(connect: null),
  ),
);
```

`null` = disabled for that phase. `useClientDefault` (the default) = inherit.

### Retry Policy

Default: 3 attempts, 300–2000ms equal-jitter backoff. Retries only for
**idempotent methods** (GET, HEAD, OPTIONS) on network errors, timeouts,
and 429/503/504.

```dart
final client = GoHttpClient(
  retryPolicy: DefaultRetryPolicy(
    maxAttempts: 5,
    baseDelay: const Duration(milliseconds: 500),
    maxDelay: const Duration(seconds: 5),
  ),
  metrics: ConsoleMetricsSink(),
);
```

### Interceptors

```dart
class TimingInterceptor extends Interceptor {
  @override
  Future<Request> onRequest(Request request) async {
    print('[${request.methodString}] ${request.uri}');
    return request;
  }

  @override
  Future<Response> onResponse(Response response) async {
    print('=> ${response.statusCode} (${response.elapsed})');
    return response;
  }
}

final client = GoHttpClient(
  interceptors: [TimingInterceptor(), LoggingInterceptor()],
);
```

### Auth

Basic:
```dart
final client = GoHttpClient(
  interceptors: [AuthInterceptor(auth: BasicAuth('user', 'pass'))],
);
```

Digest (RFC 2617/7616):
```dart
final client = GoHttpClient(
  interceptors: [AuthInterceptor(auth: DigestAuth('user', 'pass'))],
);
```

Bearer token (pre-resolved):
```dart
final client = GoHttpClient(
  interceptors: [AuthInterceptor(auth: BearerAuth('my-token'))],
);
```

Bearer token with auto-refresh (legacy, deprecated):
```dart
String? token;

final client = GoHttpClient(
  interceptors: [
    AuthInterceptor(
      tokenProvider: () async => token,
      tokenRefresher: () async {
        token = await fetchNewToken();
        return token;
      },
    ),
  ],
);
```

### Configuration

Separate `ClientConfig` (transport/TLS/timeout/proxy/cookies) from `ExecutorConfig`
(interceptors/metrics/hooks/enrichers). Both are optional — every field falls back
to a sensible default.

```dart
final client = GoHttpClient(
  clientConfig: const ClientConfig(
    connectTimeout: Duration(seconds: 5),
    sendTimeout: Duration(seconds: 15),
    followRedirects: true,
    maxRedirects: 10,
    trustEnv: true,
  ),
  executorConfig: ExecutorConfig(
    interceptors: [TimingInterceptor()],
    enrichers: [CustomEnricher()],
  ),
);

final errors = client.validate(); // List<ValidationError>
```

Config from JSON / env:
```dart
final cfg = ClientConfig.fromJson({
  'connectTimeout': 5000,
  'maxRedirects': 10,
});
final withEnv = ClientConfig.mergeEnv(cfg); // GO_HTTP_* overrides
```

### Event Hooks

```dart
final client = GoHttpClient(
  eventHooks: EventHooks(
    request: [(req) => print('>> ${req.uri}')],
    response: [(res) => print('<< ${res.statusCode}')],
  ),
);

// Hot-swap at runtime:
client.eventHooks = client.eventHooks.copyWith(
  response: [(res) => metrics.record(res)],
);
```

### Proxy

```dart
final client = GoHttpClient(
  proxyMounts: ProxyMounts({
    URLPattern.parse('http://*'): Proxy.parse('http://proxy:8080'),
    URLPattern.parse('https://*.internal'): null, // direct
  }),
  trustEnv: true, // also honor HTTP_PROXY / HTTPS_PROXY / NO_PROXY
);
```

```dart
final client = GoHttpClient(
  verify: '/etc/ssl/certs/ca-certificates.crt', // custom CA file
  // verify: false, // disable TLS verification (not recommended)
);
```

### Certificate Pinning

```dart
final client = GoHttpClient(
  clientConfig: const ClientConfig(
    pinnedCertificates: PinnedCertificates(
      pins: {
        'api.example.com': ['8Rw90Ej3T3i3C3oG7gQVo0GxGxLxPxQxRxSxTxUxVxWxXxY='],
      },
    ),
  ),
);
```

Fingerprints are SHA-256 of the server's DER-encoded X.509 certificate,
base64-encoded (without the `sha256/` prefix). To compute one:

```dart
import 'dart:convert' show base64;
import 'package:crypto/crypto.dart' show sha256;
final fp = base64.encode(sha256.convert(cert.der).bytes);
```

> **ponytail:** Pin check runs when system CA rejects the cert. True
> MITM-with-forged-CA pinning requires a `PinningDialer` wrapping
> `SecureSocket` directly.

### Headers

```dart
final headers = Headers({'content-type': 'application/json'});
headers.add('set-cookie', 'session=abc');
headers.add('set-cookie', 'token=xyz');

print(headers['content-type']); // "application/json"
print(headers.getAll('set-cookie')); // ["session=abc", "token=xyz"]

// Sensitive headers are masked in toString:
print(headers); // ... authorization: [secure] ...
```

### URL & QueryParams

```dart
final url = Url.parse('HTTPS://EXAMPLE.COM:443/path?a=1');
print(url.scheme); // "https" (lowercased)
print(url.port); // null (443 is default)

final joined = url.join('/sub?b=2');
print(joined); // https://example.com/sub?b=2

final q = QueryParams({'a': '1', 'b': '2'})
    .add('b', '3');
print(q.toQueryString()); // a=1&b=2&b=3
```

### Multipart

```dart
final mp = Multipart(
  fields: [MultipartField('name', 'file.txt')],
  files: [MultipartFile.bytes('file', 'photo.jpg', imageBytes)],
);

final response = await client.post<Uint8List>(
  uri,
  options: RequestOptions(body: mp),
);
// Content-Type and body are auto-encoded.
```

### Content-Encoding

```dart
// gzip and deflate are decoded automatically by default.
// Register brotli/zstd when packages are available:
registerBrotli(() => BrotliDecoder());
registerZstd(() => ZstdDecoder());

// Disable decompression per request:
final response = await client.get<Uint8List>(
  uri,
  options: RequestOptions(autoDecompress: false),
);
```

### Batch Executor

```dart
final executor = BatchExecutor(client, concurrency: 10);
final results = await executor.run<Uint8List>(
  uris.map((u) => Request.get(u)).toList(),
  onProgress: (done, total) => print('$done/$total'),
);

for (final result in results) {
  result.when(
    ok: (res) => print('OK: ${res.statusCode}'),
    fail: (err, req) => print('FAIL: $err'),
  );
}
```

Batch with progress reporter:
```dart
final progress = ProgressReporter(total: 1000);
final results = await executor.run(
  requests,
  onProgress: (done, total) => progress.tick(),
);
// Done: progress.summary → "50.1% 125rps ETA 4s"
```

Multiple result callbacks:
```dart
final results = await executor.run(
  requests,
  onResult: logResult,
  onResults: [writeToSink, updateCounter],
);
```

### Result Sinks

```dart
final sink = ResultSink.jsonl('results.jsonl');
for (final result in results) {
  sink.write(result);
}
await sink.close();
```

Writes are two-phase (temp file + atomic rename on `close()`) — safe for
parallel batch writers. Also available: `CsvSink` with formula-injection
sanitization.

### Response Filters

```dart
// Include only 2xx + body matching a pattern
final filter = Match.any([
  StatusCodeFilter.between(200, 299),
  RegexFilter(RegExp(r'admin')),
]);

if (filter.matches(response)) {
  // process
}
```

Composable via `Match.any` (OR, short-circuit) and `Match.all` (AND,
short-circuit on first miss). Ready for inclusion/exclusion in batch
pipelines.

### Response Model

```dart
final response = await client.get<Uint8List>(uri);

response.text; // body decoded as text (charset-aware)
response.json(); // body decoded as JSON
response.raiseForStatus(); // throw HttpStatusError on 4xx/5xx (chainable)
response.hasRedirectLocation; // true for navigable 3xx with Location
response.history; // redirect chain
response.elapsed; // full round-trip duration
response.charsetEncoding; // from Content-Type
response.encoding = 'windows-1251'; // override charset
response.defaultEncoding = (bytes) => detect(bytes); // auto-detect hook
response.numBytesDownloaded; // body byte count (after decompress)
response.bytes; // body as Stream<List<int>>
response.links['next']?['url']; // parsed Link: header
response.nextRequest; // computed redirect request (when followRedirects:false)
response.httpVersion; // "HTTP/1.1", "HTTP/2.0", etc.
response.reasonPhrase; // alias for statusMessage
```

### MockTransport

```dart
final mt = MockTransport((req) async {
  return Response(
    request: req,
    statusCode: 200,
    headers: {'content-type': 'text/plain'},
    data: Uint8List.fromList(utf8.encode('mock body')),
  );
});

final client = GoHttpClient(transport: mt);
final res = await client.get<Uint8List>(uri);
print(mt.callCount); // 1
```

## Error Handling

```dart
try {
  final response = await client.get<Uint8List>(uri);
} on ConnectTimeoutError catch (e) {
  print('Connection timed out after ${e.timeout}');
} on ReadTimeoutError catch (e) {
  print('Server did not send data in time');
} on ConnectError catch (e) {
  print('DNS or TCP-level failure: ${e.message}');
} on HttpStatusError catch (e) {
  print('HTTP ${e.statusCode}: ${e.response.text}');
} on CancellationError catch (e) {
  print('Cancelled: ${e.reason}');
} on HttpError catch (e) {
  print('Generic HTTP error: $e');
}
```

`HttpStatusError` deliberately does **not** extend `RequestError`, so
`catch (RequestError)` never accidentally swallows a 4xx/5xx.

## Platform Support

| Platform | Transport | Status |
|---|---|---|
| Dart CLI / Server | `IoTransport` (dart:io) | ✅ Full support |
| Flutter Mobile/Desktop | `IoTransport` (dart:io) | ✅ Full support |
| Flutter Web | `WebTransport` (dart:html) | ✅ Full support |

The correct transport is selected automatically via conditional imports.
Stub classes ensure compilation on all platforms with zero configuration.

## Examples

```bash
dart run example/simple_get.dart        # GET with client
dart run example/top_level_get.dart     # GET without client (top-level API)
dart run example/cancel_request.dart
dart run example/retry_policy.dart
dart run example/download_progress.dart # download with onProgress
dart run example/upload_progress.dart   # upload with onSendProgress
dart run example/post_json.dart
dart run example/batch_config.dart
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
