// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await AppState.instance.initializationFuture;
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Startup Theme & Preferences Pre-Hydration', () {
    test(
      'AppState.preHydrate pre-populates dynamic theme from SharedPreferences',
      () async {
        SharedPreferences.setMockInitialValues({
          'appThemePalette': 'dynamicTheme',
          'useDynamicTheme': true,
          'themeMode': 'dark',
          'app_locale': 'pt_BR',
        });

        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(appState.themeMode, equals(ThemeMode.dark));
        expect(appState.locale, equals(const Locale('pt', 'BR')));
      },
    );

    test(
      'AppState.preHydrate restores Keystone Amber when configured',
      () async {
        SharedPreferences.setMockInitialValues({
          'appThemePalette': 'amber',
          'useDynamicTheme': false,
          'themeMode': 'light',
          'app_locale': 'en',
        });

        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.amber));
        expect(appState.useDynamicTheme, isFalse);
        expect(appState.themeMode, equals(ThemeMode.light));
        expect(appState.locale, equals(const Locale('en')));
      },
    );

    test(
      'AppState.preHydrate migrates legacy palette from SecureStorageService when SharedPreferences is empty',
      () async {
        SharedPreferences.setMockInitialValues({});
        final secureStorage = SecureStorageService();
        await secureStorage.writeValue('appThemePalette', 'dynamicTheme');
        await secureStorage.writeValue('themeMode', 'dark');
        await secureStorage.writeValue('app_locale', 'zh');

        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(appState.themeMode, equals(ThemeMode.dark));
        expect(appState.locale, equals(const Locale('zh')));

        expect(prefs.getString('appThemePalette'), equals('dynamicTheme'));
        expect(prefs.getBool('useDynamicTheme'), isTrue);
        expect(prefs.getString('themeMode'), equals('dark'));
        expect(prefs.getString('app_locale'), equals('zh'));
      },
    );

    test(
      'setThemePalette persists to both memory and SharedPreferences synchronously',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        await appState.setThemePalette(AppThemePalette.dynamicTheme);

        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
        expect(appState.useDynamicTheme, isTrue);
        expect(prefs.getString('appThemePalette'), equals('dynamicTheme'));
        expect(prefs.getBool('useDynamicTheme'), isTrue);
      },
    );

    test(
      'Pre-hydrated dynamic palette builds Material You theme without amber accents on Frame 1',
      () async {
        SharedPreferences.setMockInitialValues({
          'appThemePalette': 'dynamicTheme',
          'useDynamicTheme': true,
        });
        final prefs = await SharedPreferences.getInstance();
        await AppState.preHydrate(prefs: prefs);

        final appState = AppState.instance;
        expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

        final lightTheme = KeystoneTheme.buildLightTheme(
          dynamicColorScheme: KeystoneTheme.fallbackDynamicLight,
          palette: appState.themePalette,
        );
        final darkTheme = KeystoneTheme.buildDarkTheme(
          dynamicColorScheme: KeystoneTheme.fallbackDynamicDark,
          palette: appState.themePalette,
        );

        expect(
          lightTheme.colorScheme.primary,
          isNot(equals(KeystoneTheme.amberPrimaryLight)),
        );
        expect(
          darkTheme.colorScheme.primary,
          isNot(equals(KeystoneTheme.amberPrimaryDark)),
        );
      },
    );
  });
}
