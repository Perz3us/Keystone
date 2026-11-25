// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_analysis.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_data.dart';

final _t0 = DateTime(2026, 1, 1);

HistoryPoint _p(
  int min, {
  double? rsrp,
  double? sinr,
  double? ping,
  String? pci,
  String? earfcn,
}) => HistoryPoint(
  t: _t0.add(Duration(minutes: min)),
  rsrp: rsrp,
  sinr: sinr,
  ping: ping,
  pci: pci,
  earfcn: earfcn,
  band: 'B3',
);

List<HistoryPoint> _run(int to, {double? rsrp, double? sinr, double? ping}) => [
  for (var m = 0; m <= to; m += 2) _p(m, rsrp: rsrp, sinr: sinr, ping: ping),
];

void main() {
  group('slowPeriods', () {
    test('12 minutes of weak RSRP is one period', () {
      final r = slowPeriods(_run(12, rsrp: -112));
      expect(r, [(_t0, _t0.add(const Duration(minutes: 12)))]);
    });
    test('8 minutes is not enough', () {
      expect(slowPeriods(_run(8, rsrp: -112)), isEmpty);
    });
    test('SINR and ping count', () {
      expect(slowPeriods(_run(12, sinr: -1)), hasLength(1));
      expect(slowPeriods(_run(12, ping: 160)), hasLength(1));
    });
    test('good values are not slow', () {
      expect(slowPeriods(_run(30, rsrp: -90, sinr: 10, ping: 40)), isEmpty);
    });
    test('null values do not break a period', () {
      final p = [
        _p(0, rsrp: -115),
        _p(4, rsrp: -115),
        _p(6),
        _p(8, rsrp: -115),
        _p(12, rsrp: -115),
      ];
      expect(slowPeriods(p), hasLength(1));
    });
    test('a good point breaks a period', () {
      final p = [
        _p(0, rsrp: -115),
        _p(6, rsrp: -115),
        _p(8, rsrp: -90),
        _p(12, rsrp: -115),
      ];
      expect(slowPeriods(p), isEmpty);
    });
    test('a gap over 10 minutes ends a period', () {
      final p = [_p(0, rsrp: -115), _p(8, rsrp: -115), _p(30, rsrp: -115)];
      expect(slowPeriods(p), isEmpty);
    });
  });

  group('towers', () {
    final pts = [
      _p(0, rsrp: -90, pci: '1', earfcn: '100'),
      _p(20, rsrp: -100, pci: '1', earfcn: '100'),
      _p(30, rsrp: -80, pci: '2', earfcn: '200'),
      _p(90, rsrp: -70, pci: '2', earfcn: '200'),
      _p(95, rsrp: -60),
      _p(100, rsrp: -60, pci: '2', earfcn: '200'),
    ];
    test('time is capped per gap and sorted', () {
      final s = towerSummary(pts);
      expect(s.map((e) => e.pci), ['1', '2']);
      expect(s[0].time, const Duration(minutes: 20));
      expect(s[1].time, const Duration(minutes: 15));
      expect(s[0].avgRsrp, -95);
      expect(s[1].avgRsrp, -70);
    });
    test('bestTower needs 30 minutes', () {
      final s = [
        const TowerUse(
          pci: 'a',
          earfcn: '1',
          time: Duration(minutes: 10),
          avgRsrp: -60,
        ),
        const TowerUse(
          pci: 'b',
          earfcn: '1',
          time: Duration(minutes: 40),
          avgRsrp: -90,
        ),
        const TowerUse(
          pci: 'c',
          earfcn: '1',
          time: Duration(minutes: 40),
          avgRsrp: -80,
        ),
      ];
      expect(bestTower(s)!.pci, 'c');
      expect(bestTower(s.take(1).toList()), isNull);
    });
  });

  group('edge cases', () {
    test('thin with empty list or non-positive max', () {
      final p = _run(10, rsrp: -100);
      expect(thin([], 0), isEmpty);
      expect(thin([], -1), isEmpty);
      expect(thin(p, 0), isEmpty);
      expect(thin(p, -1), isEmpty);
    });
    test('slowPeriods of empty list', () {
      expect(slowPeriods([]), isEmpty);
    });
    test('single point tower has zero time', () {
      final s = towerSummary([_p(0, rsrp: -90, pci: '1', earfcn: '1')]);
      expect(s.single.time, Duration.zero);
    });
    test('equal times are ordered by pci then earfcn', () {
      final s = towerSummary([
        _p(0, pci: '2', earfcn: '1'),
        _p(5, pci: '1', earfcn: '2'),
        _p(10, pci: '1', earfcn: '1'),
        _p(15),
      ]);
      expect(s.map((e) => '${e.pci}/${e.earfcn}'), ['1/1', '1/2', '2/1']);
    });
    test('duplicate timestamps do not crash', () {
      final p = [
        for (var i = 0; i < 30; i++)
          _p(0, rsrp: -100.0 - i, pci: '1', earfcn: '1'),
      ];
      expect(towerSummary(p).single.time, Duration.zero);
      expect(slowPeriods(p), isEmpty);
      expect(thin(p, 5).length, lessThanOrEqualTo(5));
    });
  });

  group('thin', () {
    test('unchanged under the limit', () {
      final p = _run(10, rsrp: -100);
      expect(identical(thin(p, 100), p), isTrue);
    });
    test('reduces, keeps tower changes and worst points', () {
      final p = [
        for (var m = 0; m < 200; m++)
          _p(
            m,
            rsrp: m == 57 ? -130 : -90,
            pci: m < 150 ? '1' : '2',
            earfcn: '100',
          ),
      ];
      final r = thin(p, 20);
      expect(r.length, lessThanOrEqualTo(20));
      expect(r.any((e) => e.t == p[150].t), isTrue);
      expect(r.any((e) => e.rsrp == -130), isTrue);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].t.isAfter(r[i - 1].t), isTrue);
      }
    });
    test('too many tower changes are cut to max', () {
      final p = [for (var m = 0; m < 50; m++) _p(m, pci: '$m', earfcn: '1')];
      expect(thin(p, 10), hasLength(10));
    });
  });
}
