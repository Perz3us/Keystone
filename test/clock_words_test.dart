import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_screen.dart';

void main() {
  final now = DateTime(2026, 11, 26, 9);

  test('today is just the time, in the given style', () {
    expect(clockWords(DateTime(2026, 11, 26, 8, 5), now), '08:05');
    expect(
      clockWords(DateTime(2026, 11, 26, 8, 5), now, clock: (_) => '8:05 AM'),
      '8:05 AM',
    );
  });

  test('older days say which day', () {
    expect(clockWords(DateTime(2026, 11, 25, 20, 1), now), 'Yesterday 20:01');
    expect(clockWords(DateTime(2026, 11, 2, 7, 30), now), '2 Nov 07:30');
  });
}
