import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/router/light_meanings.dart';
import 'package:yet_another_luci_app/screens/router/router_view.dart';
import 'package:yet_another_luci_app/widgets/keystone/speed_chart.dart';

const _lit = RouterLights([
  LightColor.green,
  LightColor.red,
  LightColor.green,
  LightColor.green,
  LightColor.green,
  LightColor.green,
]);

Future<List<String>> _pump(
  WidgetTester t, {
  RouterLights lights = _lit,
  double textScale = 1,
}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: RouterView(
          name: 'AW1000',
          model: 'Arcadyan AW1000',
          firmware: 'OpenWrt 25.12.5',
          upLine: 'Up 3 days · 48°C',
          lights: lights,
          rows: lightMeanings(
            lights,
            signalPercent: 73,
            mode: 'LTE',
            wifiNetworksOn: 2,
          ),
          onReboot: () => calls.add('reboot'),
          onNightLights: () => calls.add('night'),
          onLogs: () => calls.add('logs'),
          onPowerOptions: () => calls.add('power'),
          health: const [
            RouterGauge(
              'Processor',
              '12% busy',
              0.12,
              detail: 'Load 0.31 · 0.25 · 0.20',
            ),
            RouterGauge('Memory', '180 MB of 512 MB', 0.35),
          ],
          temps: const [('Processor', '52°C'), ('Wi-Fi 5 GHz', '61°C')],
          storage: const [
            RouterGauge('On the router', '40 MB of 96 MB', 0.42),
            RouterGauge(
              'USB drive',
              '3.1 GB of 32 GB',
              0.1,
              detail: '/mnt/sda1',
            ),
          ],
          cpuSamples: const [10, 20, 15],
          memSamples: const [35, 35, 36],
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('the router and what its lights say', (t) async {
    await _pump(t);
    expect(find.text('AW1000'), findsOneWidget);
    expect(find.text('OpenWrt 25.12.5'), findsOneWidget);
    expect(find.text('Up 3 days · 48°C'), findsOneWidget);
    expect(find.text('What the lights say'), findsOneWidget);
    expect(find.text('No 5G here, using LTE'), findsOneWidget);
    expect(find.text('Good · 73%'), findsOneWidget);
  });

  testWidgets('unreadable lights say so instead of guessing', (t) async {
    await _pump(t, lights: RouterLights.unlit);
    expect(
      find.text("Keystone can't read this router's lights."),
      findsOneWidget,
    );
    expect(find.text('Not connected'), findsNothing);
  });

  testWidgets('restart asks first', (t) async {
    final calls = await _pump(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Restart router'));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
    await t.tap(find.text('Restart'));
    await t.pumpAndSettle();
    expect(calls, ['reboot']);
  });

  testWidgets('fits at 2x text', (t) async {
    await _pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets("lights at night opens the router's own setting", (t) async {
    final calls = await _pump(t);
    await t.scrollUntilVisible(find.text('Lights at night'), 200);
    await t.tap(find.text('Lights at night'));
    expect(calls, ['night']);
  });

  testWidgets('health: bars, load, temperatures and a live chart', (t) async {
    await _pump(t);
    await t.scrollUntilVisible(find.text('61°C'), 200);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('12% busy'), findsOneWidget);
    expect(find.text('Load 0.31 · 0.25 · 0.20'), findsOneWidget);
    expect(find.text('180 MB of 512 MB'), findsOneWidget);
    expect(find.byType(SpeedChart), findsOneWidget);
    expect(find.text('52°C'), findsOneWidget);
  });

  testWidgets('storage lists the router and each drive', (t) async {
    await _pump(t);
    await t.scrollUntilVisible(find.text('/mnt/sda1'), 200);
    expect(find.text('On the router'), findsOneWidget);
    expect(find.text('3.1 GB of 32 GB'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(4));
  });

  testWidgets('the menu opens logs and the other restart options', (t) async {
    final calls = await _pump(t);
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    expect(find.text('Other firmware or power off'), findsOneWidget);
    await t.tap(find.text('Logs'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('Other firmware or power off'));
    await t.pumpAndSettle();
    expect(calls, ['logs', 'power']);
  });

  test('temperatures grouped in plain words, hottest of each', () {
    expect(
      temperatureGroups([
        ('nss top thermal (Zone 0)', 66),
        ('wcss phyb0 thermal (Zone 10)', 66),
        ('Qualcomm Wi-Fi (Radio 13)', 60),
        ('CPU / SoC', 68),
        ('cluster thermal (Zone 9)', 71),
        ('Nss1', 64),
        ('board', 40),
      ]),
      [
        ('Processor', '71°C'),
        ('Network engine', '66°C'),
        ('Wi-Fi', '66°C'),
        ('Other', '40°C'),
      ],
    );
  });
}
