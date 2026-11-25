// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/screens/firewall_security_screen.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/modules/firewall_security/widgets/add_port_forward_dialog.dart';
import 'package:yet_another_luci_app/modules/firewall_security/widgets/block_incoming_traffic_dialog.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

Widget _wrapWidget({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Map<String, dynamic> _buildSampleUciFirewall({
  List<Map<String, dynamic>>? redirects,
  List<Map<String, dynamic>>? rules,
}) {
  return {
    'defaults': {
      '.type': 'defaults',
      'syn_flood': '1',
      'input': 'ACCEPT',
      'output': 'ACCEPT',
      'forward': 'REJECT',
    },
    'zone_lan': {
      '.type': 'zone',
      'name': 'lan',
      'input': 'ACCEPT',
      'output': 'ACCEPT',
      'forward': 'ACCEPT',
      'network': ['lan'],
      'masq': '0',
    },
    'zone_wan': {
      '.type': 'zone',
      'name': 'wan',
      'input': 'REJECT',
      'output': 'ACCEPT',
      'forward': 'REJECT',
      'masq': '1',
      'mtu_fix': '1',
      'network': ['wan', 'wan6'],
    },
    'fwd_lan_wan': {'.type': 'forwarding', 'src': 'lan', 'dest': 'wan'},
    if (redirects != null)
      for (int i = 0; i < redirects.length; i++)
        'redirect_$i': {'.type': 'redirect', ...redirects[i]},
    if (rules != null)
      for (int i = 0; i < rules.length; i++)
        'rule_$i': {'.type': 'rule', ...rules[i]},
  };
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
    appState = AppState.instance;
    await appState.setReviewerMode(true);
    appState.setApiServiceForTesting(MockApiService());
  });

  tearDown(() {
    appState.clearFreeDiskSpaceForTesting();
  });

  group('AddPortForwardDialog', () {
    testWidgets(
      'Preset selector includes Plex, Minecraft, Web Server, Custom, and excludes SSH',
      (tester) async {
        final uci = _buildSampleUciFirewall();
        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const AddPortForwardDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Plex Media Server'));
        await tester.pumpAndSettle();

        expect(find.text('Minecraft Server'), findsOneWidget);
        expect(find.text('Web Server (HTTP/HTTPS)'), findsOneWidget);
        expect(find.text('Custom Service'), findsOneWidget);

        expect(find.textContaining('SSH'), findsNothing);
        expect(find.textContaining('Dropbear'), findsNothing);
      },
    );

    testWidgets(
      'Selecting Web Server preset displays warning banner and opens 80 and 443',
      (tester) async {
        final uci = _buildSampleUciFirewall();
        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const AddPortForwardDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Plex Media Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Web Server (HTTP/HTTPS)'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Anyone on the internet will be able to reach this web server.',
          ),
          findsOneWidget,
        );
        expect(find.text('Opens port 80,443 (TCP).'), findsOneWidget);
      },
    );

    testWidgets('Preflight conflict detects already in-use external port', (
      tester,
    ) async {
      final uci = _buildSampleUciFirewall(
        redirects: [
          {
            '.name': 'redirect_plex',
            'name': 'Existing Plex',
            'src': 'wan',
            'src_dport': '32400',
            'dest': 'lan',
            'dest_ip': '192.168.1.150',
            'dest_port': '32400',
            'proto': 'tcp',
            'target': 'DNAT',
            'enabled': '1',
          },
        ],
      );

      appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
      appState.setCapabilitiesForTesting(
        RouterCapabilities.conservative('test-router'),
      );
      appState.clients = [
        Client(
          ipAddress: '192.168.1.150',
          macAddress: 'AA:BB:CC:DD:EE:01',
          hostname: 'PC',
        ),
      ];

      await tester.pumpWidget(
        _wrapWidget(
          overrides: [appStateProvider.overrideWith((ref) => appState)],
          child: const AddPortForwardDialog(),
        ),
      );
      await tester.pumpAndSettle();

      final submitBtn = find.widgetWithText(FilledButton, 'Open');
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(
        find.text('This port is already being used by another rule.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'Safety guard blocks exposing router management ports externally',
      (tester) async {
        final uci = _buildSampleUciFirewall();
        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const AddPortForwardDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Plex Media Server'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Custom Service'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).at(0), 'SSH Expose');
        await tester.enterText(find.byType(TextFormField).at(1), '22');
        if (find.text('Type an address').evaluate().isNotEmpty) {
          await tester.ensureVisible(find.text('Type an address'));
          await tester.tap(find.text('Type an address'));
          await tester.pumpAndSettle();
        }
        await tester.enterText(find.byType(TextFormField).last, '192.168.1.1');
        await tester.pumpAndSettle();

        final submitBtn = find.widgetWithText(FilledButton, 'Open');
        await tester.tap(submitBtn);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'This port is reserved for router administration. Exposing it externally is not permitted.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('BlockIncomingTrafficDialog', () {
    testWidgets(
      'Preflight detects already-blocked incoming traffic on default WAN reject policy',
      (tester) async {
        final uci = _buildSampleUciFirewall();
        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const BlockIncomingTrafficDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextFormField).first,
          '198.51.100.55',
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('Already blocked.'), findsOneWidget);
        expect(find.text('Add a rule anyway'), findsOneWidget);
      },
    );

    testWidgets(
      'Preflight detects currently-allowed incoming traffic when port forward exists',
      (tester) async {
        final uci = _buildSampleUciFirewall(
          redirects: [
            {
              '.name': 'redirect_camera',
              'name': 'Camera Stream',
              'src': 'wan',
              'src_dport': '8080',
              'dest': 'lan',
              'dest_ip': '192.168.1.80',
              'dest_port': '8080',
              'proto': 'tcp',
              'target': 'DNAT',
              'enabled': '1',
            },
          ],
        );

        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const BlockIncomingTrafficDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('A port'));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextFormField).first, '8080');
        await tester.pumpAndSettle();

        expect(find.textContaining('This is let in right now'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Block'), findsOneWidget);
      },
    );

    testWidgets(
      'Preflight returns unableToDetermine when internal destination zone cannot be identified',
      (tester) async {
        final uci = {
          'defaults': {
            '.type': 'defaults',
            'syn_flood': '1',
            'input': 'ACCEPT',
            'output': 'ACCEPT',
            'forward': 'REJECT',
          },
          'zone_wan': {
            '.type': 'zone',
            'name': 'wan',
            'input': 'REJECT',
            'output': 'ACCEPT',
            'forward': 'REJECT',
            'masq': '1',
            'network': ['wan'],
          },
        };

        appState.setDashboardDataForTesting({'uciFirewallConfig': uci});
        appState.setCapabilitiesForTesting(
          RouterCapabilities.conservative('test-router'),
        );

        await tester.pumpWidget(
          _wrapWidget(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: const BlockIncomingTrafficDialog(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('A port'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, '9000');
        await tester.pumpAndSettle();

        expect(find.textContaining("can't tell whether"), findsOneWidget);
        final blockBtn = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Block'),
        );
        expect(blockBtn.onPressed, isNull);
      },
    );
  });

  group('Topology & Semantics', () {
    test('FirewallOverview primaryLanZoneName extracts internal zone', () {
      final uci = _buildSampleUciFirewall();
      final overview = FirewallOverview.fromUciData(
        uci,
        backend: FirewallBackend.fw4,
      );

      expect(overview.primaryLanZoneName, equals('lan'));
    });

    test(
      'Incoming destination port semantics: compared against destPort and redirect srcPort',
      () {
        final uci = _buildSampleUciFirewall(
          redirects: [
            {
              '.name': 'redirect_http',
              'name': 'HTTP',
              'src': 'wan',
              'src_dport': '80',
              'dest': 'lan',
              'dest_ip': '192.168.1.10',
              'dest_port': '80',
              'proto': 'tcp',
              'target': 'DNAT',
              'enabled': '1',
            },
          ],
        );
        final overview = FirewallOverview.fromUciData(
          uci,
          backend: FirewallBackend.fw4,
        );

        final resAllowed = FirewallValidator.evaluateIncomingTrafficPreflight(
          overview: overview,
          incomingPort: '80',
          proto: 'tcp',
        );
        expect(resAllowed.isCurrentlyAllowed, isTrue);

        final resBlocked = FirewallValidator.evaluateIncomingTrafficPreflight(
          overview: overview,
          incomingPort: '8080',
          proto: 'tcp',
        );
        expect(resBlocked.isAlreadyBlocked, isTrue);
      },
    );
  });

  group('Firewall page in plain words', () {
    FirewallOverview overview({bool wanOpen = false}) =>
        FirewallOverview.fromUciData(
          _buildSampleUciFirewall(
            redirects: [
              {
                'name': 'Camera',
                'src': 'wan',
                'src_dport': '8080',
                'dest': 'lan',
                'dest_ip': '192.168.1.50',
                'dest_port': '80',
                'proto': 'tcp',
              },
            ],
            rules: [
              {
                'name': 'No SSH',
                'src': 'wan',
                'dest_port': '22',
                'proto': 'tcp',
                'target': 'REJECT',
              },
            ],
          )..['zone_wan']!['input'] = wanOpen ? 'ACCEPT' : 'REJECT',
          backend: FirewallBackend.fw4,
        );

    test('lines read as sentences', () {
      final o = overview();
      expect(isProtected(o), isTrue);
      expect(isProtected(overview(wanOpen: true)), isFalse);
      expect(
        forwardLine(o.portForwards.single),
        'Port 8080 (TCP) goes to 192.168.1.50 port 80',
      );
      expect(
        ruleLine(o.customRules.single),
        'Blocks port 22 (TCP) from the internet',
      );
      final wan = o.zones.firstWhere((z) => z.name == 'wan');
      expect(
        zoneLine(wan),
        'Incoming blocked · passing through blocked · shares one address',
      );
    });

    testWidgets('a rule switch and an open port can be acted on', (
      tester,
    ) async {
      final toggled = <bool>[];
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FirewallView(
                overview: overview(),
                canEdit: true,
                onOpenPort: () => opened++,
                onBlock: () {},
                onForward: (_) {},
                onDeleteForward: (_) {},
                onRule: (_) {},
                onToggleRule: (_, v) => toggled.add(v),
                onDeleteRule: (_) {},
                onMoveRule: (_, _) {},
                onNewRule: () {},
                onOffload: (_, _) {},
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Protected.'), findsOneWidget);
      await tester.tap(find.text('Open a port'));
      expect(opened, 1);
      await tester.tap(find.byType(Switch).first);
      expect(toggled, [false]);
    });
  });
}
