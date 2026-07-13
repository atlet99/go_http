import 'package:go_http/go_http.dart';

// Пример: конфигурация клиента, batch с ProgressReporter и фильтрация.
//
// Запуск:
//   dart run example/batch_config.dart

void main() async {
  final client = GoHttpClient(
    clientConfig: const ClientConfig(
      connectTimeout: Duration(seconds: 5),
      maxRedirects: 3,
    ),
    executorConfig: ExecutorConfig(
      interceptors: [LoggingInterceptor()],
    ),
  );

  final uris = [
    Uri.parse('https://httpbin.org/status/200'),
    Uri.parse('https://httpbin.org/status/404'),
    Uri.parse('https://httpbin.org/html'),
    Uri.parse('https://httpbin.org/status/500'),
  ];

  final progress = ProgressReporter(total: uris.length);

  final executor = BatchExecutor(client, concurrency: 2);
  final results = await executor.run(
    uris.map((u) => Request(method: HttpMethod.get, uri: u)).toList(),
    onProgress: (done, _) => progress.tick(),
  );

  // Фильтр: только 2xx или 404
  final filter = Match.any([
    StatusCodeFilter.between(200, 299),
    StatusCodeFilter.exact(404),
  ]);

  for (final result in results) {
    result.when(
      ok: (res) {
        if (filter.matches(res)) {
          print('MATCH: ${res.statusCode} ${res.request.uri}');
        } else {
          print('SKIP:  ${res.statusCode} ${res.request.uri}');
        }
      },
      fail: (err, req) {
        print('FAIL:  ${req?.uri} — $err');
      },
    );
  }

  print('\n--- Summary ---');
  print(progress.summary);
  client.dispose();
}
