// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('DDNS and Async Toggle Hardening', () {
    test('DdnsOverview parses installed state and instances', () {
      final data = {
        'ddns': {
          'global': {'is_enabled': '1'},
          'myddns_ipv4': {
            '.type': 'service',
            'enabled': '1',
            'service_name': 'cloudflare.com-v4',
            'lookup_host': 'router.example.com',
            'domain': 'router.example.com',
          },
        },
      };

      final overview = DdnsOverview.fromDashboardData(
        data,
        isReviewerMode: false,
      );
      expect(overview.isInstalled, isTrue);
      expect(overview.isGlobalEnabled, isTrue);
      expect(overview.instances.length, equals(1));
      expect(overview.instances.first.name, equals('myddns_ipv4'));
      expect(overview.instances.first.enabled, isTrue);
    });

    test(
      'AppState toggleGlobalDdns updates in-memory dashboardData immediately without bounce',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ddns',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setApiServiceForTesting(MockApiService());

        appState.setDashboardDataForTesting({
          'ddns': {
            'global': {'is_enabled': '1'},
            'myddns_ipv4': {
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('1'),
        );

        final toggleOffOk = await appState.toggleGlobalDdns(false);
        expect(toggleOffOk, isTrue);
        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('0'),
        );

        final toggleOnOk = await appState.toggleGlobalDdns(true);
        expect(toggleOnOk, isTrue);
        expect(
          appState.dashboardData!['ddns']['global']['is_enabled'],
          equals('1'),
        );
      },
    );

    test(
      'AppState saveDdnsInstance and deleteDdnsInstance synchronously updates in-memory dashboardData',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ddns_save',
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'password',
          useHttps: false,
        );
        await appState.routerService?.addRouter(testRouter);
        await appState.routerService?.selectRouter(testRouter.id);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setApiServiceForTesting(MockApiService());

        appState.setDashboardDataForTesting(<String, dynamic>{
          'ddns': <String, dynamic>{
            'global': <String, dynamic>{'is_enabled': '1'},
            'myddns_ipv4': <String, dynamic>{
              '.type': 'service',
              'enabled': '1',
              'service_name': 'cloudflare.com-v4',
              'lookup_host': 'router.example.com',
              'domain': 'router.example.com',
            },
          },
        });

        const updatedInstance = DdnsInstance(
          name: 'myddns_ipv4',
          enabled: false,
          serviceName: 'cloudflare.com-v4',
          lookupHost: 'router.example.com',
          domain: 'router.example.com',
        );
        final saveOk = await appState.saveDdnsInstance(updatedInstance);
        expect(saveOk, isTrue);
        expect(
          appState.dashboardData!['ddns']['myddns_ipv4']['enabled'],
          equals('0'),
        );

        final deleteOk = await appState.deleteDdnsInstance('myddns_ipv4');
        expect(deleteOk, isTrue);
        expect(
          appState.dashboardData!['ddns'].containsKey('myddns_ipv4'),
          isFalse,
        );
      },
    );
  });
}
