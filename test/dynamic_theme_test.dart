// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KeystoneTheme Builder', () {
    test(
      'buildLightTheme with default palette produces eye-soothing Keystone Indigo theme',
      () {
        final theme = KeystoneTheme.buildLightTheme(dynamicColorScheme: null);

        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, KeystoneTheme.amberPrimaryLight);
        expect(
          theme.scaffoldBackgroundColor,
          KeystoneTheme.neutralLightScaffold,
        );
        expect(theme.cardTheme.color, KeystoneTheme.neutralLightSurface);
        expect(theme.cardTheme.elevation, 0);

        final onPrimaryLum = theme.colorScheme.onPrimaryContainer
            .computeLuminance();
        final primaryContainerLum = theme.colorScheme.primaryContainer
            .computeLuminance();
        final primaryRatio = (primaryContainerLum > onPrimaryLum)
            ? (primaryContainerLum + 0.05) / (onPrimaryLum + 0.05)
            : (onPrimaryLum + 0.05) / (primaryContainerLum + 0.05);
        expect(primaryRatio, greaterThan(7.0));

        final onSecondaryLum = theme.colorScheme.onSecondaryContainer
            .computeLuminance();
        final secondaryContainerLum = theme.colorScheme.secondaryContainer
            .computeLuminance();
        final secondaryRatio = (secondaryContainerLum > onSecondaryLum)
            ? (secondaryContainerLum + 0.05) / (onSecondaryLum + 0.05)
            : (onSecondaryLum + 0.05) / (secondaryContainerLum + 0.05);
        expect(secondaryRatio, greaterThan(7.0));
      },
    );

    test(
      'buildDarkTheme with default palette produces eye-soothing neutral charcoal amber theme',
      () {
        final theme = KeystoneTheme.buildDarkTheme(dynamicColorScheme: null);

        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.primary, KeystoneTheme.amberPrimaryDark);
        expect(
          theme.scaffoldBackgroundColor,
          KeystoneTheme.neutralDarkScaffold,
        );
        expect(theme.cardTheme.color, KeystoneTheme.neutralDarkSurface);
        expect(theme.cardTheme.elevation, 0);

        final onPrimaryLum = theme.colorScheme.onPrimaryContainer
            .computeLuminance();
        final primaryContainerLum = theme.colorScheme.primaryContainer
            .computeLuminance();
        final primaryRatio = (onPrimaryLum > primaryContainerLum)
            ? (onPrimaryLum + 0.05) / (primaryContainerLum + 0.05)
            : (primaryContainerLum + 0.05) / (onPrimaryLum + 0.05);
        expect(primaryRatio, greaterThan(7.0));

        final onSecondaryLum = theme.colorScheme.onSecondaryContainer
            .computeLuminance();
        final secondaryContainerLum = theme.colorScheme.secondaryContainer
            .computeLuminance();
        final secondaryRatio = (onSecondaryLum > secondaryContainerLum)
            ? (onSecondaryLum + 0.05) / (secondaryContainerLum + 0.05)
            : (secondaryContainerLum + 0.05) / (onSecondaryLum + 0.05);
        expect(secondaryRatio, greaterThan(7.0));
      },
    );

    test(
      'AppThemePalette contains strictly Keystone Indigo and Material You',
      () {
        expect(AppThemePalette.values, [
          AppThemePalette.amber,
          AppThemePalette.dynamicTheme,
        ]);
        expect(AppThemePalette.amber.label, 'Keystone Indigo');
        expect(AppThemePalette.dynamicTheme.label, 'Material You');
      },
    );

    test(
      'buildLightTheme with dynamicColorScheme applies Material You palette',
      () {
        const dynamicPrimary = Color(0xFF006C4C);
        final dynamicScheme = ColorScheme.fromSeed(
          seedColor: dynamicPrimary,
          brightness: Brightness.light,
        );

        final theme = KeystoneTheme.buildLightTheme(
          dynamicColorScheme: dynamicScheme,
          palette: AppThemePalette.dynamicTheme,
        );

        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.primary, dynamicScheme.primary);
        expect(
          theme.scaffoldBackgroundColor,
          dynamicScheme.surfaceContainerLowest,
        );
        expect(theme.cardTheme.color, dynamicScheme.surface);
        expect(
          theme.appBarTheme.titleTextStyle?.color,
          dynamicScheme.onSurface,
        );
      },
    );

    test(
      'buildDarkTheme with dynamicColorScheme applies Material You dark palette',
      () {
        const dynamicPrimary = Color(0xFF80D5AB);
        final dynamicScheme = ColorScheme.fromSeed(
          seedColor: dynamicPrimary,
          brightness: Brightness.dark,
        );

        final theme = KeystoneTheme.buildDarkTheme(
          dynamicColorScheme: dynamicScheme,
          palette: AppThemePalette.dynamicTheme,
        );

        expect(theme.brightness, Brightness.dark);
        expect(theme.colorScheme.primary, dynamicScheme.primary);
        expect(
          theme.scaffoldBackgroundColor,
          dynamicScheme.surfaceContainerLowest,
        );
        expect(theme.cardTheme.color, dynamicScheme.surfaceContainer);
        expect(
          theme.appBarTheme.titleTextStyle?.color,
          dynamicScheme.onSurface,
        );
      },
    );

    test(
      'fallbackDynamicLight and fallbackDynamicDark are valid and non-null',
      () {
        expect(KeystoneTheme.fallbackDynamicLight.brightness, Brightness.light);
        expect(KeystoneTheme.fallbackDynamicDark.brightness, Brightness.dark);
      },
    );
  });

  group('SessionController Dynamic Theming & Palette State', () {
    late SecureStorageService secureStorage;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      secureStorage = SecureStorageService();
    });

    test('themePalette defaults to amber and persists', () async {
      int notifyCount = 0;
      final controller = SessionController(
        apiServiceRef: () => null,
        authServiceRef: () => null,
        routerServiceRef: () => null,
        secureStorageServiceRef: () => secureStorage,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => null,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) async {},
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () => notifyCount++,
      );

      expect(controller.themePalette, AppThemePalette.amber);
      expect(controller.useDynamicTheme, isFalse);

      await controller.setThemePalette(AppThemePalette.dynamicTheme);
      expect(controller.themePalette, AppThemePalette.dynamicTheme);
      expect(controller.useDynamicTheme, isTrue);
      expect(notifyCount, 1);

      final stored = await secureStorage.readValue('appThemePalette');
      expect(stored, 'dynamicTheme');

      await controller.setThemePalette(AppThemePalette.amber);
      expect(controller.themePalette, AppThemePalette.amber);
      expect(controller.useDynamicTheme, isFalse);

      await secureStorage.writeValue('appThemePalette', 'emerald');
      final legacyController = SessionController(
        apiServiceRef: () => null,
        authServiceRef: () => null,
        routerServiceRef: () => null,
        secureStorageServiceRef: () => secureStorage,
        httpClientManagerRef: () => HttpClientManager(),
        dashboardControllerRef: () => null,
        cancelThroughputTimer: () {},
        startThroughputTimer: () {},
        fetchDashboardData: ({bool force = false}) async {},
        initializeServices: () {},
        setLoadingState: (_) {},
        setErrorState: (_) {},
        notifyListeners: () {},
      );

      await legacyController.loadDynamicTheme();
      expect(legacyController.themePalette, AppThemePalette.amber);
      expect(legacyController.useDynamicTheme, isFalse);

      await legacyController.setDynamicTheme(true);
      expect(legacyController.themePalette, AppThemePalette.dynamicTheme);
      expect(legacyController.useDynamicTheme, isTrue);

      await legacyController.setDynamicTheme(false);
      expect(legacyController.themePalette, AppThemePalette.amber);
      expect(legacyController.useDynamicTheme, isFalse);
    });
  });
}
