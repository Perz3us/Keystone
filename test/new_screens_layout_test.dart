import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/background/alerts_store.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_models.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_settings_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_sheet.dart';
import 'package:yet_another_luci_app/modules/noobwrt/slow/slow_checks.dart';
import 'package:yet_another_luci_app/modules/noobwrt/slow/slow_screen.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/restart_sheet.dart';
import 'package:yet_another_luci_app/screens/wifi/channel_check_screen.dart';

void main() {
  late AlertsPhone phone;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    phone = AlertsPhone(
      store: AlertsStore(await SharedPreferences.getInstance()),
      routerId: 'r',
      readKey: () async => null,
      writeKey: (_) async {},
      interval: () async => null,
      setInterval: (_) async {},
      notificationsAllowed: () async => true,
      askForNotifications: () async => true,
      openNotificationSettings: () async {},
    );
  });

  final screens = <String, Widget Function()>{
    'why slow': () => SlowScreen(
      checks: () => {
        SlowCause.weakSignal: () async => signalFinding(rsrp: -118),
        SlowCause.proxyOn: () async => proxyFinding(true),
        SlowCause.sqm: () async => throw StateError('x'),
      },
    ),
    'channels': () => ChannelCheckScreen(
      scan: () async => [
        for (var c = 1; c <= 11; c++) {'channel': c, 'signal': -50},
      ],
      is5g: false,
      current: 1,
      allowed: {for (var c = 1; c <= 13; c++) c},
    ),
    'restart': () => Scaffold(
      body: SingleChildScrollView(
        child: RestartForm(guarded: true, onSave: (_) async {}),
      ),
    ),
    'plan': () => Scaffold(
      body: SingleChildScrollView(
        child: DataPlanForm(
          client: DataPlanClient((_, _) async => {}),
          sim: 'main',
        ),
      ),
    ),
    'alert settings': () => AlertSettingsScreen(
      client: AlertsClient((_, _) async => {}),
      phone: phone,
      settings: const AlertSettings(),
    ),
    'alerts': () => AlertsScreen(
      client: AlertsClient(
        (m, _) async => m == 'info'
            ? {'newest': 1, 'settings': {}}
            : {
                'events': [
                  {
                    'id': 1,
                    'type': 'internet',
                    'start': 1800000000,
                    'end': 1800000720,
                    'approx': true,
                    'detail': {'drops': 6},
                  },
                ],
                'newest': 1,
              },
      ),
      phone: phone,
      install: () async {},
    ),
  };

  for (final MapEntry(key: name, value: build) in screens.entries) {
    for (final dark in [false, true]) {
      testWidgets('$name fits${dark ? ', dark' : ''}', (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            theme: dark
                ? KeystoneTheme.buildDarkTheme()
                : KeystoneTheme.buildLightTheme(),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: build(),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  }
}
