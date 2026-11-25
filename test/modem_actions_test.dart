// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_actions.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_pages.dart';

class _Fake implements ModemControls {
  _Fake({
    this.modes = true,
    this.restartable = true,
    this.reconnectable = false,
  });
  final bool modes;
  final bool restartable;
  final bool reconnectable;
  Completer<void>? hold;
  final set = <String>[];
  var restarts = 0;

  @override
  Future<bool> canRestart() async => restartable;
  @override
  Future<void> restart() async {
    restarts++;
    await hold?.future;
  }

  @override
  Future<bool> canReconnect() async => reconnectable;
  @override
  Future<void> reconnect() async => throw Exception('no');
  @override
  Future<bool> canPowerCycle() async => false;
  @override
  Future<void> powerCycle() async {}
  @override
  Future<(List<NetMode>, String)?> netModes() async => modes
      ? (const [NetMode('auto', 'Auto'), NetMode('lte', '4G only')], 'auto')
      : null;
  @override
  Future<void> setNetMode(String id) async => set.add(id);
  @override
  Future<bool?> speed(SpeedOption o) async => null;
  @override
  Future<void> setSpeed(SpeedOption o, bool on) async {}
  @override
  Future<SimSlots?> sims() async => null;
  @override
  Future<void> setSim(String id) async {}
  @override
  Future<(bool, String)?> apn() async => null;
  @override
  Future<void> setApn({required bool manual, String apn = ''}) async {}
  @override
  Future<bool?> roaming() async => null;
  @override
  Future<void> setRoaming(bool on) async {}
}

Future<void> _pump(
  WidgetTester t,
  ModemControls c,
  Future<bool> Function() o,
) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ModemActions(controls: c, online: o),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('switching mode asks first, then sets it', (t) async {
    final c = _Fake();
    await _pump(t, c, () async => true);
    expect(find.text('Network'), findsOneWidget);
    await t.tap(find.text('4G only'));
    await t.pumpAndSettle();
    expect(find.text('Switch to 4G only?'), findsOneWidget);
    expect(
      find.textContaining('The connection drops for a moment'),
      findsOneWidget,
    );
    await t.tap(find.text('Switch'));
    await t.pumpAndSettle();
    expect(c.set, ['lte']);
  });

  testWidgets('restart asks first', (t) async {
    final c = _Fake();
    await _pump(t, c, () async => true);
    await t.tap(find.text('Restart modem'));
    await t.pumpAndSettle();
    expect(c.restarts, 0);
    await t.tap(find.text('Restart'));
    await t.pumpAndSettle();
    expect(c.restarts, 1);
  });

  testWidgets('check and fix lists steps without duplicates', (t) async {
    final c = _Fake();
    await _pump(t, c, () async => true);
    await t.tap(find.text('Check and fix'));
    await t.pumpAndSettle();
    expect(find.text('Checking the connection'), findsOneWidget);
    expect(find.text('The connection is fine'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('offline: running line is replaced by its finished one', (
    t,
  ) async {
    final c = _Fake(restartable: false, reconnectable: true);
    await _pump(t, c, () async => false);
    await t.tap(find.text('Check and fix'));
    await t.pumpAndSettle();
    expect(find.text('Checking the connection'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(c.restarts, 0);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
  });

  testWidgets('renders nothing without modes or restart', (t) async {
    await _pump(t, _Fake(modes: false, restartable: false), () async => true);
    expect(find.text('Network'), findsNothing);
    expect(find.text('Restart modem'), findsNothing);
    expect(find.text('Connection'), findsNothing);
  });

  testWidgets('each part shows only its own control', (t) async {
    Future<void> only(ModemPart p) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          theme: KeystoneTheme.buildDarkTheme(),
          home: Scaffold(
            body: ModemActions(
              controls: _Fake(),
              online: () async => true,
              parts: {p},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('Network'),
        p == ModemPart.network ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Check and fix'),
        p == ModemPart.fix ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Restart modem'),
        p == ModemPart.restart ? findsOneWidget : findsNothing,
      );
    }

    for (final p in ModemPart.values) {
      await only(p);
    }
  });

  test('connected time reads plainly', () {
    expect(connectedFor('20'), 'just connected');
    expect(connectedFor('300'), 'connected 5 min');
    expect(connectedFor('4293'), 'connected 1 h 11 min');
    expect(connectedFor('180000'), 'connected 2 d 2 h');
    expect(connectedFor(null), isNull);
  });

  testWidgets('a modem page follows live data and skips empty rows', (t) async {
    final live = ValueNotifier('B3');
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Scaffold(
          body: ModemPageRow(
            title: 'Towers',
            subtitle: 'x',
            live: live,
            children: (_) => valueRows('Carriers', Icons.abc, [
              ('Primary', live.value),
              ('Cell ID', null),
            ]),
          ),
        ),
      ),
    );
    await t.tap(find.text('Towers'));
    await t.pumpAndSettle();
    expect(find.text('B3'), findsOneWidget);
    expect(find.text('Cell ID'), findsNothing);
    live.value = 'B1';
    await t.pump();
    expect(find.text('B1'), findsOneWidget);
  });

  testWidgets('check and fix hidden when the modem has no fix', (t) async {
    await _pump(t, _Fake(restartable: false), () async => true);
    expect(find.text('Network'), findsOneWidget);
    expect(find.text('Check and fix'), findsNothing);
  });

  testWidgets('a carriers row appearing keeps the restart busy', (t) async {
    final c = _Fake()..hold = Completer<void>();
    var carriers = true;
    late StateSetter flip;
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: StatefulBuilder(
          builder: (_, set) {
            flip = set;
            return KsPage(
              title: 'Mobile network',
              children: [
                if (carriers) const Text('Carriers'),
                ModemActions(
                  key: const ValueKey('modem-actions'),
                  controls: c,
                  online: () async => true,
                ),
              ],
            );
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Restart modem'));
    await t.pumpAndSettle();
    await t.tap(find.text('Restart'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    flip(() => carriers = false);
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await t.tap(find.text('Restart modem'));
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Restart the modem?'), findsNothing);
    c.hold!.complete();
    await t.pumpAndSettle();
    expect(c.restarts, 1);
  });

  test('dumpOnline needs an up interface with a default route', () {
    Map<String, dynamic> d(bool up, Map<String, dynamic> r) => {
      'interface': [
        {
          'up': up,
          'route': [r],
        },
      ],
    };
    expect(dumpOnline(d(true, {'target': '0.0.0.0', 'mask': 0})), isTrue);
    expect(dumpOnline(d(true, {'target': '::', 'mask': 0})), isTrue);
    expect(dumpOnline(d(false, {'target': '0.0.0.0', 'mask': 0})), isFalse);
    expect(dumpOnline(d(true, {'target': '10.0.0.0', 'mask': 8})), isFalse);
    expect(dumpOnline(const {}), isFalse);
  });
}
