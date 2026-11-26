// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/preferred_towers.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/fivegmodem_history.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_analysis.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_chart.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class _FakeApp extends Fake implements AppState {}

class _FakeTowers extends PreferredTowers {
  _FakeTowers() : super(_FakeApp());
  final calls = <String>[];

  @override
  Future<void> add(String earfcn, String pci) async =>
      calls.add('$earfcn/$pci');
}

final _now = DateTime(2026, 11, 25, 12);

List<HistoryPoint> _points({bool signal = true}) => [
  for (var i = 0; i < 60; i++)
    HistoryPoint(
      t: _now.subtract(Duration(minutes: 120 - i)),
      rsrp: signal ? (i >= 10 && i <= 25 ? -115 : -90) : null,
      sinr: signal ? 10 : null,
      ping: 40,
      pci: '151',
      earfcn: '1725',
      band: 'B3',
    ),
];

const _airtel = SimTraffic(
  sim: '1',
  label: 'airtel',
  month: '2026-11',
  down: 12345678901,
  up: 1200000000,
);

HistoryData _data({
  List<HistoryPoint>? points,
  List<SimTraffic> traffic = const [_airtel],
  DateTime? since,
  String? pingMethod,
}) => HistoryData(
  points: points ?? _points(),
  traffic: traffic,
  since: since,
  pingMethod: pingMethod,
);

