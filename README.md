# go_http

**Reliable HTTP client for Dart — built for control, cancellation and consistency.**

[![pub package](https://img.shields.io/pub/v/go_http.svg)](https://pub.dev/packages/go_http)
[![License: BSD 3-Clause](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)

`go_http` is a modern, cross-platform HTTP client for Dart that provides fine-grained control over requests, built-in retry mechanisms, cancellation support, and a powerful interceptor system.

## ✨ Features

- ✅ **Cross-platform**: Works identically on Dart CLI, Flutter Mobile/Desktop, and Web
- ✅ **Cancellation**: Every request can be cancelled at any time with `CancellationToken`
- ✅ **Retry Policy**: Smart retry with exponential backoff + equal jitter (only for idempotent methods)
- ✅ **Timeouts**: Real per-phase timeouts (`connectTimeout`/`sendTimeout`/`receiveTimeout`) that throw `TimeoutError`
- ✅ **Interceptors**: Request/response/error interceptors for logging, auth, etc.
- ✅ **Auth Refresh**: `AuthInterceptor` refreshes credentials on `401` and retries the request automatically
- ✅ **Cookie Store**: Automatic cookie management with `MemoryCookieStore` (multi-value `Set-Cookie`, `Domain` attribute)
- ✅ **Metrics**: Built-in metrics collection with `ConsoleMetricsSink`
- ✅ **Decoders**: Type-safe response decoding via pluggable `Decoder<T>` (`JsonDecoder`, `BytesDecoder`)
- ✅ **Download Progress**: `onReceiveProgress` callback for tracking byte progress
- ✅ **All HTTP methods**: `get`, `post`, `put`, `delete`, `patch`, `head`, `options`
- ✅ **Error Handling**: Comprehensive error types (`NetworkError`, `HttpResponseError`, `TimeoutError`, `CancellationError`)
- ✅ **Redirects**: Configurable redirect handling
- ✅ **Injectable logging**: `LoggingInterceptor` / `ConsoleMetricsSink` accept a custom `Logger` sink

## 📦 Installation

Add `go_http` to your `pubspec.yaml`:

```yaml
dependencies:
  go_http: ^0.2.0
```

Then run:

```bash
dart pub get
```

## 🚀 Quick Start

### Basic GET Request

```dart
import 'package:go_http/go_http.dart';

final client = GoHttpClient();

try {
  final response = await client.get<Uint8List>(
    Uri.parse('https://api.example.com/data'),
  );
  
  print('Status: ${response.statusCode}');
  print('Data: ${response.data?.length} bytes');
} catch (e) {
  print('Error: $e');
} finally {
  client.dispose();
}
```

### POST Request with JSON

```dart
import 'dart:convert';
import 'package:go_http/go_http.dart';

final client = GoHttpClient();

try {
  final response = await client.post<Uint8List>(
    Uri.parse('https://api.example.com/users'),
    data: jsonEncode({
      'name': 'John Doe',
      'email': 'john@example.com',
    }),
    options: RequestOptions(
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );
  
  print('Created: ${response.statusCode}');
  final responseData = jsonDecode(utf8.decode(response.data!));
  print('Response: $responseData');
} catch (e) {
  print('Error: $e');
} finally {
  client.dispose();
}
```

## 🎯 Core Concepts

### Request Cancellation

Every request can be cancelled at any time using `CancellationToken`:

```dart
import 'dart:async';
import 'package:go_http/go_http.dart';

final client = GoHttpClient();
final cancelSource = CancellationSource();

// Cancel the request after 2 seconds
Timer(const Duration(seconds: 2), () {
  print('Cancelling request...');
  cancelSource.cancel('User cancelled');
});

try {
  final response = await client.get<Uint8List>(
    Uri.parse('https://api.example.com/slow-endpoint'),
    cancel: cancelSource.token,
  );
  
  print('Response: ${response.statusCode}');
} on CancellationError catch (e) {
  print('Request was cancelled: ${e.reason}');
} catch (e) {
  print('Error: $e');
} finally {
  cancelSource.dispose();
  client.dispose();
}
```

### Retry Policy

By default, `go_http` retries failed requests up to 3 times with exponential backoff **with equal jitter** (an AWS-recommended, stateless strategy that is safe to share across concurrent requests). Retries are **only performed for idempotent methods** (GET, HEAD, OPTIONS) to ensure safety.

```dart
final client = GoHttpClient(
  retryPolicy: DefaultRetryPolicy(
    maxAttempts: 5,
    baseDelay: const Duration(milliseconds: 500),
    maxDelay: const Duration(seconds: 5),
  ),
  metrics: ConsoleMetricsSink(), // See retry attempts in console
);

try {
  final response = await client.get<Uint8List>(
    Uri.parse('https://api.example.com/unstable-endpoint'),
  );
} catch (e) {
  print('Error after retries: $e');
}
```

**Retry triggers:**
- Network errors (`NetworkError`)
- Timeout errors (`TimeoutError`)
- HTTP status codes: 429 (Too Many Requests), 503 (Service Unavailable), 504 (Gateway Timeout)

### Interceptors

Interceptors allow you to modify requests, responses, and handle errors. They are executed in the order they are added.

#### Logging Interceptor

```dart
final client = GoHttpClient(
  interceptors: [
    LoggingInterceptor(
      logRequest: true,
      logResponse: true,
      logError: true,
    ),
  ],
);

// All requests/responses will be logged
// Sensitive headers (authorization, cookie, etc.) are automatically masked
```

#### Auth Interceptor

Automatically add authentication tokens and refresh them when needed. On a
`401 Unauthorized`, the token is refreshed via `tokenRefresher` and the request
is retried once (re-running the request interceptors so the fresh token is
attached):

```dart
String? authToken;

final client = GoHttpClient(
  interceptors: [
    AuthInterceptor(
      tokenProvider: () async => authToken,
      tokenRefresher: () async {
        // Refresh token logic
        final newToken = await refreshAuthToken();
        authToken = newToken;
        return newToken;
      },
      headerName: 'Authorization',
      headerPrefix: 'Bearer ',
    ),
  ],
);
```

#### Custom Interceptor

Create your own interceptors:

```dart
class RequestIdInterceptor extends Interceptor {
  @override
  Future<Request> onRequest(Request request) async {
    final headers = Map<String, String>.from(request.headers);
    headers['X-Request-ID'] = _generateRequestId();
    return request.copyWith(headers: headers);
  }

  String _generateRequestId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

final client = GoHttpClient(
  interceptors: [
    RequestIdInterceptor(),
    LoggingInterceptor(),
  ],
);
```

### Timeouts

Timeouts are enforced **per phase** (`connect`, `send`, `receive`) and throw
`TimeoutError` when exceeded. They can be set globally on the client and
overridden per request:

```dart
final client = GoHttpClient(
  connectTimeout: const Duration(seconds: 10),
  sendTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(seconds: 30),
);

// Override per request
final response = await client.get<Uint8List>(
  Uri.parse('https://api.example.com/data'),
  options: const RequestOptions(receiveTimeout: Duration(seconds: 5)),
);
```

> On native platforms each phase is timed independently via `dart:io`. On the
> web a single overall request timeout is applied (XHR limitation).

### Error Handling

`go_http` provides comprehensive error types:

```dart
try {
  final response = await client.get<Uint8List>(uri);
} on NetworkError catch (e) {
  // Network issues (connection timeout, DNS failure, etc.)
  print('Network error: ${e.message}');
} on HttpResponseError catch (e) {
  // HTTP error responses (4xx, 5xx)
  print('HTTP ${e.statusCode}: ${e.message}');
} on TimeoutError catch (e) {
  // Request timeout
  print('Timeout after ${e.timeout.inSeconds}s');
} on CancellationError catch (e) {
  // Request was cancelled
  print('Cancelled: ${e.reason}');
} catch (e) {
  // Other errors
  print('Unexpected error: $e');
}
```

### Cookie Management

Automatic cookie handling with `MemoryCookieStore`:

```dart
final client = GoHttpClient(
  cookieStore: MemoryCookieStore(),
);

// Cookies are automatically stored from responses
// and added to subsequent requests for the same domain
final response = await client.get<Uint8List>(
  Uri.parse('https://example.com/login'),
);

// Cookies from login response are now stored
// and will be sent with subsequent requests
```

You can also create custom cookie stores:

```dart
class PersistentCookieStore implements CookieStore {
  // Implement persistent storage (file, database, etc.)
  @override
  List<String> getCookies(Uri uri) {
    // Load cookies from storage
  }

  @override
  void setCookies(Response response) {
    // Save cookies to storage
  }

  @override
  void clear() {
    // Clear all cookies
  }

  @override
  void clearDomain(String domain) {
    // Clear cookies for specific domain
  }
}
```

### Metrics

Track request metrics with `ConsoleMetricsSink`:

```dart
final client = GoHttpClient(
  metrics: ConsoleMetricsSink(),
);

// Metrics will be logged:
// - Request start
// - Request completion
// - Retry attempts
// - Errors
```

You can also create custom metrics sinks:

```dart
class CustomMetricsSink implements MetricsSink {
  @override
  void onRequestStart(Request request) {
    // Track request start
  }

  @override
  void onRequestEnd(Request request, Response response) {
    // Track request completion
  }

  @override
  void onRetry(Request request, int attempt, Duration delay) {
    // Track retry attempts
  }

  @override
  void onError(HttpError error) {
    // Track errors
  }
}
```

## ⚙️ Configuration

### Full Configuration Example

```dart
final client = GoHttpClient(
  // Transport (auto-detected by platform)
  // transport: IoTransport() or WebTransport(),
  
  // Interceptors
  interceptors: [
    LoggingInterceptor(),
    AuthInterceptor(/* ... */),
  ],
  
  // Retry policy
  retryPolicy: DefaultRetryPolicy(
    maxAttempts: 3,
    baseDelay: const Duration(milliseconds: 300),
    maxDelay: const Duration(milliseconds: 2000),
  ),
  
  // Redirect policy
  redirectPolicy: DefaultRedirectPolicy(
    maxRedirects: 5,
  ),
  
  // Cookie store
  cookieStore: MemoryCookieStore(),
  
  // Timeouts
  connectTimeout: const Duration(seconds: 10),
  sendTimeout: const Duration(seconds: 30),
  receiveTimeout: const Duration(seconds: 30),
  
  // Redirects
  followRedirects: true,
  maxRedirects: 5,
  
  // Other options
  autoDecompress: true,
  defaultHeaders: {
    'User-Agent': 'my-app/1.0',
    'Accept': 'application/json',
  },
  
  // Metrics
  metrics: ConsoleMetricsSink(),
);
```

### Per-Request Options

You can override client settings for individual requests:

```dart
final response = await client.get<Uint8List>(
  Uri.parse('https://api.example.com/data'),
  options: RequestOptions(
    headers: {
      'X-Custom-Header': 'value',
    },
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
```

## 📚 Examples

See the `example/` directory for complete examples:

- **`simple_get.dart`** - Basic GET request
- **`cancel_request.dart`** - Request cancellation
- **`retry_policy.dart`** - Custom retry policy with metrics
- **`download_progress.dart`** - File download

### Running Examples

```bash
# Simple GET request
dart run example/simple_get.dart

# Cancel request example
dart run example/cancel_request.dart

# Retry policy example
dart run example/retry_policy.dart

# Download example
dart run example/download_progress.dart
```

## 🔧 Advanced Usage

### Custom Transport

You can provide a custom transport implementation:

```dart
class CustomTransport implements Transport {
  @override
  Future<Response> send(
    Request request, {
    CancellationToken? cancel,
    // ... other parameters
  }) async {
    // Custom implementation
  }

  @override
  void dispose() {
    // Cleanup
  }
}

final client = GoHttpClient(
  transport: CustomTransport(),
);
```

### Type-Safe Responses

Pass a `Decoder<T>` to any request method to get a properly-typed
`Response<T>` — the body is decoded once, inside the client, with no unsafe
casts:

```dart
// Decode JSON automatically
final response = await client.get<dynamic>(
  Uri.parse('https://api.example.com/data'),
  decoder: JsonDecoder(),
);
final data = response.data as Map<String, dynamic>;
print(data['key']);

// Raw bytes (default when no decoder is supplied)
final bytes = await client.get<Uint8List>(Uri.parse('https://x.test/image'));
```

### Response Decoders

`go_http` provides decoders for common response formats:

#### JSON Decoder

```dart
import 'package:go_http/go_http.dart';

final jsonDecoder = JsonDecoder();
final response = await client.get<Uint8List>(uri);

// Automatically decode JSON from bytes or string
final jsonData = jsonDecoder.decode(response.data!);
print(jsonData['key']); // Access decoded JSON
```

#### Bytes Decoder

```dart
import 'package:go_http/go_http.dart';

final bytesDecoder = BytesDecoder();
final response = await client.get<Uint8List>(uri);

// Ensure data is Uint8List
final bytes = bytesDecoder.decode(response.data!);
```

#### Custom Decoder

You can create your own decoders:

```dart
class XmlDecoder implements Decoder<String> {
  @override
  String decode(dynamic data) {
    if (data is String) {
      return data;
    } else if (data is Uint8List) {
      return utf8.decode(data);
    }
    throw ArgumentError('Cannot decode to XML string');
  }
}
```

### Redirect Policy

Control how redirects are handled:

```dart
final client = GoHttpClient(
  redirectPolicy: DefaultRedirectPolicy(
    maxRedirects: 10, // Allow up to 10 redirects
  ),
  followRedirects: true,
);

// Custom redirect policy
class CustomRedirectPolicy implements RedirectPolicy {
  @override
  int get maxRedirects => 3;

  @override
  bool shouldFollowRedirect(
    Request request,
    Response response,
    int redirectCount,
  ) {
    // Only follow redirects for specific status codes
    return response.statusCode == 301 || response.statusCode == 302;
  }
}
```

## 🛡️ Security

- **Retries**: Only performed for idempotent HTTP methods (GET, HEAD, OPTIONS)
- **Sensitive Data**: Headers like `authorization`, `cookie`, `set-cookie`, `x-api-key` are automatically masked in logs
- **TLS**: TLS verification is enabled by default
- **Timeouts**: Real per-phase timeouts prevent hanging requests

## 🌐 Platform Support

| Platform               | Transport                  | Status            |
| ---------------------- | -------------------------- | ----------------- |
| Dart CLI / Server      | `IoTransport` (dart:io)    | ✅ Fully supported |
| Flutter Mobile/Desktop | `IoTransport` (dart:io)    | ✅ Fully supported |
| Flutter Web            | `WebTransport` (dart:html) | ✅ Fully supported |

The appropriate transport is automatically selected based on the platform using **conditional imports**. This ensures that:

- **Native platforms** (Dart CLI, Flutter Mobile/Desktop) use `IoTransport` with `dart:io`
- **Web platforms** (Flutter Web) use `WebTransport` with `dart:html`
- **No platform-specific code** is required in your application

The library uses Dart's conditional imports (`if (dart.library.io)` and `if (dart.library.html)`) to automatically select the correct transport implementation. Stub classes are provided for platforms where a transport is not available, ensuring the code compiles on all platforms without any additional configuration.

## 📖 API Reference

### GoHttpClient

Main HTTP client class.

**Methods:**
- `Future<Response<T>> get<T>(Uri url, {RequestOptions? options, CancellationToken? cancel, Decoder<T>? decoder, ProgressCallback? onProgress})`
- `Future<Response<T>> post<T>(Uri url, {Object? data, RequestOptions? options, CancellationToken? cancel, Decoder<T>? decoder, ProgressCallback? onProgress})`
- `Future<Response<T>> put<T>(...)`, `delete<T>(...)`, `patch<T>(...)`, `head<T>(...)`, `options<T>(...)` — same signature shape
- `Future<Response<T>> request<T>(Request req, {CancellationToken? cancel, Decoder<T>? decoder, ProgressCallback? onProgress})`
- `void dispose()` - Clean up resources

### CancellationSource

Source for creating cancellation tokens.

**Methods:**
- `CancellationToken get token` - Get the cancellation token
- `void cancel([String? reason])` - Cancel the token
- `void dispose()` - Clean up resources

### DefaultRetryPolicy

Default retry policy with decorrelated jitter backoff.

**Parameters:**
- `maxAttempts` (default: 3) - Maximum number of retry attempts
- `baseDelay` (default: 300ms) - Base delay for backoff
- `maxDelay` (default: 2000ms) - Maximum delay between retries

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the [BSD 3-Clause License](LICENSE).

## 🙏 Acknowledgments

Inspired by modern HTTP clients like `axios`, `requests`, and `http` package, but built specifically for Dart with focus on cancellation, retry policies, and cross-platform consistency.

---

**Made with ❤️ for the Dart community**