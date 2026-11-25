// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/screens/adguard_home_screen.dart';
import 'package:yet_another_luci_app/modules/adguard_home/utils/adguard_web_url_helper.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/adguard_credentials_dialog.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/adguard_custom_rules_dialog.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/adguard_pause_dialog.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/adguard_profile_dialog.dart';
import 'package:yet_another_luci_app/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';

class UiTestMockAdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;

  @override
  String get instanceId => 'local_$routerId';

  AdGuardConnectionStatus testConnectionResult =
      AdGuardConnectionStatus.authenticated;

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async => testConnectionResult;

  AdGuardCredentials? activeCreds;
  AdGuardStatus? mockStatus;
  AdGuardStats? mockStats;
  AdGuardFilteringStatus? mockFiltering;
  bool isAuthRequiredState = false;
  Completer<void>? delayStatusCompleter;
  AdGuardApiResult<AdGuardStatus>? customStatusResult;

  int statusCallCount = 0;
  int setCredentialsCallCount = 0;

  UiTestMockAdGuardApiService({
    required this.routerId,
    this.mockStatus,
    this.mockStats,
    this.mockFiltering,
  }) {
    mockStatus ??= const AdGuardStatus(
      version: 'v0.107.52',
      running: true,
      protectionState: AdGuardProtectionState.enabled,
      dnsAddresses: ['192.168.1.1'],
      dnsPort: 53,
      httpPort: 3000,
    );

    mockStats ??= const AdGuardStats(
      numDnsQueries: 10000,
      numBlockedFiltering: 2000,
      numReplacedSafebrowsing: 5,
      numReplacedSafesearch: 0,
      numReplacedParental: 0,
      avgProcessingTime: 0.015,
      topQueriedDomains: [AdGuardTopItem(identifier: 'google.com', count: 500)],
      topBlockedDomains: [
        AdGuardTopItem(identifier: 'adservice.google.com', count: 300),
      ],
      topClients: [AdGuardTopItem(identifier: '192.168.1.100', count: 800)],
      dnsQueriesTrend: [100, 200],
      blockedFilteringTrend: [20, 40],
      blockRatePercentage: 20.0,
    );

    mockFiltering ??= const AdGuardFilteringStatus(
      enabled: true,
      filterLists: [],
      userRules: [],
      totalRulesCount: 50000,
    );
  }

  @override
  AdGuardCredentials? get activeCredentials => activeCreds;

  @override
  bool get isAuthenticated => !isAuthRequiredState;

  @override
  bool get isAuthRequired => isAuthRequiredState;

  @override
  void setCredentials(AdGuardCredentials? credentials) {
    setCredentialsCallCount++;
    activeCreds = credentials;
  }

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    statusCallCount++;
    if (delayStatusCompleter != null) {
      await delayStatusCompleter!.future;
    }
    if (customStatusResult != null) {
      return customStatusResult!;
    }
    if (isAuthRequiredState) {
      return AdGuardApiResult.authRequired();
    }
    return AdGuardApiResult.success(mockStatus!);
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    return AdGuardApiResult.success(mockStats!);
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    return AdGuardApiResult.success(mockFiltering!);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtection({
    required bool enabled,
    Duration? duration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> setProtectionState(
    AdGuardProtectionState state, {
    Duration? pauseDuration,
  }) async {
    return AdGuardApiResult.success(true);
  }

  List<String>? lastSetUserRules;
  AdGuardApiResult<bool>? setUserRulesResult;

  @override
  Future<AdGuardApiResult<bool>> setUserRules(List<String> rules) async {
    lastSetUserRules = rules;
    return setUserRulesResult ?? AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    return AdGuardApiResult.success(const []);
  }

  @override
  Future<AdGuardApiResult<bool>> addClient(AdGuardClient client) async {
    return AdGuardApiResult.success(true);
  }

  @override
  Future<AdGuardApiResult<bool>> updateClient(
    String oldName,
    AdGuardClient client,
  ) async {
    return AdGuardApiResult.success(true);
  }

  List<String> mockUpstreamDns = const ['1.1.1.1', '8.8.8.8'];

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    return AdGuardApiResult.success(mockUpstreamDns);
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async =>
      AdGuardApiResult.success(true);
}

class UiTestFakeLuciApiService implements IApiService {
  final List<String> executedServiceActions = [];

  @override
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  }) async {
    executedServiceActions.add('$serviceName:$action');
    return true;
  }

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (object == 'luci' && method == 'getProcessList') {
      return {
        'result': [
          {
            'PID': '1660',
            'COMMAND': '/usr/bin/AdGuardHome -c /etc/adguardhome.yaml',
            '%CPU': '1.5',
            '%MEM': '3.2',
            'VSZ': '45056',
          },
        ],
      };
    }
    if (object == 'luci' && method == 'getInitList') {
      return {
        'result': {
          'adguardhome': {'enabled': true, 'running': true},
        },
      };
    }
    return {'result': []};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildTestApp({
  Key? key,
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    key: key,
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdGuard Home UI', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AdGuardController.invalidateSessionCache();
    });

    test(
      'IPv4/IPv6 Web UI URL construction handles formats and custom ports',
      () {
        expect(
          AdGuardWebUrlHelper.buildWebUrl(host: '192.168.1.1', port: 3000),
          equals('http://192.168.1.1:3000'),
        );
        expect(
          AdGuardWebUrlHelper.buildWebUrl(
            host: '192.168.1.1',
            port: 3000,
            useHttps: true,
          ),
          equals('https://192.168.1.1:3000'),
        );
        expect(
          AdGuardWebUrlHelper.buildWebUrl(host: '2001:db8::1', port: 3000),
          equals('http://[2001:db8::1]:3000'),
        );
        expect(
          AdGuardWebUrlHelper.buildWebUrl(host: '[2001:db8::1]', port: 3000),
          equals('http://[2001:db8::1]:3000'),
        );
        expect(
          AdGuardWebUrlHelper.buildWebUrl(host: '10.0.0.1', port: 8080),
          equals('http://10.0.0.1:8080'),
        );
      },
    );

    testWidgets(
      'Reviewer Mode suppresses browser launch and shows info notification',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('launch_button'),
                  onPressed: () async {
                    await AdGuardWebUrlHelper.launchWebInterface(
                      context: context,
                      isReviewerMode: true,
                      host: '192.168.1.1',
                      port: 3000,
                    );
                  },
                  child: const Text('Launch'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('launch_button')));
        await tester.pump();

        expect(
          find.text('The demo has no AdGuard Home page to open.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AdGuardPauseDialog presents preset durations and custom date/time option',
      (tester) async {
        Duration? selectedDuration;

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_pause_dialog'),
                  onPressed: () async {
                    selectedDuration = await AdGuardPauseDialog.show(context);
                  },
                  child: const Text('Pause'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_pause_dialog')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_pause_15m_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_30m_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_1h_option')), findsOneWidget);
        expect(find.byKey(const Key('agh_pause_24h_option')), findsOneWidget);
        expect(
          find.byKey(const Key('agh_pause_custom_option')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('agh_pause_30m_option')));
        await tester.pumpAndSettle();

        expect(selectedDuration, equals(const Duration(minutes: 30)));
      },
    );

    testWidgets('Auth-required banner displays when credentials are required', (
      tester,
    ) async {
      final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
        ..isAuthRequiredState = true;
      final mockLuci = UiTestFakeLuciApiService();

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            adguardControllerProvider('test-router').overrideWith(
              (ref) => AdGuardController(
                ref,
                'test-router',
                apiServiceOverride: mockApi,
                luciApiServiceOverride: mockLuci,
              ),
            ),
          ],
          child: const AdGuardHomeScreen(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_auth_required_banner')), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets(
      'AdGuardCredentialsDialog collects and submits credentials to controller',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..isAuthRequiredState = true;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_creds_dialog'),
                  onPressed: () {
                    AdGuardCredentialsDialog.show(
                      context,
                      controller: controller,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_creds_dialog')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_credentials_username_field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_credentials_password_field')),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('agh_credentials_username_field')),
          'adguard_admin',
        );
        await tester.enterText(
          find.byKey(const Key('agh_credentials_password_field')),
          'super_secret_pass',
        );
        await tester.pump();

        mockApi.isAuthRequiredState = false;
        await tester.tap(
          find.byKey(const Key('agh_credentials_submit_button')),
        );
        await tester.pumpAndSettle();

        expect(mockApi.setCredentialsCallCount, equals(1));
        expect(mockApi.activeCreds?.username, equals('adguard_admin'));
        expect(mockApi.activeCreds?.password, equals('super_secret_pass'));

        controller.dispose();
      },
    );

    testWidgets(
      '9b. AdGuardCredentialsDialog displays authentication failed error and remains open when submitted credentials fail',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..isAuthRequiredState = true;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_creds_dialog_9b'),
                  onPressed: () {
                    AdGuardCredentialsDialog.show(
                      context,
                      controller: controller,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_creds_dialog_9b')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('agh_credentials_username_field')),
          'bad_user',
        );
        await tester.enterText(
          find.byKey(const Key('agh_credentials_password_field')),
          'wrong_password',
        );
        await tester.pump();

        await tester.tap(
          find.byKey(const Key('agh_credentials_submit_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdGuardCredentialsDialog), findsOneWidget);
        expect(
          find.text('Authentication failed. Invalid username or password.'),
          findsOneWidget,
        );

        controller.dispose();
      },
    );

    testWidgets(
      'Polling interval menu presents exactly Off, 5s, 10s, 30s, Manual with no 60s option',
      (tester) async {
        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Update the numbers'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(
          find.byType(DropdownButtonFormField<AdGuardPollingInterval>),
        );
        await tester.pumpAndSettle();

        for (final t in const [
          'Never',
          'Every 5 seconds',
          'Every 10 seconds',
          'Every 30 seconds',
          'Only when I pull down',
        ]) {
          expect(find.text(t), findsWidgets);
        }
        expect(find.textContaining('60 seconds'), findsNothing);
      },
    );

    testWidgets(
      'Independent router IDs isolate AdGuard controller and screen states',
      (tester) async {
        final mockApiA = UiTestMockAdGuardApiService(
          routerId: 'router-A',
          mockStatus: const AdGuardStatus(
            version: 'v0.107.50',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['192.168.1.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );
        final mockApiB = UiTestMockAdGuardApiService(
          routerId: 'router-B',
          mockStatus: const AdGuardStatus(
            version: 'v0.107.99',
            running: false,
            protectionState: AdGuardProtectionState.disabled,
            dnsAddresses: ['10.0.0.1'],
            dnsPort: 5353,
            httpPort: 8080,
          ),
        );

        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('router-A').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-A',
                  apiServiceOverride: mockApiA,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
              adguardControllerProvider('router-B').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-B',
                  apiServiceOverride: mockApiB,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'router-A'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('v0.107.50'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('v0.107.50'), findsOneWidget);
        expect(find.textContaining('v0.107.99'), findsNothing);

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('router-A').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-A',
                  apiServiceOverride: mockApiA,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
              adguardControllerProvider('router-B').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'router-B',
                  apiServiceOverride: mockApiB,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'router-B'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.textContaining('v0.107.99'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('v0.107.99'), findsOneWidget);
        expect(find.textContaining('v0.107.50'), findsNothing);
      },
    );

    testWidgets(
      'AdGuardProfileDialog validates inputs, tests connection, and saves profile',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_dialog_button'),
                onPressed: () =>
                    AdGuardProfileDialog.show(context, controller: controller),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();
        expect(find.text('Please enter a name'), findsOneWidget);
        expect(find.text('Host is required'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Raspberry Pi AGH',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          '192.168.1.129',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_port_field')),
          '3000',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_username_field')),
          'nightcode',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_password_field')),
          'secret123',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_test_status_indicator')),
          findsOneWidget,
        );
        expect(find.text('It answers, and the sign-in works.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();

        expect(find.byType(AdGuardProfileDialog), findsNothing);
        expect(
          controller.state.profiles.any((p) => p.name == 'Raspberry Pi AGH'),
          isTrue,
        );
        expect(
          controller.state.activeProfile?.name,
          equals('Raspberry Pi AGH'),
        );

        controller.dispose();
      },
    );

    testWidgets(
      '18b. AdGuardProfileDialog distinguishes authentication failed from authentication required',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router')
          ..testConnectionResult = AdGuardConnectionStatus.authRequired;
        final mockLuci = UiTestFakeLuciApiService();

        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: const Key('open_dialog_button_18b'),
                  onPressed: () {
                    AdGuardProfileDialog.show(context, controller: controller);
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog_button_18b')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Pi Auth Test',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          '192.168.1.129',
        );

        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();
        expect(find.text('It needs a name and password.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('agh_profile_username_field')),
          'nightcode',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_password_field')),
          'wrongpass',
        );
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();
        expect(
          find.text('Authentication failed. Invalid username or password.'),
          findsOneWidget,
        );

        controller.dispose();
      },
    );

    testWidgets(
      'AdGuardProfileDialog sanitizes host input and validates IP/hostname format',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final controller = AdGuardController(
          container.read(adguardControllerProvider('test-router').notifier).ref,
          'test-router',
          apiServiceOverride: mockApi,
          luciApiServiceOverride: mockLuci,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('open_dialog_button'),
                onPressed: () =>
                    AdGuardProfileDialog.show(context, controller: controller),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('agh_profile_name_field')),
          'Test AGH',
        );
        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          'invalid host with spaces!!!',
        );
        await tester.tap(find.byKey(const Key('agh_save_profile_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('Enter a valid IP address or hostname'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('agh_profile_host_field')),
          'http://192.168.1.129:3000/',
        );
        await tester.ensureVisible(
          find.byKey(const Key('agh_test_connection_button')),
        );
        await tester.tap(find.byKey(const Key('agh_test_connection_button')));
        await tester.pumpAndSettle();

        final hostField = tester.widget<KsField>(
          find.byKey(const Key('agh_profile_host_field')),
        );
        expect(hostField.controller.text, equals('192.168.1.129'));
        final portField = tester.widget<KsField>(
          find.byKey(const Key('agh_profile_port_field')),
        );
        expect(portField.controller.text, equals('3000'));
        expect(find.text('It answers, and the sign-in works.'), findsOneWidget);

        controller.dispose();
      },
    );

    testWidgets(
      'AdGuardHomeScreen allows editing active external profile via AppBar menu',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final extProfile = AdGuardInstanceProfile.external(
          id: 'ext_pi_edit',
          name: 'Raspberry Pi External',
          host: '192.168.1.129',
          port: 3000,
        );

        final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('test-router').overrideWith(
                (ref) => AdGuardController(
                  ref,
                  'test-router',
                  initialProfile: extProfile,
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                ),
              ),
            ],
            child: const AdGuardHomeScreen(routerId: 'test-router'),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('agh_profile_selector_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_edit_active_profile_button')),
          findsOneWidget,
        );
        expect(find.textContaining('Edit '), findsWidgets);

        await tester.tap(
          find.byKey(const Key('agh_edit_active_profile_button')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AdGuardProfileDialog), findsOneWidget);
        expect(find.text('Edit this AdGuard Home'), findsOneWidget);
        expect(find.text('Raspberry Pi External'), findsWidgets);
      },
    );

    testWidgets('Profile deletion cancellation keeps profile intact', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final extProfile = AdGuardInstanceProfile.external(
        id: 'ext_cancel_del',
        name: 'Cancel Me Not',
        host: '192.168.1.130',
        port: 3000,
      );

      final mockApi = UiTestMockAdGuardApiService(routerId: 'test-router');
      final mockLuci = UiTestFakeLuciApiService();

      await tester.pumpWidget(
        buildTestApp(
          overrides: [
            adguardControllerProvider('test-router').overrideWith(
              (ref) => AdGuardController(
                ref,
                'test-router',
                initialProfile: extProfile,
                apiServiceOverride: mockApi,
                luciApiServiceOverride: mockLuci,
              ),
            ),
          ],
          child: const AdGuardHomeScreen(routerId: 'test-router'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('agh_profile_selector_button')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('agh_delete_active_profile_button')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Remove Cancel Me Not'), findsWidgets);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Cancel Me Not?'), findsNothing);
      expect(find.text('Cancel Me Not'), findsWidgets);
    });

    testWidgets(
      'AdGuardHomeScreen surfaces generalError banner without duplicating existing banners',
      (tester) async {
        tester.view.physicalSize = const Size(800, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final mockApi = UiTestMockAdGuardApiService(routerId: 'gen-err-router');
        final mockLuci = UiTestFakeLuciApiService();

        await tester.pumpWidget(
          buildTestApp(
            overrides: [
              adguardControllerProvider('gen-err-router').overrideWith((ref) {
                final c = AdGuardController(
                  ref,
                  'gen-err-router',
                  apiServiceOverride: mockApi,
                  luciApiServiceOverride: mockLuci,
                );
                c.refresh().then((_) {
                  c.state = c.state.copyWith(
                    generalError:
                        'Unexpected system fault during background sync',
                  );
                });
                return c;
              }),
            ],
            child: const AdGuardHomeScreen(routerId: 'gen-err-router'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_general_error_banner')),
          findsOneWidget,
        );
        expect(
          find.text('Unexpected system fault during background sync'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_api_unreachable_banner')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('agh_invalid_endpoint_banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'AdGuardCustomRulesDialog renders rules, counts lines, and submits edits',
      (tester) async {
        final container = ProviderContainer();
        final mockApiService = UiTestMockAdGuardApiService(
          routerId: 'test_router_custom_rules',
        );
        final controller = AdGuardController(
          container
              .read(
                adguardControllerProvider('test_router_custom_rules').notifier,
              )
              .ref,
          'test_router_custom_rules',
          apiServiceOverride: mockApiService,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AdGuardCustomRulesDialog.show(
                  context,
                  controller: controller,
                  initialRules: const [
                    '||adservice.com^',
                    '! A comment line',
                    '127.0.0.1 bad.org',
                  ],
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_custom_rules_dialog')),
          findsOneWidget,
        );
        expect(find.text('2 rules. One per line.'), findsOneWidget);

        final textField = find.byKey(const Key('agh_custom_rules_text_field'));
        expect(textField, findsOneWidget);

        await tester.enterText(
          textField,
          '||domain1.com^\n||domain2.com^\n||domain3.com^\n! Just comment',
        );
        await tester.pump();

        expect(find.text('3 rules. One per line.'), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_custom_rules_save_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_custom_rules_dialog')), findsNothing);
        expect(
          mockApiService.lastSetUserRules,
          equals([
            '||domain1.com^',
            '||domain2.com^',
            '||domain3.com^',
            '! Just comment',
          ]),
        );
      },
    );

    testWidgets(
      'AdGuardCustomRulesDialog displays error banner on save failure',
      (tester) async {
        final container = ProviderContainer();
        final mockApiService = UiTestMockAdGuardApiService(
          routerId: 'test_router_custom_rules_err',
        );
        mockApiService.setUserRulesResult = AdGuardApiResult.failure(
          const AdGuardApiException(
            type: AdGuardApiErrorType.httpError,
            statusCode: 400,
            message: 'Invalid filter rule syntax error',
          ),
        );
        final controller = AdGuardController(
          container
              .read(
                adguardControllerProvider(
                  'test_router_custom_rules_err',
                ).notifier,
              )
              .ref,
          'test_router_custom_rules_err',
          apiServiceOverride: mockApiService,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AdGuardCustomRulesDialog.show(
                  context,
                  controller: controller,
                  initialRules: const ['bad_syntax_rule'],
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_custom_rules_dialog')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('agh_custom_rules_save_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_custom_rules_dialog')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_custom_rules_error_banner')),
          findsOneWidget,
        );
        expect(
          find.textContaining('Invalid filter rule syntax error'),
          findsOneWidget,
        );
      },
    );
  });
}
