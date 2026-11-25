import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_settings_view.dart';

Future<List<String>> _pump(WidgetTester t, {bool canEdit = true}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Scaffold(
        body: WifiSettingsView(
          canEdit: canEdit,
          networks: const [
            WifiNetworkRow(
              id: 'w0',
              name: 'NoobWRT',
              band: '5 GHz',
              security: 'WPA2/WPA3',
              devices: 2,
              enabled: true,
            ),
            WifiNetworkRow(
              id: 'w1',
              name: 'IoT',
              band: '2.4 GHz',
              security: 'WPA2',
              devices: 0,
              enabled: false,
              hidden: true,
            ),
          ],
          radios: const [
            WifiRadioRow(
              id: 'r0',
              band: '5 GHz',
              line: 'Channel 36 · 80 MHz · 20 dBm',
              enabled: true,
            ),
          ],
          onNetwork: (id) => calls.add('open $id'),
          onToggleNetwork: (id, v) => calls.add('toggle $id $v'),
          onNetworkAction: (id, a) => calls.add('${a.name} $id'),
          onAddNetwork: () => calls.add('add'),
          onRadio: (id) => calls.add('radio $id'),
          onAccessControl: () => calls.add('acl'),
          onGuest: () => calls.add('guest'),
        ),
      ),
    ),
  );
  return calls;
}

void main() {
  testWidgets('every network, radio and who-can-join setting', (t) async {
    final calls = await _pump(t);
    expect(find.text('5 GHz · WPA2/WPA3 · 2 devices'), findsOneWidget);
    expect(find.text('2.4 GHz · WPA2 · hidden · no devices'), findsOneWidget);
    expect(find.text('Channel 36 · 80 MHz · 20 dBm'), findsOneWidget);

    await t.tap(find.text('NoobWRT'));
    await t.tap(find.byType(Switch).last);
    await t.tap(find.text('Add a network'));
    await t.tap(find.text('Channel 36 · 80 MHz · 20 dBm'));
    await t.tap(find.text('Allow or block devices'));
    await t.tap(find.text('Guest network settings'));
    await t.tap(find.byTooltip('Options for IoT'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(calls, [
      'open w0',
      'toggle w1 true',
      'add',
      'radio r0',
      'acl',
      'guest',
      'remove w1',
    ]);
  });

  testWidgets('a read-only sign-in can look but not change', (t) async {
    final calls = await _pump(t, canEdit: false);
    expect(find.textContaining('can only look'), findsOneWidget);
    expect(find.text('Add a network'), findsNothing);
    await t.tap(find.text('NoobWRT'));
    await t.tap(find.byType(Switch).first);
    expect(calls, isEmpty);
  });
}
