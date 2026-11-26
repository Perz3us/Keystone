import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/slow/slow_checks.dart';
import 'package:yet_another_luci_app/modules/noobwrt/slow/slow_screen.dart';

SimPlan plan(PlanKind kind, double usedGb) => SimPlan(
  sim: 'main',
  kind: kind,
  allowanceGb: 100,
  billingDay: 1,
  periodStart: DateTime.utc(2026, 11),
  periodEnd: DateTime.utc(2026, 11, 30),
  down: (usedGb * 1e9).round(),
  up: 0,
);

void main() {
  group('signal', () {
    test('weak power', () {
      expect(
        signalFinding(rsrp: -111, sinr: 10)!.score,
        greaterThanOrEqualTo(80),
      );
    });
    test('just inside the line', () {
      expect(signalFinding(rsrp: -110, sinr: 10), isNull);
    });
    test('noisy', () {
      expect(
        signalFinding(rsrp: -90, sinr: -1)!.score,
        greaterThanOrEqualTo(80),
      );
      expect(signalFinding(rsrp: -90, sinr: 0), isNull);
    });
    test('no readings is not a cause', () {
      expect(signalFinding(), isNull);
    });
  });

  group('line ping', () {
    test('slow', () {
      expect(linePingFinding([40, 160])!.score, greaterThanOrEqualTo(80));
    });
    test('fine at the line', () {
      expect(linePingFinding([150, 150]), isNull);
    });
    test('jumpy', () {
      expect(
        linePingFinding([20, 90, 20, 90])!.score,
        greaterThanOrEqualTo(80),
      );
      expect(linePingFinding([20, 60, 20, 60]), isNull);
    });
    test('nothing measured', () => expect(linePingFinding([]), isNull));
  });

  group('phone Wi-Fi', () {
    test('far from the router', () {
      expect(phoneWifiFinding(-76)!.score, greaterThanOrEqualTo(80));
      expect(phoneWifiFinding(-75), isNull);
    });
    test('unknown', () => expect(phoneWifiFinding(null), isNull));
  });

  group('busy device', () {
    test('one device takes most of the line', () {
      final f = heavyDeviceFinding(
        name: 'Living-room TV',
        mac: 'aa',
        deviceBps: 8e6,
        totalBps: 10e6,
      )!;
      expect(f.score, greaterThanOrEqualTo(80));
      expect(f.fix!.label, 'Pause Living-room TV');
    });
    test('busy but small', () {
      expect(
        heavyDeviceFinding(
          name: 'x',
          mac: 'aa',
          deviceBps: 4.9e6,
          totalBps: 5e6,
        ),
        isNull,
      );
    });
    test('fast but sharing', () {
      expect(
        heavyDeviceFinding(
          name: 'x',
          mac: 'aa',
          deviceBps: 6.9e6,
          totalBps: 10e6,
        ),
        isNull,
      );
    });
  });

  test('proxy is a note, not a verdict', () {
    expect(proxyFinding(true)!.score, 40);
    expect(proxyFinding(false), isNull);
  });

  test('fair use passed', () {
    expect(fairUseFinding(plan(PlanKind.fairuse, 101))!.score, 90);
    expect(fairUseFinding(plan(PlanKind.fairuse, 99)), isNull);
    expect(fairUseFinding(plan(PlanKind.capped, 101)), isNull);
    expect(fairUseFinding(null), isNull);
  });

  test('SQM limit is mentioned', () {
    expect(
      sqmFinding(enabled: true, downloadKbit: 20000)!.detail,
      contains('20'),
    );
    expect(sqmFinding(enabled: false, downloadKbit: 20000), isNull);
    expect(sqmFinding(enabled: true, downloadKbit: 0), isNull);
  });

  group('running them', () {
    SlowFinding f(SlowCause c, int s) =>
        SlowFinding(cause: c, score: s, detail: '');

    test('the biggest is the answer', () async {
      final r = await runSlowChecks({
        SlowCause.proxyOn: () async => f(SlowCause.proxyOn, 40),
        SlowCause.weakSignal: () async => f(SlowCause.weakSignal, 85),
        SlowCause.linePing: () async => null,
      });
      expect(r.top!.cause, SlowCause.weakSignal);
      expect(r.others.single.cause, SlowCause.proxyOn);
      expect(r.couldntCheck, isEmpty);
    });
    test('small findings are dropped', () async {
      final r = await runSlowChecks({
        SlowCause.proxyOn: () async => f(SlowCause.proxyOn, 29),
      });
      expect(r.top, isNull);
    });
    test('a check that hangs', () async {
      final r = await runSlowChecks({
        SlowCause.linePing: () => Completer<SlowFinding?>().future,
      }, timeout: const Duration(milliseconds: 10));
      expect(r.couldntCheck, [SlowCause.linePing]);
      expect(r.top, isNull);
    });
    test('a check that breaks', () async {
      final r = await runSlowChecks({
        SlowCause.sqm: () async => throw StateError('x'),
        SlowCause.weakSignal: () async => f(SlowCause.weakSignal, 85),
      });
      expect(r.couldntCheck, [SlowCause.sqm]);
      expect(r.top!.cause, SlowCause.weakSignal);
    });
    test('all fine', () async {
      final r = await runSlowChecks({SlowCause.linePing: () async => null});
      expect(r.top, isNull);
      expect(slowHeadline(r), 'Nothing looks wrong right now');
    });
    test('they run at the same time', () async {
      final start = DateTime.now();
      await runSlowChecks({
        for (final c in SlowCause.values)
          c: () async {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            return null;
          },
      });
      expect(
        DateTime.now().difference(start),
        lessThan(const Duration(milliseconds: 400)),
      );
    });
  });

  testWidgets(
    'screen names the cause, offers the fix and says what it missed',
    (t) async {
      var opened = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [KeystoneColors.light]),
          home: SlowScreen(
            checks: () => {
              SlowCause.weakSignal: () async => SlowFinding(
                cause: SlowCause.weakSignal,
                score: 85,
                detail: 'The mobile signal is weak (-114 dBm).',
                fix: SlowFix('Check the modem', (_) => opened++),
              ),
              SlowCause.proxyOn: () async => proxyFinding(true),
              SlowCause.sqm: () async => throw StateError('x'),
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('The mobile signal is weak (-114 dBm).'),
        findsOneWidget,
      );
      expect(find.textContaining('Passwall is on'), findsOneWidget);
      expect(find.text("Couldn't check: SQM"), findsOneWidget);
      await t.tap(find.text('Check the modem'));
      expect(opened, 1);
    },
  );
}
