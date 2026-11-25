import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/devices/devices_view.dart';

Client c(String name, String mac, {bool wifi = true, int? dbm, double? rx}) =>
    Client(
      ipAddress: '192.168.1.$mac',
      macAddress: 'AA:BB:CC:00:00:$mac',
      hostname: name,
      connectionType: wifi ? ConnectionType.wireless : ConnectionType.wired,
      isConnected: true,
      signalDbm: dbm,
      rxSpeed: rx,
    );

final _all = [
  c('Pixel 8', '11', dbm: -50, rx: 3.9e6),
  c('Living room TV', '12', dbm: -80, rx: 1.2e6),
  c('MacBook', '13', wifi: false),
  c('Kid tablet', '14', dbm: -55),
];

Future<List<String>> _pump(
  WidgetTester t, {
  List<Client>? clients,
  bool loading = false,
  double textScale = 1,
}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(
          ctx,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DevicesView(
          routerName: 'AW1000',
          clients: clients ?? _all,
          pausedMacs: const {'AA:BB:CC:00:00:14'},
          loading: loading,
          onOpen: (d) => calls.add('open ${d.hostname}'),
          onResume: (d) => calls.add('resume ${d.hostname}'),
          onAllDetails: () => calls.add('all'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('busy devices first, then quiet, then paused', (t) async {
    await _pump(t);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('4 online · 40.8 Mbps in use'), findsOneWidget);
    expect(find.text('Using the most'), findsOneWidget);
    expect(find.text('Quiet'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    final pixel = t.getTopLeft(find.text('Pixel 8')).dy;
    final tv = t.getTopLeft(find.text('Living room TV')).dy;
    final mac = t.getTopLeft(find.text('MacBook')).dy;
    expect(pixel < tv && tv < mac, isTrue);
    expect(find.text('31.2'), findsOneWidget);
    expect(find.text('Idle'), findsOneWidget);
  });

  testWidgets('weak signal is said in words', (t) async {
    await _pump(t);
    expect(find.text('Wi-Fi · weak signal'), findsOneWidget);
  });

  testWidgets('chips filter Wi-Fi and wired', (t) async {
    await _pump(t);
    await t.tap(find.text('Wired 1'));
    await t.pumpAndSettle();
    expect(find.text('MacBook'), findsOneWidget);
    expect(find.text('Pixel 8'), findsNothing);
    await t.tap(find.text('Wi-Fi 3'));
    await t.pumpAndSettle();
    expect(find.text('MacBook'), findsNothing);
    expect(find.text('Pixel 8'), findsOneWidget);
  });

  testWidgets('rows open, Resume resumes', (t) async {
    final calls = await _pump(t);
    await t.tap(find.text('Pixel 8'));
    await t.ensureVisible(find.text('Resume'));
    await t.tap(find.text('Resume'));
    await t.ensureVisible(find.text('All device details'));
    await t.tap(find.text('All device details'));
    expect(calls, ['open Pixel 8', 'resume Kid tablet', 'all']);
  });

  testWidgets('no devices says so', (t) async {
    await _pump(t, clients: const []);
    expect(find.text('No devices are connected.'), findsOneWidget);
  });

  testWidgets('loading says so', (t) async {
    await _pump(t, clients: const [], loading: true);
    expect(find.text('Looking for devices…'), findsOneWidget);
  });

  testWidgets('fits at 2x text', (t) async {
    await _pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });
}