Future<void> _pump(
  WidgetTester t,
  Future<HistoryData?> Function(DateTime, DateTime) load, {
  PreferredTowers? towers,
  Size size = const Size(390, 3000),
  double textScale = 1,
  bool dark = false,
  bool settle = true,
  int maxDays = 7,
  Future<List<(DateTime, DateTime)>> Function(DateTime, DateTime)? outages,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: dark
          ? KeystoneTheme.buildDarkTheme()
          : KeystoneTheme.buildLightTheme(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(
          ctx,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HistoryScreen(
        key: UniqueKey(),
        load: load,
        towers: towers,
        now: () => _now,
        maxDays: maxDays,
        outages: outages,
      ),
    ),
  );
  settle ? await t.pumpAndSettle() : await t.pump();
}

HistoryChart _chart(WidgetTester t, String key) =>
    t.widget<CustomPaint>(find.byKey(ValueKey(key))).painter! as HistoryChart;

void main() {
  testWidgets('outages are shaded on the ping chart', (t) async {
    final down = (
      _now.subtract(const Duration(hours: 3)),
      _now.subtract(const Duration(hours: 2)),
    );
    DateTime? askedFrom;
    await _pump(
      t,
      (_, _) async => _data(),
      outages: (f, _) async {
        askedFrom = f;
        return [down];
      },
    );
    expect(_chart(t, 'ping-chart').outages, [down]);
    expect(askedFrom, _now.subtract(const Duration(hours: 24)));
  });

  testWidgets('no alerts package, no shading, no fuss', (t) async {
    await _pump(t, (_, _) async => _data(), outages: (_, _) async => throw 'x');
    expect(_chart(t, 'ping-chart').outages, isEmpty);
    expect(find.byKey(const ValueKey('ping-chart')), findsOneWidget);
  });

  testWidgets('range picker defaults to 24 h and loads 7 d', (t) async {
    final calls = <(DateTime, DateTime)>[];
    await _pump(t, (f, to) async {
      calls.add((f, to));
      return _data();
    });
    final seg = t.widget<KsSegmented<Duration>>(
      find.byType(KsSegmented<Duration>),
    );
    expect(seg.options.map((o) => o.$2), ['6 h', '24 h', '7 d']);
    expect(seg.value, const Duration(hours: 24));
    expect(calls.single.$1, _now.subtract(const Duration(hours: 24)));
    await t.tap(find.text('7 d'));
    await t.pumpAndSettle();
    expect(calls.last.$1, _now.subtract(const Duration(days: 7)));
    expect(calls.last.$2, _now);
  });

  testWidgets('30 d only when the helper keeps 30 days', (t) async {
    final calls = <DateTime>[];
    await _pump(t, (f, _) async {
      calls.add(f);
      return _data();
    }, maxDays: 30);
    final seg = t.widget<KsSegmented<Duration>>(
      find.byType(KsSegmented<Duration>),
    );
    expect(seg.options.map((o) => o.$2), ['6 h', '24 h', '7 d', '30 d']);
    await t.tap(find.text('30 d'));
    await t.pumpAndSettle();
    expect(calls.last, _now.subtract(const Duration(days: 30)));
    await _pump(t, (_, _) async => _data(), maxDays: 14);
    expect(find.text('30 d'), findsNothing);
  });

  testWidgets('summary line for the sample data', (t) async {
    await _pump(t, (_, _) async => _data());
    expect(
      t.widget<Text>(find.byKey(const ValueKey('summary'))).data,
      'Up and down, mostly fair. Strength about \u221290 dBm, '
      'clearness about 10 dB. 1 slow period.',
    );
  });

  test('summary words', () {
    List<HistoryPoint> pts(double rsrp, double? sinr, {double swing = 0}) => [
      for (var i = 0; i < 20; i++)
        HistoryPoint(
          t: _now.add(Duration(minutes: i)),
          rsrp: rsrp + (i.isEven ? swing : -swing),
          sinr: sinr,
        ),
    ];
    final slow = [(_now, _now), (_now, _now)];
    expect(
      historySummary(pts(-94, 16), const []),
      'Steady and fair. Strength about \u221294 dBm, '
      'clearness about 16 dB. No slow periods.',
    );
    expect(
      historySummary(pts(-85, 20), const []),
      'Steady and good. Strength about \u221285 dBm, '
      'clearness about 20 dB. No slow periods.',
    );
    expect(
      historySummary(pts(-85, -2, swing: 6), slow),
      'Up and down, mostly poor. Strength about \u221285 dBm, '
      'clearness about \u22122 dB. 2 slow periods.',
    );
    expect(
      historySummary(pts(-110, null), const []),
      'Steady and poor. Strength about \u2212110 dBm. No slow periods.',
    );
    expect(
      historySummary([HistoryPoint(t: _now, sinr: 5)], const []),
      'Fair. Clearness about 5 dB. No slow periods.',
    );
    expect(historySummary([HistoryPoint(t: _now, ping: 5)], const []), isNull);
  });

  testWidgets('strength and clearness are separate one-colour charts', (
    t,
  ) async {
    await _pump(t, (_, _) async => _data());
    expect(find.text('Strength (RSRP)'), findsOneWidget);
    expect(find.text('Clearness (SINR)'), findsOneWidget);
    expect(find.text('dBm'), findsOneWidget);
    expect(find.text('dB'), findsOneWidget);
    final r = _chart(t, 'rsrp-chart'), s = _chart(t, 'sinr-chart');
    const ks = KeystoneColors.light;
    expect(r.line.color, ks.ac);
    expect(s.line.color, ks.ac);
    expect((r.line.lo, r.line.hi), (-125, -70));
    expect((s.line.lo, s.line.hi), (-5, 30));
    expect(r.line.value(_points()[0]), -90);
    expect(s.line.value(_points()[0]), 10);
    for (final c in [r, s]) {
      expect(c.bands.map((b) => b.label), ['good', 'fair', 'poor']);
      expect(c.bands.map((b) => b.color.withValues(alpha: 1)), [
        ks.ok,
        ks.warn,
        ks.bad,
      ]);
      expect(c.bands.every((b) => b.color.a < .2), isTrue);
      expect(c.ticks, isTrue);
      expect(c.slow, hasLength(1));
    }
    expect(r.bands.map((b) => (b.lo, b.hi)), [
      (-90, -70),
      (-105, -90),
      (-125, -105),
    ]);
    expect(s.bands.map((b) => (b.lo, b.hi)), [(13, 30), (0, 13), (-5, 0)]);
    expect(_chart(t, 'ping-chart').bands, isEmpty);
  });

  test('zone labels sit in a gutter right of the plot', () {
    final style = KeystoneType.caption(KeystoneColors.light.mu);
    HistoryChart c(List<HistoryBand> bands) => HistoryChart(
      points: const [],
      from: _now,
      to: _now,
      line: (
        value: (p) => p.rsrp,
        lo: -125,
        hi: -70,
        color: KeystoneColors.light.ac,
        width: 2,
      ),
      slowColor: KeystoneColors.light.warn,
      grid: KeystoneColors.light.line,
      labelStyle: style,
      bands: bands,
    );
    final banded = c([
      for (final l in ['good', 'fair', 'poor'])
        (lo: -125.0, hi: -70.0, color: KeystoneColors.light.ok, label: l),
    ]);
    final widest = [
      for (final l in ['good', 'fair', 'poor'])
        (TextPainter(
          text: TextSpan(text: l, style: style),
          textDirection: TextDirection.ltr,
        )..layout()).width,
    ].reduce((a, b) => a > b ? a : b);
    expect(banded.plotWidth(300) + widest, lessThan(300));
    expect(c(const []).plotWidth(300), 300);
  });

  testWidgets('ping heading follows the ping method', (t) async {
    await _pump(t, (_, _) async => _data(pingMethod: 'tcp'));
    expect(find.text('Connection time'), findsOneWidget);
    expect(find.text('Line ping'), findsNothing);
    for (final m in ['icmp', null]) {
      await _pump(t, (_, _) async => _data(pingMethod: m));
      expect(find.text('Line ping'), findsOneWidget);
      expect(find.text('Connection time'), findsNothing);
    }
  });

  testWidgets('chart draws points, ping label and one slow period', (t) async {
    await _pump(t, (_, _) async => _data());
    expect(find.text('Line ping'), findsOneWidget);
    final c = _chart(t, 'rsrp-chart');
    expect(c.points, isNotEmpty);
    expect(c.slow.length, 1);
    expect(_chart(t, 'sinr-chart').points, isNotEmpty);
    expect(_chart(t, 'ping-chart').points, isNotEmpty);
  });

  testWidgets('tapping the chart shows a readout', (t) async {
    await _pump(t, (_, _) async => _data());
    await t.tap(find.byKey(const ValueKey('sinr-chart')));
    await t.pump();
    expect(find.textContaining('RSRP −90 dBm'), findsOneWidget);
    expect(find.textContaining('SINR 10.0 dB'), findsOneWidget);
    expect(find.textContaining('PCI 151'), findsWidgets);
  });

  testWidgets('notes when readings start inside the range', (t) async {
    await _pump(
      t,
      (_, _) async => _data(since: _now.subtract(const Duration(hours: 3))),
    );
    expect(find.textContaining('No readings before'), findsOne);
  });

  testWidgets('no note when readings cover the range', (t) async {
    await _pump(t, (_, _) async => _data());
    expect(find.textContaining('No readings before'), findsNothing);
    await _pump(
      t,
      (_, _) async => _data(since: _now.subtract(const Duration(days: 2))),
    );
    expect(find.textContaining('No readings before'), findsNothing);
  });

  testWidgets('towers list and add best tower', (t) async {
    final towers = _FakeTowers();
    await _pump(t, (_, _) async => _data(), towers: towers);
    expect(find.text('Towers'), findsOneWidget);
    expect(find.text('PCI 151 · EARFCN 1725'), findsOneWidget);
    expect(find.textContaining('59 min'), findsOneWidget);
    await t.tap(find.text('Add to Preferred towers'));
    await t.pumpAndSettle();
    expect(towers.calls, ['1725/151']);
  });

  testWidgets('no add button without towers', (t) async {
    await _pump(t, (_, _) async => _data());
    expect(find.text('PCI 151 · EARFCN 1725'), findsOneWidget);
    expect(find.text('Add to Preferred towers'), findsNothing);
  });

  testWidgets('data this month in GB with tabular figures', (t) async {
    await _pump(t, (_, _) async => _data());
    expect(find.text('Data this month'), findsOneWidget);
    expect(find.text('airtel'), findsOneWidget);
    final f = find.textContaining('12.35 GB');
    expect(f, findsOneWidget);
    final text = t.widget<Text>(f);
    expect(text.data, contains('1.20 GB'));
    expect(
      text.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('helper traffic shows as the router mobile line', (t) async {
    await _pump(
      t,
      (_, _) async => _data(
        traffic: const [
          SimTraffic(
            sim: 'helper',
            label: 'Router',
            month: '2026-11',
            down: 1,
            up: 1,
          ),
        ],
      ),
    );
    expect(find.text("Router's mobile line"), findsOneWidget);
  });

  testWidgets('null load shows no history message', (t) async {
    await _pump(t, (_, _) async => null);
    expect(find.text('No history on this router yet.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  test('points 3 h apart do not connect', () {
    final runs = historyRuns([
      HistoryPoint(t: _now, rsrp: -90),
      HistoryPoint(t: _now.add(const Duration(minutes: 1)), rsrp: -91),
      HistoryPoint(t: _now.add(const Duration(hours: 3)), rsrp: -92),
    ], (p) => p.rsrp);
    expect(runs.map((r) => r.length), [2, 1]);
  });

  test('null values do not break a run', () {
    final runs = historyRuns([
      HistoryPoint(t: _now, rsrp: -90),
      HistoryPoint(t: _now.add(const Duration(minutes: 1))),
      HistoryPoint(t: _now.add(const Duration(minutes: 2)), rsrp: -92),
    ], (p) => p.rsrp);
    expect(runs.map((r) => r.length), [2]);
  });

  testWidgets('load error with nothing shown: centred message and retry', (
    t,
  ) async {
    var n = 0;
    await _pump(t, (_, _) async {
      if (n++ == 0) throw StateError('offline');
      return _data();
    });
    expect(find.textContaining("Couldn't reach the router"), findsOneWidget);
    expect(find.text('No history on this router yet.'), findsNothing);
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Line ping'), findsOneWidget);
    expect(find.textContaining("Couldn't reach the router"), findsNothing);
  });

  testWidgets('load error keeps data already shown', (t) async {
    var n = 0;
    await _pump(t, (_, _) async {
      if (n++ > 0) throw StateError('session expired');
      return _data();
    });
    await t.tap(find.text('6 h'));
    await t.pumpAndSettle();
    expect(
      find.text("Couldn't load the last 6 h. Still showing the last 24 h."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('airtel'), findsOneWidget);
    expect(find.text('Line ping'), findsOneWidget);
  });

  testWidgets('a slower earlier range does not overwrite a newer one', (
    t,
  ) async {
    final pending = <Duration, Completer<HistoryData?>>{};
    await _pump(t, (f, to) {
      final c = Completer<HistoryData?>();
      pending[to.difference(f)] = c;
      return c.future;
    }, settle: false);
    pending[const Duration(hours: 24)]!.complete(_data());
    await t.pumpAndSettle();
    await t.tap(find.text('6 h'));
    await t.pump();
    await t.tap(find.text('7 d'));
    await t.pump();
    SimTraffic sim(String l) =>
        SimTraffic(sim: l, label: l, month: '2026-11', down: 1, up: 1);
    pending[const Duration(days: 7)]!.complete(
      _data(traffic: [sim('seven days')]),
    );
    await t.pumpAndSettle();
    pending[const Duration(hours: 6)]!.complete(
      _data(traffic: [sim('six hours')]),
    );
    await t.pumpAndSettle();
    expect(find.text('seven days'), findsOneWidget);
    expect(find.text('six hours'), findsNothing);
  });

  testWidgets('no points: no crash, sections hidden', (t) async {
    await _pump(t, (_, _) async => _data(points: const [], traffic: const []));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('rsrp-chart')), findsNothing);
    expect(find.byKey(const ValueKey('sinr-chart')), findsNothing);
    expect(find.byKey(const ValueKey('ping-chart')), findsNothing);
    expect(find.byKey(const ValueKey('summary')), findsNothing);
    expect(find.text('Towers'), findsNothing);
    expect(find.text('Data this month'), findsNothing);
    expect(find.text('Nothing recorded in this time.'), findsOneWidget);
  });

  testWidgets('one point draws as a dot', (t) async {
    await _pump(
      t,
      (_, _) async => _data(
        points: [HistoryPoint(t: _now, rsrp: -90, sinr: 5, ping: 30)],
        traffic: const [],
      ),
    );
    expect(t.takeException(), isNull);
    final c = _chart(t, 'rsrp-chart');
    expect(historyRuns(c.points, (p) => p.rsrp).single.length, 1);
    expect(find.text('Towers'), findsNothing);
    final r = PictureRecorder();
    c.paint(Canvas(r), const Size(300, 140));
    r.endRecording();
  });

  testWidgets('ping only: signal chart hidden, ping chart shown', (t) async {
    await _pump(t, (_, _) async => _data(points: _points(signal: false)));
    expect(find.byKey(const ValueKey('rsrp-chart')), findsNothing);
    expect(find.byKey(const ValueKey('sinr-chart')), findsNothing);
    expect(find.byKey(const ValueKey('summary')), findsNothing);
    expect(find.byKey(const ValueKey('ping-chart')), findsOneWidget);
  });

  testWidgets('2x text in dark mode at 390x844 has no overflow', (t) async {
    await _pump(
      t,
      (_, _) async => _data(since: _now.subtract(const Duration(hours: 3))),
      towers: _FakeTowers(),
      size: const Size(390, 844),
      textScale: 2,
      dark: true,
    );
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('summary')), findsOneWidget);
    for (final k in ['rsrp-chart', 'sinr-chart']) {
      await t.ensureVisible(find.byKey(ValueKey(k)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(ValueKey(k)));
      await t.pump();
      expect(t.takeException(), isNull);
    }
    for (var i = 0; i < 8; i++) {
      await t.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }
    expect(find.text('airtel'), findsOneWidget);
  });

  testWidgets('2x text error state has no overflow', (t) async {
    await _pump(
      t,
      (_, _) async => throw StateError('offline'),
      size: const Size(390, 844),
      textScale: 2,
      dark: true,
    );
    expect(t.takeException(), isNull);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the current range', (t) async {
    final calls = <Duration>[];
    await _pump(t, (f, to) async {
      calls.add(to.difference(f));
      return _data();
    }, size: const Size(390, 844));
    await t.tap(find.text('6 h'));
    await t.pumpAndSettle();
    await t.fling(find.byType(Scrollable).first, const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(calls, [
      const Duration(hours: 24),
      const Duration(hours: 6),
      const Duration(hours: 6),
    ]);
  });

  test('thinned 7 d data stays connected, a real outage breaks it', () {
    final start = _now.subtract(const Duration(days: 7));
    final pts = <HistoryPoint>[];
    for (var i = 0; i < 5040; i++) {
      final t = start.add(Duration(seconds: 120 * i));
      if (i >= 2000 && i < 2090) continue;
      pts.add(HistoryPoint(t: t, rsrp: -90.0 - i % 7));
    }
    final runs = historyRuns(thin(pts, 400), (p) => p.rsrp);
    expect(runs, hasLength(2));
    expect(runs.every((r) => r.length > 50), isTrue);
  });

  testWidgets('data this month shows only the current month', (t) async {
    await _pump(
      t,
      (_, _) async => _data(
        traffic: const [
          SimTraffic(
            sim: '1',
            label: 'october',
            month: '2026-10',
            down: 1,
            up: 1,
          ),
          _airtel,
        ],
      ),
    );
    expect(find.text('airtel'), findsOneWidget);
    expect(find.text('october'), findsNothing);
    await _pump(
      t,
      (_, _) async => _data(
        traffic: const [
          SimTraffic(sim: '1', label: 'old', month: '2026-10', down: 1, up: 1),
        ],
      ),
    );
    expect(find.text('Data this month'), findsNothing);
  });

  testWidgets('tapping does not move the charts', (t) async {
    await _pump(t, (_, _) async => _data(), textScale: 2);
    final signal = t.getTopLeft(find.byKey(const ValueKey('rsrp-chart')));
    final ping = t.getTopLeft(find.byKey(const ValueKey('ping-chart')));
    await t.tap(find.byKey(const ValueKey('ping-chart')));
    await t.pump();
    expect(find.textContaining('ping 40 ms'), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const ValueKey('rsrp-chart'))), signal);
    expect(t.getTopLeft(find.byKey(const ValueKey('ping-chart'))), ping);
    expect(t.takeException(), isNull);
  });

  testWidgets('charts have semantic summaries', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, (_, _) async => _data());
    expect(
      find.bySemanticsLabel(
        'Strength, last 24 h: \u2212115 to \u221290 dBm, 1 slow period',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Clearness, last 24 h: 10 to 10 dB, 1 slow period'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Line ping, last 24 h: 40 to 40 ms, 1 slow period'),
      findsOneWidget,
    );
    h.dispose();
  });

  testWidgets('real AW1000 series draw lines and zero ping hides', (t) async {
    final points = parseFiveG(
      series: {'rsrp': _realRsrp, 'sinr': _realSinr, 'ping': _realPing},
      towerLog: '',
      uptimeNow: 3200,
      now: _now,
    );
    await _pump(t, (_, _) async => _data(points: points));
    for (final (k, v) in <(String, double? Function(HistoryPoint))>[
      ('rsrp-chart', (p) => p.rsrp),
      ('sinr-chart', (p) => p.sinr),
    ]) {
      final runs = historyRuns(_chart(t, k).points, v);
      expect(runs, hasLength(1));
      expect(runs.single, hasLength(30));
    }
    expect(find.byKey(const ValueKey('ping-chart')), findsNothing);
    expect(find.text('Line ping'), findsNothing);
  });
}

const _realRsrp = <(int, double)>[
  (71, -93.0),
  (119, -93.0),
  (258, -94.0),
  (338, -94.0),
  (386, -94.0),
  (528, -92.0),
  (673, -90.0),
  (815, -94.0),
  (958, -93.0),
  (1003, -93.0),
  (1098, -93.0),
  (1241, -92.0),
  (1286, -92.0),
  (1381, -92.0),
  (1524, -91.0),
  (1569, -91.0),
  (1664, -92.0),
  (1809, -93.0),
  (1854, -93.0),
  (1951, -90.0),
  (2097, -93.0),
  (2142, -93.0),
  (2238, -92.0),
  (2385, -92.0),
  (2430, -92.0),
  (2531, -92.0),
  (2676, -93.0),
  (2822, -92.0),
  (2966, -92.0),
  (3108, -90.0),
];
const _realSinr = <(int, double)>[
  (71, 16.0),
  (119, 16.0),
  (259, 16.0),
  (338, 16.0),
  (386, 16.0),
  (528, 16.0),
  (673, 16.0),
  (815, 15.0),
  (958, 16.0),
  (1003, 16.0),
  (1098, 17.0),
  (1241, 17.0),
  (1286, 17.0),
  (1381, 18.0),
  (1524, 15.0),
  (1569, 15.0),
  (1664, 16.0),
  (1809, 17.0),
  (1854, 17.0),
  (1951, 17.0),
  (2097, 15.0),
  (2142, 15.0),
  (2238, 17.0),
  (2385, 17.0),
  (2430, 17.0),
  (2531, 15.0),
  (2676, 17.0),
  (2822, 15.0),
  (2966, 17.0),
  (3108, 16.0),
];
const _realPing = <(int, double)>[
  (71, 0.0),
  (119, 0.0),
  (164, 0.0),
  (211, 0.0),
  (258, 0.0),
  (306, 0.0),
  (338, 0.0),
  (385, 0.0),
  (431, 0.0),
  (479, 0.0),
  (528, 0.0),
  (576, 0.0),
  (622, 0.0),
  (673, 0.0),
  (719, 0.0),
  (767, 0.0),
  (815, 0.0),
  (862, 0.0),
  (908, 0.0),
  (958, 0.0),
  (1003, 0.0),
  (1051, 0.0),
  (1098, 0.0),
  (1145, 0.0),
  (1190, 0.0),
  (1240, 0.0),
  (1286, 0.0),
  (1333, 0.0),
  (1381, 0.0),
  (1428, 0.0),
];
