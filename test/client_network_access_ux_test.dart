// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/services/client_policy_schedule_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/device_network_access_card.dart';

Widget _wrapWidget({required Widget child, required AppState appState}) {
  return ProviderScope(
    overrides: [appStateProvider.overrideWith((ref) => appState)],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Client _createTestClient({
  String mac = 'AA:BB:CC:DD:EE:01',
  String ip = '192.168.1.150',
  String name = 'Test Phone',
}) {
  return Client(
    macAddress: mac,
    ipAddress: ip,
    hostname: name,
    connectionType: ConnectionType.wireless,
    isConnected: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          if (methodCall.method == 'write') {
            return null;
          }
          return null;
        });
  });

  late AppState appState;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ClientPolicyScheduleService.instance.init();
    MockApiService.resetMockState();
    SelfDeviceGuard.setMockLocalAddresses({});

    appState = AppState.instance;
    await appState.setReviewerMode(true);
    appState.setApiServiceForTesting(MockApiService());
    appState.setCapabilitiesForTesting(RouterCapabilities.mock());
    appState.setDashboardDataForTesting({});
  });

  group('DeviceNetworkAccessCard UX', () {
    testWidgets(
      'Displays Network Access section with master and protocol switches in ALLOWED state',
      (tester) async {
        final client = _createTestClient();

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Internet'), findsOneWidget);
        expect(find.text('IPv4 internet'), findsOneWidget);
        expect(find.text('IPv6 internet'), findsOneWidget);
        expect(find.textContaining('On the internet'), findsOneWidget);

        final switches = find.byType(Switch);
        expect(switches, findsNWidgets(3));
        for (final s in tester.widgetList<Switch>(switches)) {
          expect(s.value, isTrue);
        }
      },
    );

    testWidgets(
      'Master block overrides and disables IPv4 and IPv6 toggles with truthful notice',
      (tester) async {
        final client = _createTestClient(mac: '11:22:33:44:55:66');

        await tester.runAsync(() async {
          await appState.setDeviceNetworkAccessPolicy(
            policy: NetworkAccessPolicy.blocked(client.macAddress),
          );
        });

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('Off the internet until you turn it back on.'),
          findsOneWidget,
        );

        final switchWidgets = tester
            .widgetList<Switch>(find.byType(Switch))
            .toList();
        expect(switchWidgets.first.value, isFalse);

        expect(switchWidgets, hasLength(1));
        expect(find.text('Keep it off for'), findsOneWidget);
        expect(find.text('Always'), findsOneWidget);
        expect(find.text('1 hour'), findsOneWidget);
      },
    );

    testWidgets(
      'Selective protocol blocking (IPv4 allowed, IPv6 blocked) shows [IPv6 BLOCKED] and truthful banner',
      (tester) async {
        final client = _createTestClient(mac: '22:33:44:55:66:77');

        await tester.runAsync(() async {
          await appState.setDeviceNetworkAccessPolicy(
            policy: NetworkAccessPolicy(
              targetMac: client.macAddress,
              internetAccess: true,
              ipv4Access: true,
              ipv6Access: false,
            ),
          );
        });

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('IPv6 internet is off. IPv4 still works.'),
          findsOneWidget,
        );

        final switchWidgets = tester
            .widgetList<Switch>(find.byType(Switch))
            .toList();
        expect(switchWidgets[0].value, isTrue);
        expect(switchWidgets[1].value, isTrue);
        expect(switchWidgets[2].value, isFalse);
      },
    );

    testWidgets(
      'Capability gating: IPv6 toggle disabled with notice when supportsIpv6InternetFirewall is false',
      (tester) async {
        final client = _createTestClient(mac: '33:44:55:66:77:88');

        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('IPv6 internet'), findsNothing);
        expect(find.byType(Switch), findsOneWidget);
      },
    );

    testWidgets(
      'SelfDeviceGuard intercepts attempt to block managing device MAC',
      (tester) async {
        const managingMac = 'EE:FF:11:22:33:44';
        final client = _createTestClient(mac: managingMac);

        SelfDeviceGuard.setMockLocalAddresses({
          ClientNamingHelper.normalizeMac(managingMac),
        });

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        final masterSwitch = find.byType(Switch).first;
        await tester.tap(masterSwitch);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(find.text('This is your phone'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        final currentPolicy = appState.getDeviceNetworkAccessPolicy(
          managingMac,
        );
        expect(currentPolicy.isEffectivelyBlocked, isFalse);
      },
    );

    testWidgets(
      'Non-destructive legacy rule recognition reflects blocked state in card',
      (tester) async {
        const targetMac = 'AA:BB:CC:99:88:77';
        final client = _createTestClient(mac: targetMac);

        appState.setDashboardDataForTesting({
          'uciFirewallConfig': {
            'values': {
              'defaults': {
                '.type': 'defaults',
                'input': 'ACCEPT',
                'output': 'ACCEPT',
                'forward': 'REJECT',
              },
              'lan': {
                '.type': 'zone',
                'name': 'lan',
                'input': 'ACCEPT',
                'output': 'ACCEPT',
                'forward': 'ACCEPT',
                'network': ['lan'],
              },
              'legacy_rule': {
                '.type': 'rule',
                '.name': 'nointernet_wireless_clients',
                'name': 'nointernet_wireless_clients',
                'src': 'lan',
                'dest': 'wan',
                'src_mac': [targetMac],
                'target': 'REJECT',
                'enabled': '1',
              },
            },
          },
        });

        final policy = appState.getDeviceNetworkAccessPolicy(targetMac);
        expect(policy.isEffectivelyBlocked, isTrue);

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: DeviceNetworkAccessCard(client: client),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Off the internet'), findsOneWidget);
        final switchWidgets = tester
            .widgetList<Switch>(find.byType(Switch))
            .toList();
        expect(switchWidgets.first.value, isFalse);
      },
    );

    testWidgets(
      'Schedule persistence, expiry evaluation, and stale record protection',
      (tester) async {
        const mac = '44:55:66:77:88:99';
        final futureExpiry = DateTime.now().add(const Duration(hours: 2));

        final scheduledPolicy = NetworkAccessPolicy.blocked(
          mac,
          scheduleExpiry: futureExpiry,
        );
        await tester.runAsync(() async {
          await appState.setDeviceNetworkAccessPolicy(policy: scheduledPolicy);
        });

        expect(ClientPolicyScheduleService.instance.getExpiry(mac), isNotNull);
        final stored = ClientPolicyScheduleService.instance.getSchedule(mac);
        expect(stored?.targetMac, equals(ClientNamingHelper.normalizeMac(mac)));
        expect(stored?.isExpired, isFalse);

        final pastExpiry = DateTime.now().subtract(const Duration(minutes: 5));
        await tester.runAsync(() async {
          await ClientPolicyScheduleService.instance.saveSchedule(
            policy: scheduledPolicy.copyWith(scheduleExpiry: pastExpiry),
          );
        });

        final expiredStored = ClientPolicyScheduleService.instance.getSchedule(
          mac,
        );
        expect(expiredStored?.isExpired, isTrue);

        await tester.runAsync(() async {
          await appState.checkExpiredDevicePolicies();
        });

        final policyAfterExpiry = appState.getDeviceNetworkAccessPolicy(mac);
        expect(policyAfterExpiry.isEffectivelyBlocked, isFalse);
      },
    );

    testWidgets(
      'Synchronization between quick Pause/Resume and NetworkAccessPolicy',
      (tester) async {
        const mac = '55:66:77:88:99:AA';

        await tester.runAsync(() async {
          final pauseSuccess = await appState.pauseClientInternet(
            mac,
            pause: true,
          );
          expect(pauseSuccess, isTrue);
        });

        expect(appState.isInternetPaused(mac), isTrue);

        expect(
          appState.getDeviceNetworkAccessPolicy(mac).isEffectivelyBlocked,
          isTrue,
        );

        await tester.runAsync(() async {
          final unblockSuccess = await appState.setDeviceNetworkAccessPolicy(
            policy: NetworkAccessPolicy.unrestricted(mac),
          );
          expect(unblockSuccess, isTrue);
        });

        expect(appState.isInternetPaused(mac), isFalse);
        expect(
          appState.getDeviceNetworkAccessPolicy(mac).isEffectivelyBlocked,
          isFalse,
        );
      },
    );

    testWidgets(
      'showAsBottomSheet renders popup with IPv4, IPv6, and full internet switches',
      (tester) async {
        final client = _createTestClient(mac: '55:66:77:88:99:AA');

        await tester.pumpWidget(
          _wrapWidget(
            appState: appState,
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => DeviceNetworkAccessCard.showAsBottomSheet(
                    context,
                    client: client,
                  ),
                  child: const Text('Open Access Sheet'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Access Sheet'));
        await tester.pumpAndSettle();

        expect(find.text('Internet'), findsOneWidget);
        expect(find.text('IPv4 internet'), findsOneWidget);
        expect(find.text('IPv6 internet'), findsOneWidget);

        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        expect(find.text('Internet'), findsNothing);
      },
    );
  });
}
