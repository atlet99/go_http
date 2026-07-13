import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('IoTransport scheme fallback', () {
    test('tryHttpOnHttpsError defaults to false', () {
      final t = IoTransport();
      expect(t.tryHttpOnHttpsError, isFalse);
    });

    test('tryHttpOnHttpsError is settable', () {
      final t = IoTransport(tryHttpOnHttpsError: true);
      expect(t.tryHttpOnHttpsError, isTrue);
    });
  });

  group('IoTransport DNS resolver', () {
    test('resolver defaults to null', () {
      final t = IoTransport();
      expect(t.resolver, isNull);
    });

    test('resolver is settable', () {
      final r = SystemDnsResolver();
      final t = IoTransport(resolver: r);
      expect(t.resolver, same(r));
    });
  });
}
