import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cellular_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/screens/home/home_signal.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/home/home_view.dart';

SignalOverview _m(Map<String, dynamic> extra) => SignalOverview.fromMetrics(
  ModemMetrics({
    'operator_name': 'airtel',
    'mode': 'LTE',
    'signal': '60',
    'rsrp': '-94',
    'sinr': '15',
    'rsrq': '-13',
    'pband': 'B3 (1800 MHz) @20 MHz',
    'pci': '151',
    'earfcn': '1725',
    ...extra,
  }),
);

final _one = _m({});
final _ca = _m({
  's1band': 'B1 (2100 MHz) @10 MHz',
  's1pci': '7',
  's2band': 'B1 (2100 MHz) @5 MHz',
  's2pci': '8',
});
final _nsa = _m({
  'mode': '5G NSA',
  's1band': 'n78 (3500 MHz) @60 MHz',
  's1pci': '9',
});

final _t0 = DateTime(2026, 1, 1, 12);
DateTime _at(int seconds) => _t0.add(Duration(seconds: seconds));

Future<void> _pump(
  WidgetTester t,
  SignalOverview? signal, {
  HomePrefs prefs = const HomePrefs(flow: false),
  double scale = 1,
  double width = 360,
  bool dark = false,
  VoidCallback? onSignal,
}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: dark
          ? KeystoneTheme.buildDarkTheme()
          : KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: HomeView(
          prefs: prefs,
          routerName: 'AW1000',
          model: 'Arcadyan AW1000',
          status: const HomeStatus(
            headline: "Everything's working.",
            detail: 'Online.',
            internet: LinkState.ok,
            internetLine: 'Signal 60%',
            devices: 2,
          ),
          lights: RouterLights.unlit,
          shortcuts: const [],
          downMbps: 0,
          upMbps: 0,
          downHistory: const [],
          upHistory: const [],
          signal: signal,
          onSignal: onSignal,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('5G Modem readings become types, bands and rows', () {
    expect(_one.type, '4G');
    expect(_one.summary, 'LTE, 1 carrier');
    expect(_one.rows, [('Main', 'B3 · 1800 MHz · 20 MHz wide')]);
    expect(_ca.type, '4G+');
    expect(_ca.bands, 'B3 + B1 + B1');
    expect(_ca.totalWidth, '35 MHz');
    expect(_ca.rows[1], ('Added', 'B1 + B1 · 15 MHz wide'));
    expect(_nsa.type, '5G NSA');
    expect(_nsa.rows.last, ('5G', 'n78 · 3500 MHz · 60 MHz wide'));
    final sa = _m({'mode': '5G SA', 'pband': 'n78 (3500 MHz) @100 MHz'});
    expect(sa.type, '5G SA');
    expect(_m({'mode': 'HSPA+', 'pband': 'B1'}).type, '3G');
    expect(_m({'pband': 'B3'}).totalWidth, isNull);
  });

  test('bars follow RSRP, then the percentage', () {
    int? bars(String? rsrp) => SignalOverview(rsrp: rsrp, percent: 60).bars;
    expect(
      [bars('-82'), bars('-94'), bars('-104'), bars('-113')],
      [4, 3, 2, 1],
    );
    expect(bars('-120'), 0);
    expect(bars(null), 3);
    expect(const SignalOverview().bars, isNull);
  });

  test('QModem readings work without a percentage or frequency', () {
    final s = SignalOverview.fromQmodem(
      const [
        CellEntry('LTE', 'LTE'),
        CellEntry('RSRP', '-96', unit: 'dBm'),
        CellEntry('SINR', '12'),
        CellEntry('NR5G-NSA', 'NR5G-NSA'),
        CellEntry('RSRP', '-80'),
      ],
      'EN-DC',
      const [
        Carrier(role: 'pcc', rat: 'LTE', band: 'LTE B3', width: '20'),
        Carrier(role: 'nsa', rat: 'NR', band: 'NR n78', width: '100'),
      ],
    );
    expect(s.rsrp, '-96');
    expect(s.type, '5G NSA');
    expect(s.rows, [
      ('Main', 'B3 · 20 MHz wide'),
      ('5G', 'n78 · 100 MHz wide'),
    ]);
    expect(signalLine(s), '−96 dBm');
  });

  group('idle', () {
    test('lost carriers rest while the line is quiet', () {
      final mem = SignalMemory();
      mem.next(_ca, at: _at(0), mbps: 20);
      final s = mem.next(_one, at: _at(60), mbps: .1)!;
      expect(s.idle, isTrue);
      expect(s.type, '4G+');
      expect(s.summary, 'Idle. 3 carriers when last busy');
      expect(s.bands, 'B3, idle');
      expect(s.totalWidth, '20 MHz');
      expect(s.rows[1].$2, endsWith('idle'));
    });

    test('an idle 5G leg keeps the 5G NSA name', () {
      final mem = SignalMemory()..next(_nsa, at: _at(0), mbps: 20);
      expect(mem.next(_one, at: _at(10), mbps: 0)!.type, '5G NSA');
    });

    test('they go when traffic is high, the cell changes or time runs out', () {
      SignalOverview after(SignalOverview now, int sec, double mbps) {
        final mem = SignalMemory()..next(_ca, at: _at(0), mbps: 20);
        return mem.next(now, at: _at(sec), mbps: mbps)!;
      }

      expect(after(_one, 30, 15).idle, isFalse);
      expect(after(_m({'pci': '99'}), 30, 0).idle, isFalse);
      expect(after(_one, 601, 0).idle, isFalse);
    });

    test('the setting turns it off', () {
      final mem = SignalMemory()..next(_ca, at: _at(0), mbps: 20);
      final s = mem.next(_one, at: _at(5), mbps: 0, keepCarriers: false)!;
      expect(s.idle, isFalse);
    });

    test('missing readings hold for a minute, then go', () {
      final mem = SignalMemory()..next(_one, at: _at(0), mbps: 0);
      final gone = _m({'sinr': '-'});
      expect(mem.next(gone, at: _at(30), mbps: 0)!.sinr, '15');
      expect(mem.next(null, at: _at(40), mbps: 0)!.rsrp, '-94');
      expect(mem.next(gone, at: _at(70), mbps: 0)!.sinr, isNull);
      expect(mem.next(null, at: _at(200), mbps: 0), isNull);
    });

    test('old readings never move to another cell', () {
      final mem = SignalMemory()..next(_one, at: _at(0), mbps: 0);
      final s = mem.next(_m({'pci': '99', 'sinr': '-'}), at: _at(5), mbps: 0)!;
      expect(s.sinr, isNull);
    });
  });

  test('prefs survive a save and cap the readings at four', () {
    const p = HomePrefs(signal: true, beside: false, besideItems: []);
    final back = HomePrefs.fromJson(p.toJson());
    expect(back.signal, isTrue);
    expect(back.beside, isFalse);
    expect(back.besideItems, isEmpty);
    final many = HomePrefs.fromJson({
      'besideItems': [for (final i in SignalItem.values) i.name, 'bogus'],
    });
    expect(many.besideItems.length, maxSignalItems);
    expect(HomePrefs.fromJson(const {}).signal, isFalse);
  });

  testWidgets('readings sit beside the router and open the modem', (t) async {
    var taps = 0;
    await _pump(t, _ca, onSignal: () => taps++);
    expect(find.byType(SignalBars), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('B3 + B1 + B1'), findsOneWidget);
    expect(find.byType(SignalDetails), findsNothing);
    final box = t.getRect(find.byType(SignalReadings));
    expect(box.left, greaterThan(180 + 40));
    expect(box.right, lessThanOrEqualTo(360));
    await t.tap(find.text('4G+'));
    expect(taps, 1);
  });

  testWidgets('short readings sit midway between router and edge', (t) async {
    await _pump(
      t,
      _ca,
      prefs: const HomePrefs(flow: false, besideItems: [SignalItem.type]),
    );
    final readings = t.getRect(find.text('4G+'));
    expect(readings.left, greaterThan(180 + 40 + 24));
  });

  testWidgets('without readings Home looks as before', (t) async {
    await _pump(t, null, prefs: const HomePrefs(flow: false, signal: true));
    expect(find.text('Signal 60%'), findsOneWidget);
    expect(find.byType(SignalBars), findsNothing);
    expect(find.byType(SignalReadings), findsNothing);
    expect(find.byType(SignalDetails), findsNothing);
  });

  testWidgets('each part can be turned off', (t) async {
    await _pump(
      t,
      _nsa,
      prefs: const HomePrefs(
        flow: false,
        signalBars: false,
        beside: false,
        signal: true,
        signalNumbers: false,
      ),
    );
    expect(find.byType(SignalBars), findsNothing);
    expect(find.byType(SignalReadings), findsNothing);
    expect(find.text('4G main carrier with 5G added'), findsOneWidget);
    expect(find.text('RSRP'), findsNothing);
    expect(find.text('n78'), findsOneWidget);
    expect(find.text('Main'), findsNothing);
  });

  for (final (name, width, scale, layout) in [
    ('small phone', 320.0, 1.0, HomeLayout.side),
    ('top to bottom', 360.0, 1.0, HomeLayout.topDown),
    ('large text', 360.0, 2.0, HomeLayout.side),
  ]) {
    testWidgets('nothing overflows: $name', (t) async {
      final mem = SignalMemory()..next(_ca, at: _at(0), mbps: 20);
      await _pump(
        t,
        mem.next(_one, at: _at(5), mbps: 0),
        width: width,
        scale: scale,
        dark: true,
        prefs: HomePrefs(
          flow: false,
          layout: layout,
          signal: true,
          signalList: true,
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.byType(SignalReadings), findsOneWidget);
      if (scale > 1.3) {
        expect(
          t.getTopLeft(find.byType(SignalReadings)).dy,
          greaterThan(t.getBottomLeft(find.byType(HomeFlow)).dy),
        );
      }
    });
  }
}
