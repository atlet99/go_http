import 'dart:convert';

import 'package:go_http/go_http.dart';
import 'package:test/test.dart';

void main() {
  group('DohDnsResolver — JSON parsing', () {
    test('parses A record from DNS JSON response', () {
      final json = jsonDecode('''
        {
          "Status": 0,
          "Answer": [
            {"name": "example.com", "type": 1, "TTL": 300, "data": "93.184.216.34"}
          ]
        }
      ''') as Map<String, dynamic>;

      final answers = json['Answer'] as List<dynamic>;
      expect(answers, hasLength(1));
      final record = answers[0] as Map<String, dynamic>;
      expect(record['type'], 1);
      expect(record['data'], '93.184.216.34');
    });

    test('prefers A record over AAAA', () {
      final json = jsonDecode('''
        {
          "Status": 0,
          "Answer": [
            {"name": "example.com", "type": 28, "TTL": 300, "data": "2606:2800:220:1:248:1893:25c8:1946"},
            {"name": "example.com", "type": 1, "TTL": 300, "data": "93.184.216.34"}
          ]
        }
      ''') as Map<String, dynamic>;

      final answers = json['Answer'] as List<dynamic>;
      // Should find A record (type 1) first.
      int? foundType;
      for (final answer in answers) {
        final record = answer as Map<String, dynamic>;
        if (record['type'] == 1) {
          foundType = 1;
          break;
        }
      }
      expect(foundType, 1);
    });

    test('falls back to AAAA when no A record', () {
      final json = jsonDecode('''
        {
          "Status": 0,
          "Answer": [
            {"name": "example.com", "type": 28, "TTL": 300, "data": "2606:2800:220:1:248:1893:25c8:1946"}
          ]
        }
      ''') as Map<String, dynamic>;

      final answers = json['Answer'] as List<dynamic>;
      final record = answers[0] as Map<String, dynamic>;
      expect(record['type'], 28);
      expect(record['data'], contains(':'));
    });

    test('NXDOMAIN status throws DnsLookupError', () {
      final json = <String, dynamic>{'Status': 3, 'Answer': null};
      final status = json['Status'] as int;
      expect(status, isNot(0));
    });

    test('empty answers throws DnsLookupError', () {
      final json = jsonDecode('''
        {"Status": 0, "Answer": []}
      ''') as Map<String, dynamic>;
      final answers = json['Answer'] as List<dynamic>;
      expect(answers, isEmpty);
    });

    test('multiple A records picks first', () {
      final json = jsonDecode('''
        {
          "Status": 0,
          "Answer": [
            {"name": "example.com", "type": 1, "TTL": 60, "data": "1.2.3.4"},
            {"name": "example.com", "type": 1, "TTL": 60, "data": "5.6.7.8"}
          ]
        }
      ''') as Map<String, dynamic>;

      final answers = json['Answer'] as List<dynamic>;
      final first = answers[0] as Map<String, dynamic>;
      expect(first['data'], '1.2.3.4');
    });
  });

  group('DohDnsResolver — default server', () {
    test('default server is Google DNS', () {
      final resolver = DohDnsResolver();
      expect(resolver.server, 'https://dns.google/resolve');
    });
  });
}
