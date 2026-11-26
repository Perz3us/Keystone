import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_sheet.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/screens/home/home_data.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';

SimPlan plan(
  PlanKind kind, {
  int? gb,
  double usedGb = 18,
  int day = 15,
  String start = '2026-11-15',
  String end = '2026-12-14',
  String? since,
}) => SimPlan(
  sim: 'main',
  kind: kind,
  allowanceGb: gb,
  billingDay: day,
  periodStart: DateTime.parse('${start}T00:00:00Z'),
  periodEnd: DateTime.parse('${end}T00:00:00Z'),
  down: (usedGb * 1e9).round(),
  up: 0,
  since: since == null ? null : DateTime.parse('${since}T00:00:00Z'),
);

SimPlan inNovember(PlanKind kind) =>
    plan(kind, day: 1, start: '2026-11-01', end: '2026-11-30');

void main() {
  final now = DateTime(2026, 11, 20);
  List<String> lines(SimPlan p) => dataLines(p, now);

  group('words', () {
    test('unlimited', () {
      expect(lines(plan(PlanKind.unlimited)), ['18.0 GB since 15 Nov']);
    });
    test('unlimited on the calendar month', () {
      expect(lines(inNovember(PlanKind.unlimited)), ['18.0 GB this month']);
    });
    test('counting that began this month says since when', () {
      final p = plan(
        PlanKind.none,
        day: 1,
        start: '2026-11-01',
        end: '2026-11-30',
        since: '2026-11-18',
      );
      expect(lines(p), ['18.0 GB since 18 Nov']);
    });
    test('a cap counted for part of the period says so', () {
      expect(
        lines(plan(PlanKind.capped, gb: 100, usedGb: 15, since: '2026-11-18')),
        [
          '15% used · 25 days left',
          'At this rate it runs out on 7 Dec',
          'Counted since 18 Nov',
        ],
      );
    });
    test('capped', () {
      expect(lines(plan(PlanKind.capped, gb: 100, usedGb: 15)), [
        '15% used · 25 days left',
      ]);
    });
    test('one day left', () {
      expect(
        dataLines(
          plan(PlanKind.capped, gb: 100, usedGb: 62),
          DateTime(2026, 12, 14),
        ),
        ['62% used · 1 day left'],
      );
    });
    test('running out early', () {
      expect(lines(plan(PlanKind.capped, gb: 100, usedGb: 30)), [
        '30% used · 25 days left',
        'At this rate it runs out on 4 Dec',
      ]);
    });
    test('used up', () {
      expect(lines(plan(PlanKind.capped, gb: 10, usedGb: 10.2)), [
        'Data used up · resets 15 Dec',
      ]);
    });
    test('99.6% is not shown as 100%', () {
      expect(
        lines(plan(PlanKind.capped, gb: 100, usedGb: 99.6)).first,
        startsWith('99%'),
      );
    });
    test('fair use', () {
      expect(lines(plan(PlanKind.fairuse, gb: 100, usedGb: 38)), [
        '38.0 of 100 GB before it slows down',
      ]);
    });
    test('fair use passed', () {
      expect(lines(plan(PlanKind.fairuse, gb: 100, usedGb: 104)), [
        'Past the 100 GB fair-use limit · resets 15 Dec',
      ]);
    });
    test('not set up', () {
      expect(lines(inNovember(PlanKind.none)), ['18.0 GB this month']);
    });
  });

  Widget host(Widget w, {bool dark = false, double scale = 1}) => MaterialApp(
    theme: ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      extensions: [dark ? KeystoneColors.dark : KeystoneColors.light],
    ),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(body: SingleChildScrollView(child: w)),
  );

  testWidgets('not set up offers to set the plan', (t) async {
    var taps = 0;
    await t.pumpWidget(
      host(
        HomeDataLine(plan: plan(PlanKind.none), now: now, onTap: () => taps++),
      ),
    );
    await t.tap(find.text('Set your plan'));
    expect(taps, 1);
  });

  testWidgets('a set plan opens for editing', (t) async {
    var taps = 0;
    await t.pumpWidget(
      host(
        HomeDataLine(
          plan: plan(PlanKind.capped, gb: 100),
          now: now,
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.text('Set your plan'), findsNothing);
    await t.tap(find.textContaining('% used'));
    expect(taps, 1);
  });

  testWidgets('used up is in the danger colour, dark too', (t) async {
    for (final dark in [false, true]) {
      await t.pumpWidget(
        host(
          HomeDataLine(
            plan: plan(PlanKind.capped, gb: 10),
            now: now,
            onTap: () {},
          ),
          dark: dark,
        ),
      );
      await t.pumpAndSettle();
      final text = t.widget<Text>(find.textContaining('used up'));
      final want = dark ? KeystoneColors.dark.bad : KeystoneColors.light.bad;
      expect(text.style!.color, want);
    }
  });

  testWidgets('fits a small phone with large text', (t) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      host(
        HomeDataLine(
          plan: plan(PlanKind.capped, gb: 100, usedGb: 30),
          now: now,
          onTap: () {},
        ),
        scale: 2,
      ),
    );
    expect(t.takeException(), isNull);
  });

  group('widget from Home', () {
    HomeStatus status(LinkState s) => HomeStatus(
      headline: '',
      detail: '',
      internet: s,
      internetLine: '',
      devices: 0,
    );
    test('online with signal and plan', () {
      final w = homeSnapshot(
        'AW1000',
        status(LinkState.weak),
        bars: 1,
        plan: plan(PlanKind.capped, gb: 100, usedGb: 15),
        now: now,
      )!;
      expect(w.online, isTrue);
      expect(w.bars, 1);
      expect(w.dataLine, '15% used · 25 days left');
      expect(w.data!.percent, 15);
      expect(w.at, now);
    });
    test('signal line from what Home read', () {
      final w = homeSnapshot(
        'r',
        status(LinkState.ok),
        signal: const SignalOverview(
          rsrp: '-93',
          sinr: '15.4',
          carriers: [
            SignalCarrier(band: 'B3 (1800 MHz) @20 MHz'),
            SignalCarrier(band: 'B1 (2100 MHz) @15 MHz'),
            SignalCarrier(band: 'B7 (2600 MHz) @20 MHz', resting: true),
          ],
        ),
        now: now,
      )!;
      expect(w.signal, 'B3 + B1 · −93 dBm · SINR 15');
    });
    test('down', () {
      expect(
        homeSnapshot('r', status(LinkState.down), now: now)!.online,
        isFalse,
      );
    });
    test('not known yet is not saved', () {
      expect(homeSnapshot('r', status(LinkState.unknown), now: now), isNull);
    });
  });

  group('plan form', () {
    Map<String, dynamic>? sent;
    Map<String, dynamic> Function()? reply;
    setUp(() {
      sent = null;
      reply = null;
    });
    Future<void> open(WidgetTester t, {SimPlan? p}) => t.pumpWidget(
      host(
        DataPlanForm(
          client: DataPlanClient((m, params) async {
            sent = params;
            return reply?.call() ??
                {
                  ...params,
                  'period_start': '2026-11-15',
                  'period_end': '2026-12-14',
                  'down': 1,
                  'up': 1,
                };
          }),
          sim: 'main',
          plan: p,
        ),
      ),
    );
    Future<void> pick(WidgetTester t, String kind) async {
      await t.tap(find.text(kind));
      await t.pump();
    }

    testWidgets('unlimited has no GB field', (t) async {
      await open(t);
      await pick(t, 'Capped');
      expect(find.byType(TextFormField), findsOneWidget);
      await pick(t, 'Unlimited');
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('asks for an allowance', (t) async {
      await open(t);
      await pick(t, 'Capped');
      await t.tap(find.text('Save'));
      await t.pump();
      expect(find.text('Enter your allowance'), findsOneWidget);
      expect(sent, isNull);
    });

    for (final bad in ['0', '-5', '100001', 'abc', '1.5']) {
      testWidgets('refuses $bad GB', (t) async {
        await open(t);
        await pick(t, 'Capped');
        await t.enterText(find.byType(TextFormField), bad);
        await t.tap(find.text('Save'));
        await t.pump();
        expect(find.text('Whole GB, 1 to 100000'), findsOneWidget);
        expect(sent, isNull);
      });
    }

    testWidgets('saves', (t) async {
      await open(t, p: plan(PlanKind.capped, gb: 50, day: 31));
      expect(find.textContaining('Shorter months'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), '80');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(sent, {
        'sim': 'main',
        'plan': 'capped',
        'allowance_gb': 80,
        'billing_day': 31,
      });
    });

    testWidgets('shows why the router refused and stays open', (t) async {
      reply = () => throw const NoobRpcError('could not save the plan');
      await open(t, p: plan(PlanKind.unlimited));
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.textContaining('could not save the plan'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a set plan can be removed', (t) async {
      await open(t, p: plan(PlanKind.capped, gb: 50));
      await t.tap(find.text('Remove plan'));
      await t.pumpAndSettle();
      expect(sent!['plan'], 'none');
    });

    testWidgets('nothing to remove when not set', (t) async {
      await open(t);
      expect(find.text('Remove plan'), findsNothing);
    });
  });
}
