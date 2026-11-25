import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('requests that accept any certificate never carry the login', () {
    final acceptAny = RegExp(r'badCertificateCallback\s*=\s*\(?\([^)]*\)\s*=>');
    var found = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      for (final m in acceptAny.allMatches(s)) {
        found++;
        final end = m.end + 1200 < s.length ? m.end + 1200 : s.length;
        final after = s.substring(m.end, end);
        expect(
          after.contains('sysauth=') || after.contains("'Cookie'"),
          isFalse,
          reason: '${f.path}: use HttpClientManager().newHttpClient',
        );
      }
    }
    expect(found, greaterThan(0));
  });
}
