// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('MoreScreen Deduping & Permanent RPC Management', () {});

  group('Permanent RPC Status in SettingsScreen', () {});

  group('DashboardScreen Banner Dismissal without Lingering Chips', () {});

  group('RPC Fix Script & Toast Localization Resilience', () {
    test('getPermissionsFixScript creates ACL file and reloads rpcd', () {
      final script = ApiService.getPermissionsFixScript();
      final aclIndex = script.indexOf(
        'cat << \'EOF\' > /usr/share/rpcd/acl.d/yet-another-luci-app.json',
      );
      final reloadIndex = script.indexOf(
        '/etc/init.d/rpcd restart 2>/dev/null || /etc/init.d/rpcd reload',
      );

      expect(aclIndex, isNonNegative);
      expect(reloadIndex, isNonNegative);

      expect(aclIndex < reloadIndex, isTrue);

      expect(script.contains('command -v apk'), isTrue);
      expect(script.contains('apk add'), isTrue);
      expect(script.contains('opkg install'), isTrue);
    });
  });
}
