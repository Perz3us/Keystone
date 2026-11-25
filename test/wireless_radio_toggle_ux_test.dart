// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('Wireless Radio & Interface Toggle UX', () {
    test(
      'AppState toggleWirelessRadio synchronously updates in-memory dashboardData and invalidates fetches',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_radio_toggle',
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
          'uciWirelessConfig': <String, dynamic>{
            'radio0': <String, dynamic>{
              'disabled': '0',
              'type': 'mac80211',
              'channel': '36',
            },
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Home-5G',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'disabled': false,
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {'ssid': 'Home-5G', 'mode': 'ap'},
                },
              ],
            },
          },
        });

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('0'),
        );
        expect(appState.dashboardData!['wireless']['radio0']['up'], isTrue);

        final offOk = await appState.toggleWirelessRadio('radio0', false);
        expect(offOk, isTrue);

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('1'),
        );
        expect(appState.dashboardData!['wireless']['radio0']['up'], isFalse);
        expect(
          appState.dashboardData!['wireless']['radio0']['disabled'],
          isTrue,
        );

        final onOk = await appState.toggleWirelessRadio('radio0', true);
        expect(onOk, isTrue);

        expect(
          appState.dashboardData!['uciWirelessConfig']['radio0']['disabled'],
          equals('0'),
        );
        expect(appState.dashboardData!['wireless']['radio0']['up'], isTrue);
        expect(
          appState.dashboardData!['wireless']['radio0']['disabled'],
          isFalse,
        );
      },
    );

    test(
      'AppState setSsidEnabled synchronously updates in-memory dashboardData and invalidates fetches',
      () async {
        final appState = AppState.instance;
        final testRouter = model.Router(
          id: 'test_router_ssid_toggle',
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
          'uciWirelessConfig': <String, dynamic>{
            'wifinet0': <String, dynamic>{
              'device': 'radio0',
              'mode': 'ap',
              'ssid': 'Home-Main',
              'disabled': '0',
            },
          },
          'wireless': <String, dynamic>{
            'radio0': <String, dynamic>{
              'up': true,
              'interfaces': [
                {
                  'section': 'wifinet0',
                  'ifname': 'wlan0',
                  'config': {'ssid': 'Home-Main', 'disabled': '0'},
                },
              ],
            },
          },
        });

        final disableOk = await appState.setSsidEnabled('wifinet0', false);
        expect(disableOk, isTrue);
        expect(
          appState.dashboardData!['uciWirelessConfig']['wifinet0']['disabled'],
          equals('1'),
        );

        final enableOk = await appState.setSsidEnabled('wifinet0', true);
        expect(enableOk, isTrue);
        expect(
          appState.dashboardData!['uciWirelessConfig']['wifinet0']['disabled'],
          equals('0'),
        );
      },
    );
  });
}
