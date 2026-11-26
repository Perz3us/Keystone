import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/background/widget_lines.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';

final now = DateTime(2026, 11, 19, 9);

SimPlan plan(PlanKind kind, {int? gb, double down = 0, double up = 0}) =>
    SimPlan(
      sim: 'main',
      kind: kind,
      allowanceGb: gb,
      billingDay: 1,
      periodStart: DateTime.utc(2026, 11, 1),
      periodEnd: DateTime.utc(2026, 11, 30),
      down: (down * 1e9).round(),
      up: (up * 1e9).round(),
    );

void main() {
  group('data widget', () {
    test('no plan saved yet', () {
      expect(dataWidgetLines(null, now), isNull);
    });

    test('capped', () {
      final d = dataWidgetLines(
        plan(PlanKind.capped, gb: 50, down: 17, up: 1),
        now,
      )!;
      expect(d.used, '18.0 GB');
      expect(d.of, 'of 50 GB');
      expect(d.percent, 36);
      expect(d.reset, '12 days left');
      expect(d.compact, '18.0 / 50 GB · 12 days');
    });

    test('unlimited has no bar', () {
      final d = dataWidgetLines(
        plan(PlanKind.unlimited, down: 16.2, up: 1.8),
        now,
      )!;
      expect(d.used, '18.0 GB');
      expect(d.of, 'Unlimited');
      expect(d.percent, isNull);
      expect(d.split, '↓ 16.2 ↑ 1.8 GB');
      expect(d.reset, 'Resets in 12 days');
      expect(d.compact, '18.0 GB · unlimited · resets in 12 days');
    });

    test('last day', () {
      final last = DateTime(2026, 11, 30, 9);
      expect(
        dataWidgetLines(plan(PlanKind.unlimited, down: 1), last)!.reset,
        'Resets tomorrow',
      );
      final capped = dataWidgetLines(
        plan(PlanKind.capped, gb: 50, down: 1),
        last,
      )!;
      expect(capped.reset, '1 day left');
      expect(capped.compact, '1.0 / 50 GB · 1 day');
    });

    test('over the allowance', () {
      final d = dataWidgetLines(
        plan(PlanKind.capped, gb: 50, down: 52.1),
        now,
      )!;
      expect(d.percent, 100);
      expect(d.reset, '2.1 GB over');
      expect(d.compact, '52.1 / 50 GB · 2.1 GB over');
    });

    test('exactly used up', () {
      final d = dataWidgetLines(plan(PlanKind.capped, gb: 50, down: 50), now)!;
      expect(d.percent, 100);
      expect(d.reset, 'Used up');
    });

    test('an allowance of 0 does not divide by zero', () {
      final d = dataWidgetLines(plan(PlanKind.capped, gb: 0), now)!;
      expect(d.percent, 100);
    });

    test('fair use gets a bar too', () {
      expect(
        dataWidgetLines(
          plan(PlanKind.fairuse, gb: 100, down: 80),
          now,
        )!.percent,
        80,
      );
    });

    test('plan not set', () {
      final d = dataWidgetLines(plan(PlanKind.none, down: 3), now)!;
      expect(d.used, 'Set a data plan');
      expect([d.of, d.split, d.reset, d.compact], everyElement(''));
      expect(d.percent, isNull);
    });
  });

  group('signal line', () {
    test('bands, rsrp and sinr', () {
      expect(
        signalLine(bands: ['B3', 'B1', 'B1'], rsrp: -95, sinr: 14),
        'B3 + B1 + B1 · −95 dBm · SINR 14',
      );
    });
    test('parts it has', () {
      expect(signalLine(bands: ['B3']), 'B3');
      expect(signalLine(rsrp: -97), '−97 dBm');
      expect(signalLine(sinr: -3), 'SINR −3');
    });
    test('nothing', () {
      expect(signalLine(), isNull);
      expect(signalLine(bands: []), isNull);
    });
    test('short band names', () {
      expect(shortBand('B3 (1800 MHz) @20 MHz'), 'B3');
      expect(shortBand('  n78'), 'n78');
    });
  });
}
