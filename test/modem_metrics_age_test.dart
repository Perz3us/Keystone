import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';

void main() {
  const up = {'ipaddr': '10.0.0.2', 'mode': 'LTE | B3'};

  test('a fresh reading is trusted', () {
    const m = ModemMetrics(up, age: 30);
    expect(m.stale, isFalse);
    expect(m.connected, isTrue);
  });

  test('an old reading is not shown as connected', () {
    const m = ModemMetrics(up, age: ModemMetrics.staleAfter + 1);
    expect(m.stale, isTrue);
    expect(m.connected, isFalse);
  });

  test('no age known is trusted as before', () {
    expect(const ModemMetrics(up).connected, isTrue);
  });
}
