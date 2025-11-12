# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

