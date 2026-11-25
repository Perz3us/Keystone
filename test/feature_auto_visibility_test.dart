// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/core/luci_module.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/noobwrt/passwall/passwall_module.dart';

class _Fake extends LuciModule {
  _Fake({this.ubus = const {}, this.configs = const {}});
  final Set<String> ubus;
  final Set<String> configs;

  @override
  String get id => 'fake';
  @override
  String get name => 'Fake';
  @override
  String get description => '';
  @override
  IconData get icon => Icons.extension;
  @override
  LuciModuleCategory get category => LuciModuleCategory.tools;
  @override
  Set<String> get requiredUbus => ubus;
  @override
  Set<String> get requiredConfigs => configs;
  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const SizedBox();
}

RouterCapabilities _caps({
  Set<String> ubusObjects = const {},
  Set<String> installedUbus = const {},
  Set<String> installedConfigs = const {},
}) => RouterCapabilities(
  routerId: 'r',
  probedAt: DateTime(2026),
  ubusObjects: ubusObjects,
  installedUbus: installedUbus,
  installedConfigs: installedConfigs,
);

class _Auth implements IAuthService {
  @override
  String? get sysauth => 'tok';
  @override
  bool get isAuthenticated => true;
  @override
  bool get useHttps => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RouterApi extends RealApiService {
  _RouterApi({
    this.ubus = const [],
    this.configs,
    this.listThrows = false,
    this.gate,
  });
  final Completer<void>? gate;
  final List<String> ubus;
  final List<String>? configs;
  final bool listThrows;
  int ubusCalls = 0;

  @override
  Future<List<String>> listUbusObjects(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? pattern,
    BuildContext? context,
  }) async {
    ubusCalls++;
    await gate?.future;
    return ubus;
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
    if (object == 'file' && method == 'list') {
      if (listThrows) throw Exception('file list denied');
      return [
        0,
        {
          'entries': [
            for (final c in configs ?? const <String>[]) {'name': c},
          ],
        },
      ];
    }
    return [4];
  }
}

