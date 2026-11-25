// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/models/router_upgrade_scan.dart';
import 'package:yet_another_luci_app/modules/system_backup_upgrade/services/router_upgrade_scan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MockApiService & RouterUpgradeScanService Package Engine', () {
    test(
      'MockApiService reports APK engine and RouterUpgradeScanService detects only APK',
      () async {
        final mockApi = MockApiService();
        MockApiService.mockPackageEngine = PackageManagerEngine.apk;
        addTearDown(() {
          MockApiService.mockPackageEngine = PackageManagerEngine.opkg;
        });
        final scanService = RouterUpgradeScanService(
          apiService: mockApi,
          ipAddress: '192.168.1.1',
          sysauth: 'mock_token',
          useHttps: false,
        );

        final scan = await scanService.scan();

        expect(scan.packageManager.isKnown, isTrue);
        expect(scan.packageManager.value, equals(RouterPackageManager.apk));
        expect(
          scan.packageManager.value,
          isNot(equals(RouterPackageManager.mixed)),
        );
        expect(
          scan.packageManager.value,
          isNot(equals(RouterPackageManager.opkg)),
        );
      },
    );
  });
}
