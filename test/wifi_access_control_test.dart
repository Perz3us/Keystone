// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wifi_access_control_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

void main() {
  group('device addresses', () {
    test('any common way of typing one is read', () {
      expect(parseMac('aa-bb-cc-dd-ee-ff'), 'AA:BB:CC:DD:EE:FF');
      expect(parseMac('aabb.ccdd.eeff'), 'AA:BB:CC:DD:EE:FF');
      expect(parseMac('AABBCCDDEEFF'), 'AA:BB:CC:DD:EE:FF');
      expect(parseMac('AA:BB:CC'), isNull);
      expect(parseMac('hello'), isNull);
    });

    test('the router list is read as a list or a spaced string', () {
      expect(readMacList(['aa:bb:cc:dd:ee:ff', 'junk']), ['AA:BB:CC:DD:EE:FF']);
      expect(readMacList('aa:bb:cc:dd:ee:ff 11:22:33:44:55:66'), [
        'AA:BB:CC:DD:EE:FF',
        '11:22:33:44:55:66',
      ]);
      expect(readMacList(null), isEmpty);
    });

    test('rules read back from the router and summarise plainly', () {
      expect(JoinRule.from('allow'), JoinRule.onlyListed);
      expect(JoinRule.from('deny'), JoinRule.allButListed);
      expect(JoinRule.from(null), JoinRule.anyone);
      expect(JoinRule.onlyListed.summary(3), 'Only 3 devices');
      expect(JoinRule.allButListed.summary(1), 'Everyone except 1 device');
      expect(JoinRule.onlyListed.summary(0), 'Nobody (the list is empty)');
    });
  });

  testWidgets('the list shows only when it matters, and marks this phone', (
    tester,
  ) async {
    var rule = JoinRule.anyone;
    String? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, set) => SingleChildScrollView(
              child: NetworkAccessView(
                network: 'Home',
                rule: rule,
                devices: const [
                  (mac: 'AA:AA:AA:AA:AA:AA', name: 'Pixel'),
                  (mac: 'BB:BB:BB:BB:BB:BB', name: null),
                ],
                thisPhone: 'AA:AA:AA:AA:AA:AA',
                onRule: (r) => set(() => rule = r),
                onRemove: (m) => removed = m,
                onAdd: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Add a device'), findsNothing);
    await tester.tap(find.text('Only the devices below'));
    await tester.pump();
    expect(find.text('Allowed'), findsOneWidget);
    expect(find.text('Pixel (this phone)'), findsOneWidget);
    expect(find.textContaining('is turned away from Home'), findsOneWidget);
    await tester.tap(find.byTooltip('Take off the list').last);
    expect(removed, 'BB:BB:BB:BB:BB:BB');
    await tester.tap(find.text('Everyone except the devices below'));
    await tester.pump();
    expect(find.text('Blocked'), findsOneWidget);
  });

  testWidgets('saving an allow list without this phone asks first', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    SelfDeviceGuard.setMockLocalAddresses({'192.168.1.50'});
    addTearDown(() => SelfDeviceGuard.setMockLocalAddresses(null));
    final app = AppState.instance;
    await app.initializationFuture;
    app.clients = [
      Client(
        ipAddress: '192.168.1.50',
        macAddress: 'AA:AA:AA:AA:AA:AA',
        hostname: 'My-Phone',
        connectionType: ConnectionType.wireless,
        ssid: 'Home_5G',
        isConnected: true,
      ),
    ];
    const iface = WirelessInterface(
      ifName: 'wlan0',
      sectionName: 'default_radio0',
      ssid: 'Home_5G',
      mode: 'ap',
      encryption: 'sae',
      securityMode: WifiSecurityMode.saeOnly,
      pmfState: PmfState.required,
      channel: '36',
      isEnabled: true,
      stations: [],
    );
    const radio = WirelessRadio(
      name: 'radio0',
      isUp: true,
      channel: '36',
      country: 'US',
      interfaces: [iface],
    );
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: NetworkAccessScreen(radio: radio, interface: iface),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Only the devices below'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this phone connected?'), findsOneWidget);
    expect(find.text('Add this phone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Keep this phone connected?'), findsNothing);
  });
}