Future<DashboardController> _controller(
  RealApiService api, {
  void Function()? onNotify,
}) async {
  final routers = RouterService();
  final router = model.Router(
    id: 'r1',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: 'x',
    useHttps: false,
  );
  await routers.addRouter(router);
  await routers.selectRouter(router.id);
  final c = DashboardController(
    apiServiceRef: () => api,
    authServiceRef: () => _Auth(),
    routerServiceRef: () => routers,
    secureStorageServiceRef: () => SecureStorageService(),
    throughputControllerRef: () => null,
    dashboardPreferencesRef: () => DashboardPreferences(),
    reviewerModeRef: () => false,
    tryAutoLogin: ({bool force = false, bool fetchDashboard = true}) async =>
        true,
    fetchPublicIps: () async {},
    setPublicIps: (v4, v6) {},
    setConnectionStatus: (status) {},
    startThroughputTimer: () {},
    processDhcpLeases: (raw) => raw,
    notifyListeners: () => onNotify?.call(),
  );
  c.setCapabilitiesForTesting(_caps().copyWith(routerId: router.id));
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('installed features are fresh after', () {
    Future<AppState> appWith(List<String> ubus) async {
      final app = AppState.instance;
      app.setApiServiceForTesting(_RouterApi(ubus: ubus));
      app.setAuthServiceForTesting(_Auth());
      final router = model.Router(
        id: 'r1',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'x',
        useHttps: false,
      );
      await app.routerService?.addRouter(router);
      await app.routerService?.selectRouter(router.id);
      app.setCapabilitiesForTesting(_caps().copyWith(routerId: 'r1'));
      return app;
    }

    test('app resume', () async {
      final app = await appWith(['system', 'fxs']);
      await app.handleAppResume();
      await pumpEventQueue();
      expect(app.capabilities!.installedUbus, {'system', 'fxs'});
    });

    test('forced dashboard fetch', () async {
      final app = await appWith(['system', 'luci.bandix']);
      await app.fetchDashboardData(force: true);
      await pumpEventQueue();
      expect(app.capabilities!.installedUbus, {'system', 'luci.bandix'});
    });
  });

  group('refreshInstalledFeatures', () {
    test('fills sets from router', () async {
      final c = await _controller(
        _RouterApi(ubus: ['system', 'fxs'], configs: ['network', 'passwall2']),
      );
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedUbus, {'system', 'fxs'});
      expect(c.capabilities!.installedConfigs, {'network', 'passwall2'});
    });

    test('keeps empty set when file list throws', () async {
      final c = await _controller(
        _RouterApi(ubus: ['system'], listThrows: true),
      );
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedUbus, {'system'});
      expect(c.capabilities!.installedConfigs, isEmpty);
    });

    test('drops result when caps changed during refresh', () async {
      final gate = Completer<void>();
      final c = await _controller(_RouterApi(ubus: ['fxs'], gate: gate));
      final pending = c.refreshInstalledFeatures();
      final newer = _caps().copyWith(routerId: 'r1', boardName: 'newer');
      c.setCapabilitiesForTesting(newer);
      gate.complete();
      await pending;
      expect(identical(c.capabilities, newer), isTrue);
    });

    test('skips refresh when caps belong to another router', () async {
      final c = await _controller(_RouterApi(ubus: ['fxs']));
      c.setCapabilitiesForTesting(_caps().copyWith(routerId: 'old'));
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedUbus, isEmpty);
    });

    test('keeps previous configs when file list throws', () async {
      final c = await _controller(_RouterApi(ubus: ['fxs'], listThrows: true));
      c.setCapabilitiesForTesting(
        _caps(installedConfigs: {'sqm'}).copyWith(routerId: 'r1'),
      );
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedConfigs, {'sqm'});
      expect(c.capabilities!.installedUbus, {'fxs'});
    });

    test('keeps previous ubus set when ubus list returns nothing', () async {
      final c = await _controller(_RouterApi(configs: ['network']));
      c.setCapabilitiesForTesting(
        _caps(installedUbus: {'fxs'}).copyWith(routerId: 'r1'),
      );
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedUbus, {'fxs'});
    });

    test('concurrent refreshes share one request', () async {
      final gate = Completer<void>();
      final api = _RouterApi(ubus: ['fxs'], gate: gate);
      final c = await _controller(api);
      final a = c.refreshInstalledFeatures();
      final b = c.refreshInstalledFeatures();
      gate.complete();
      await Future.wait([a, b]);
      expect(api.ubusCalls, 1);
      expect(c.capabilities!.installedUbus, {'fxs'});
    });

    test('does not notify when nothing changed', () async {
      var notifies = 0;
      final c = await _controller(
        _RouterApi(ubus: ['fxs'], configs: ['sqm']),
        onNotify: () => notifies++,
      );
      c.setCapabilitiesForTesting(
        _caps(
          installedUbus: {'fxs'},
          installedConfigs: {'sqm'},
        ).copyWith(routerId: 'r1'),
      );
      notifies = 0;
      await c.refreshInstalledFeatures();
      expect(notifies, 0);
    });

    test('does not cache caps that are not RPC complete', () async {
      final c = await _controller(_RouterApi(ubus: ['fxs']));
      c.setCapabilitiesForTesting(
        _caps(ubusObjects: {'system'}).copyWith(routerId: 'r1'),
      );
      await c.refreshInstalledFeatures();
      expect(c.capabilities!.installedUbus, {'fxs'});
      expect(
        await SecureStorageService().readValue('router_capabilities_r1'),
        isNull,
      );
    });

    test('dashboard probes during a refresh do not discard it', () async {
      final gate = Completer<void>();
      final c = await _controller(
        _RouterApi(ubus: ['system', 'fxs'], configs: ['sqm'], gate: gate),
      );
      final cached = RouterCapabilities.mock().copyWith(
        routerId: 'r1',
        probedAt: DateTime.now(),
      );
      await SecureStorageService().writeValue(
        'router_capabilities_r1',
        jsonEncode(cached.toJson()),
      );
      await c.probeRouterCapabilities();
      await c.probeRouterCapabilities();
      gate.complete();
      await pumpEventQueue();
      expect(c.capabilities!.installedUbus, {'system', 'fxs'});
      expect(c.capabilities!.installedConfigs, {'sqm'});
    });

    test('cache-hit probe re-checks installed features', () async {
      final c = await _controller(_RouterApi(ubus: ['system', 'fxs']));
      final cached = RouterCapabilities.mock().copyWith(
        routerId: 'r1',
        probedAt: DateTime.now(),
      );
      await SecureStorageService().writeValue(
        'router_capabilities_r1',
        jsonEncode(cached.toJson()),
      );
      await c.probeRouterCapabilities();
      await pumpEventQueue();
      expect(c.capabilities!.installedUbus, {'system', 'fxs'});
    });
  });

  test('registry hides phone and bandix on plain OpenWrt', () {
    final caps = _caps(
      installedUbus: {'system', 'uci', 'file', 'network.interface'},
      installedConfigs: {'network', 'dhcp'},
    );
    final ids = LuciModuleRegistry.instance
        .enabledModulesFor(caps)
        .map((m) => m.id)
        .toSet();
    for (final hidden in [
      'noobwrt_phone',
      'noobwrt_bandix',
      'noobwrt_passwall2',
      'noobwrt_modem',
      'adguard_home',
      'sqm',
    ]) {
      expect(ids, isNot(contains(hidden)), reason: hidden);
    }
    expect(ids, containsAll(['interfaces', 'noobwrt_tools']));
  });

  test('Passwall 1 shows on its own config, Passwall 2 stays hidden', () {
    final caps = _caps(
      installedUbus: {'system'},
      installedConfigs: {'network', 'passwall'},
    );
    final ids = LuciModuleRegistry.instance
        .enabledModulesFor(caps)
        .map((m) => m.id)
        .toSet();
    expect(ids, contains('noobwrt_passwall'));
    expect(ids, isNot(contains('noobwrt_passwall2')));
  });

  test('older Passwall keeps the node in tcp_node', () {
    const info = PasswallInfo(
      {'enabled': '1', 'tcp_node': 'b'},
      [
        {'.name': 'a', 'remarks': 'A'},
        {'.name': 'b', 'remarks': 'B'},
      ],
      true,
    );
    expect(info.nodeKey, 'tcp_node');
    expect(PasswallInfo.nodeName(info.currentNode!), 'B');
    expect(const PasswallInfo({'node': 'a'}, [], null).nodeKey, 'node');
  });

  group('LuciModule.isAvailableOn', () {
    test('shows everything when caps null', () {
      expect(_Fake(ubus: {'luci.bandix'}).isAvailableOn(null), isTrue);
    });

    test('shows everything when probe failed', () {
      expect(
        _Fake(
          ubus: {'luci.bandix'},
        ).isAvailableOn(RouterCapabilities.conservative('r')),
        isTrue,
      );
    });

    test('shows everything when installedUbus empty', () {
      expect(_Fake(ubus: {'luci.bandix'}).isAvailableOn(_caps()), isTrue);
    });

    test('hides module whose ubus object is missing', () {
      final caps = _caps(installedUbus: {'system', 'fxs'});
      expect(_Fake(ubus: {'luci.bandix'}).isAvailableOn(caps), isFalse);
    });

    test('shows module whose ubus object is present', () {
      final caps = _caps(installedUbus: {'system', 'fxs'});
      expect(_Fake(ubus: {'fxs'}).isAvailableOn(caps), isTrue);
    });

    test('ignores wildcard ubusObjects', () {
      final caps = _caps(ubusObjects: {'*'}, installedUbus: {'system'});
      expect(_Fake(ubus: {'fxs'}).isAvailableOn(caps), isFalse);
    });

    test('hides module whose config is missing', () {
      final caps = _caps(
        installedUbus: {'system'},
        installedConfigs: {'network'},
      );
      expect(_Fake(configs: {'passwall2'}).isAvailableOn(caps), isFalse);
    });

    test('skips config check when config listing empty', () {
      final caps = _caps(installedUbus: {'system'});
      expect(_Fake(configs: {'passwall2'}).isAvailableOn(caps), isTrue);
    });
  });

  group('RouterCapabilities installed sets', () {
    test('old cache JSON loads with empty sets', () {
      final json =
          _caps(installedUbus: {'fxs'}, installedConfigs: {'sqm'}).toJson()
            ..remove('installedUbus')
            ..remove('installedConfigs');
      final caps = RouterCapabilities.fromJson(json);
      expect(caps.installedUbus, isEmpty);
      expect(caps.installedConfigs, isEmpty);
      expect(caps.probeFailed, isFalse);
    });

    test('round-trips installed sets through JSON', () {
      final caps = RouterCapabilities.fromJson(
        _caps(
          installedUbus: {'fxs', 'luci.bandix'},
          installedConfigs: {'sqm'},
        ).toJson(),
      );
      expect(caps.installedUbus, {'fxs', 'luci.bandix'});
      expect(caps.installedConfigs, {'sqm'});
    });

    test('copyWith replaces installed sets', () {
      final caps = _caps().copyWith(
        installedUbus: {'fxs'},
        installedConfigs: {'sqm'},
      );
      expect(caps.installedUbus, {'fxs'});
      expect(caps.installedConfigs, {'sqm'});
    });
  });
}
