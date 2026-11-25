// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_settings.dart';

class _Fake implements ModemControls {
  _Fake({
    this.ca = false,
    this.hasSims = false,
    this.hasApn = false,
    this.hasRoam = false,
  });
  final bool? ca;
  final bool hasSims;
  final bool hasApn;
  final bool hasRoam;
  final calls = <String>[];
  var manual = false;
  var typed = '';
  var roam = false;
  var fail = false;

  @override
  Future<bool> canRestart() async => false;
  @override
  Future<void> restart() async {}
  @override
  Future<bool> canReconnect() async => false;
  @override
  Future<void> reconnect() async {}
  @override
  Future<bool> canPowerCycle() async => false;
  @override
  Future<void> powerCycle() async {}
  @override
  Future<(List<NetMode>, String)?> netModes() async => null;
  @override
  Future<void> setNetMode(String id) async {}
  @override
  Future<bool?> speed(SpeedOption o) async =>
      o == SpeedOption.ca && ca != false ? true : null;
  @override
  Future<void> setSpeed(SpeedOption o, bool on) async =>
      fail ? throw StateError('boom') : calls.add('speed ${o.name} $on');
  @override
  Future<SimSlots?> sims() async => hasSims
      ? const SimSlots([('1', 'SIM1', true), ('2', 'SIM2', true)], '1')
      : null;
  @override
  Future<void> setSim(String id) async => calls.add('sim $id');
  @override
  Future<(bool, String)?> apn() async => hasApn ? (manual, typed) : null;
  @override
  Future<void> setApn({required bool manual, String apn = ''}) async {
    this.manual = manual;
    typed = apn;
    calls.add('apn $manual $apn');
  }

  @override
  Future<bool?> roaming() async => hasRoam ? roam : null;
  @override
  Future<void> setRoaming(bool on) async {
    roam = on;
    calls.add('roam $on');
  }
}

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: w)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('speed options confirm, then set', (t) async {
    final c = _Fake(ca: true);
    await _pump(t, SpeedOptions(controls: c));
    expect(find.text('Carrier aggregation'), findsOneWidget);
    await t.tap(find.text('Carrier aggregation'));
    await t.pumpAndSettle();
    expect(find.text('Turn Carrier aggregation off?'), findsOneWidget);
    expect(find.textContaining('The modem restarts its radio'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(c.calls, ['speed ca false']);
  });

  testWidgets('speed options say when nothing is supported', (t) async {
    await _pump(t, SpeedOptions(controls: _Fake(ca: false)));
    expect(find.textContaining('no speed options'), findsOneWidget);
  });

  testWidgets('sim settings show rows and switch sim after asking', (t) async {
    final c = _Fake(hasSims: true, hasApn: true, hasRoam: true);
    await _pump(t, SimSettings(controls: c));
    expect(find.text('SIM card'), findsOneWidget);
    expect(find.text('SIM1'), findsOneWidget);
    expect(find.text('Data roaming'), findsOneWidget);
    expect(find.text('APN'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    await t.tap(find.text('SIM2'));
    await t.pumpAndSettle();
    expect(find.text('Switch to SIM2?'), findsOneWidget);
    await t.tap(find.text('Switch'));
    await t.pumpAndSettle();
    expect(c.calls, ['sim 2']);
  });

  testWidgets('roaming asks first, then toggles', (t) async {
    final c = _Fake(hasRoam: true);
    await _pump(t, SimSettings(controls: c));
    await t.tap(find.text('Data roaming'));
    await t.pumpAndSettle();
    expect(find.text('Turn data roaming on?'), findsOneWidget);
    expect(find.text('The connection drops for a moment.'), findsOneWidget);
    expect(c.calls, isEmpty);
    await t.tap(find.text('Turn on'));
    await t.pumpAndSettle();
    expect(c.calls, ['roam true']);
    await t.tap(find.text('Data roaming'));
    await t.pumpAndSettle();
    expect(find.text('Turn data roaming off?'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(c.calls, ['roam true', 'roam false']);
  });

  testWidgets('apn sheet saves a typed apn', (t) async {
    final c = _Fake(hasApn: true);
    await _pump(t, SimSettings(controls: c));
    await t.tap(find.text('APN'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'Saving reconnects the modem. The connection drops for a moment.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Type it'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'internet');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(c.calls, ['apn true internet']);
    expect(find.text('internet'), findsOneWidget);
  });

  testWidgets('sim settings hide when all null', (t) async {
    await _pump(t, SimSettings(controls: _Fake()));
    expect(find.textContaining('no SIM settings'), findsOneWidget);
    expect(find.text('SIM card'), findsNothing);
    expect(find.text('Data roaming'), findsNothing);
    expect(find.text('APN'), findsNothing);
  });

  testWidgets('a failing setter shows the error and stays on screen', (
    t,
  ) async {
    final c = _Fake(ca: true)..fail = true;
    await _pump(t, SpeedOptions(controls: c));
    await t.tap(find.text('Carrier aggregation'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Carrier aggregation'), findsOneWidget);
  });

  testWidgets('apn Save is off while typing mode has no apn', (t) async {
    final c = _Fake(hasApn: true);
    await _pump(t, SimSettings(controls: c));
    await t.tap(find.text('APN'));
    await t.pumpAndSettle();
    await t.tap(find.text('Type it'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(c.calls, isEmpty);
  });
}
