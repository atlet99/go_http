import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  test('isCancelled is false by default', () {
    final token = CancellationToken();
    expect(token.isCancelled, isFalse);
  });

  test('cancel sets isCancelled and stores reason', () {
    final token = CancellationToken();
    token.cancel('done');
    expect(token.isCancelled, isTrue);
    expect(token.reason, 'done');
  });

  test('throwIfCancelled throws after cancel', () {
    final token = CancellationToken();
    token.cancel();
    expect(() => token.throwIfCancelled(), throwsA(isA<CancellationException>()));
  });

  test('cancel is idempotent (only fires once)', () {
    final token = CancellationToken();
    var count = 0;
    token.stream.listen((_) => count++);
    token.cancel();
    token.cancel();
    expect(count, 1);
  });

  test('CancellationToken via CancellationSource', () {
    final source = CancellationSource();
    expect(source.isCancelled, isFalse);
    source.cancel('user');
    expect(source.token.isCancelled, isTrue);
    expect(source.token.reason, 'user');
  });
}
