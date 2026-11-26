import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';

void main() {
  test('offers the package when there are no totals at all', () {
    expect(
      installNote(calendarTotals: false),
      'See the data each device uses, per billing period',
    );
  });

  test('calendar totals are enough when the bill starts on the 1st', () {
    expect(installNote(calendarTotals: true, billingDay: 1), isNull);
    expect(installNote(calendarTotals: true), isNull);
  });

  test('offers the package when the billing day is not the 1st', () {
    expect(
      installNote(calendarTotals: true, billingDay: 15),
      contains('not your billing day'),
    );
  });
}
