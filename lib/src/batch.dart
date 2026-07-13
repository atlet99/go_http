import 'dart:math' show min;

import 'client.dart';
import 'codec/decoder.dart';
import 'request.dart';
import 'result.dart';

/// Runs many [Request]s concurrently, collecting a [Result] per request.
///
/// A single failing target never aborts the batch (the error lands in
/// [Result.fail], never thrown). Concurrency is bounded so 100k URLs
/// don't open 100k sockets at once.
class BatchExecutor {
  BatchExecutor(this.client, {this.concurrency = 1});

  final GoHttpClient client;
  final int concurrency;

  Future<List<Result<T>>> run<T>(
    List<Request> requests, {
    Decoder<T>? decoder,
    void Function(int done, int total)? onProgress,
    void Function(Result<T>)? onResult,
    List<ResultCallback>? onResults,
  }) async {
    final total = requests.length;
    final out = <Result<T>>[];
    var done = 0;

    for (var i = 0; i < requests.length; i += concurrency) {
      final slice = requests.sublist(i, min(i + concurrency, total));
      final batch = await Future.wait(
        slice.map((r) => _one<T>(r, decoder)),
      );
      for (final r in batch) {
        out.add(r);
        onResult?.call(r);
        for (final cb in onResults ?? const []) {
          cb(r);
        }
      }
      done += batch.length;
      onProgress?.call(done, total);
    }
    return out;
  }

  Future<Result<T>> _one<T>(Request request, Decoder<T>? decoder) async {
    try {
      final resp = await client.send<T>(request, decoder: decoder);
      return Result.ok(resp);
    } catch (e) {
      return Result.fail(e, request: request);
    }
  }
}
