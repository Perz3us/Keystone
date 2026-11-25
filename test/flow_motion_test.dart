// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';

void main() {
  test('one empty sample does not hide the dots, a quiet line does', () {
    final m = FlowMotion();
    m.step({'tv': 2.0}, 1 / 60);
    expect(m.rate('tv'), 2.0);
    for (var i = 0; i < 180; i++) {
      m.step({'tv': 0}, 1 / 60);
    }
    expect(m.rate('tv'), greaterThan(FlowMotion.minRate));
    expect(m.busy, isTrue);
    for (var i = 0; i < 600; i++) {
      m.step({'tv': 0}, 1 / 60);
    }
    expect(m.rate('tv'), 0);
    expect(m.busy, isFalse);
  });

  test('dots move on from where they are when the speed changes', () {
    final m = FlowMotion();
    for (var i = 0; i < 30; i++) {
      m.step({'tv': 1}, 1 / 60);
    }
    final before = m.phase('tv');
    m.step({'tv': 100}, 1 / 60);
    final moved = (m.phase('tv') - before) % FlowMotion.gap;
    expect(moved, closeTo(FlowMotion.speed(100) / 60, 1e-9));
  });

  test('speed grows with the rate and stops at a cap', () {
    expect(FlowMotion.speed(1), lessThan(FlowMotion.speed(10)));
    expect(FlowMotion.speed(10), lessThan(FlowMotion.speed(100)));
    expect(FlowMotion.speed(100), lessThan(FlowMotion.speed(300)));
    expect(FlowMotion.speed(100000), FlowMotion.maxSpeed);
    expect(FlowMotion.maxSpeed / 60, lessThan(FlowMotion.gap / 3));
  });
}
