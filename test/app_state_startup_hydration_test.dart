// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  group('AppState Startup Hydration', () {
    test('AppState.instance.initializationFuture completes', () async {
      final appState = AppState.instance;
      await appState.initializationFuture;
      expect(appState.themeMode, isNotNull);
      expect(appState.themePalette, isNotNull);
    });

    test(
      'SessionController loading methods support notify=false without notifying listeners',
      () async {
        final appState = AppState.instance;
        int notificationCount = 0;
        void listener() {
          notificationCount++;
        }

        appState.addListener(listener);

        await appState.loadRouters(notify: false);
        expect(notificationCount, equals(0));

        await appState.loadRouters(notify: true);
        expect(notificationCount, equals(1));

        appState.removeListener(listener);
      },
    );
  });
}
