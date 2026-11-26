import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/devices/all_devices.dart';

Client _c(
  String name,
  String mac, {
  bool online = true,
  String ip = '192.168.1.10',
  String? vendor,
  String? ap,
}) => Client(
  ipAddress: ip,
  macAddress: mac,
  hostname: name,
  vendor: vendor,
  connectionType: ConnectionType.wireless,
  isConnected: online,
  isDumbApClient: ap != null,
  apName: ap,
);

final _all = [
  _c('Phone', 'AA:00:00:00:00:01', vendor: 'Samsung'),
  _c('Laptop', 'AA:00:00:00:00:02', online: false, ip: '192.168.1.20'),
  _c('TV', 'AA:00:00:00:00:03', ap: 'Upstairs AP'),
];

void main() {
  test('blocked devices the router no longer lists still show', () {
    final list = withBlocked(_all, {'aa-00-00-00-00-09'});
    expect(list.length, 4);
    expect(list.last.normalizedMac, 'AA:00:00:00:00:09');
  });

  test('filters: online, offline, blocked, and search', () {
    final blocked = {'AA:00:00:00:00:01'};
    List<String> names(DeviceFilter f, [String q = '']) => [
      for (final c in filterDevices(
        _all,
        filter: f,
        query: q,
        blocked: blocked,
      ))
        c.hostname,
    ];
    expect(names(DeviceFilter.all), ['Phone', 'Laptop', 'TV']);
    expect(names(DeviceFilter.online), ['TV']);
    expect(names(DeviceFilter.offline), ['Laptop']);
    expect(names(DeviceFilter.blocked), ['Phone']);
    expect(names(DeviceFilter.all, 'samsung'), ['Phone']);
    expect(names(DeviceFilter.all, '1.20'), ['Laptop']);
    expect(names(DeviceFilter.all, '00:03'), ['TV']);
  });

  testWidgets('every device with its status, filters and search', (t) async {
    final opened = <String>[];
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Scaffold(
          body: AllDevicesView(
            devices: _all,
            blocked: const {'AA:00:00:00:00:01'},
            paused: const {},
            onOpen: (c) => opened.add(c.hostname),
          ),
        ),
      ),
    );
    expect(find.text('All devices'), findsOneWidget);
    expect(find.text('Blocked'), findsWidgets);
    expect(find.text('Offline'), findsWidgets);
    expect(find.textContaining('via Upstairs AP'), findsOneWidget);
    expect(find.textContaining('Samsung'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'Offline 1'));
    await t.pump();
    expect(find.text('Phone'), findsNothing);
    expect(find.text('Laptop'), findsOneWidget);

    await t.tap(find.widgetWithText(ChoiceChip, 'All 3'));
    await t.enterText(find.byType(TextField), 'tv');
    await t.pump();
    expect(find.text('Laptop'), findsNothing);
    await t.tap(find.text('TV'));
    expect(opened, ['TV']);
  });

  testWidgets('limited devices and most data first', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: Scaffold(
          body: AllDevicesView(
            devices: _all,
            blocked: const {},
            paused: const {},
            limited: const {'AA:00:00:00:00:02'},
            usage: const {
              'AA:00:00:00:00:01': 120000000,
              'AA:00:00:00:00:03': 4200000000,
            },
            usageLabel: 'This month',
            onOpen: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Limited'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Most data'));
    await t.pump();
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(y('TV'), lessThan(y('Phone')));
    expect(y('Phone'), lessThan(y('Laptop')));
    expect(find.text('4.2 GB this month'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'Limited 1'));
    await t.pump();
    expect(find.text('TV'), findsNothing);
    expect(find.text('Laptop'), findsOneWidget);
  });

  testWidgets('a note with an action above the list', (t) async {
    var tapped = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: Scaffold(
          body: AllDevicesView(
            devices: _all,
            blocked: const {},
            paused: const {},
            onOpen: (_) {},
            note: 'See the data each device uses this month',
            noteAction: 'Install',
            onNote: () => tapped++,
          ),
        ),
      ),
    );
    await t.tap(find.text('Install'));
    expect(tapped, 1);
  });
}
