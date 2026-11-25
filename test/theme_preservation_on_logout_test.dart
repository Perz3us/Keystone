// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppState.instance.initializationFuture;
  });

  test('Theme mode and theme palette are preserved across logout', () async {
    final appState = AppState.instance;

    await appState.setThemeMode(ThemeMode.dark);
    await appState.setThemePalette(AppThemePalette.dynamicTheme);

    expect(appState.themeMode, equals(ThemeMode.dark));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
    expect(appState.useDynamicTheme, isTrue);

    await appState.logout();

    expect(appState.themeMode, equals(ThemeMode.dark));
    expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
    expect(appState.useDynamicTheme, isTrue);
  });

  test(
    'Theme mode and theme palette are preserved across reviewer mode toggles',
    () async {
      final appState = AppState.instance;

      await appState.setThemeMode(ThemeMode.light);
      await appState.setThemePalette(AppThemePalette.dynamicTheme);

      expect(appState.themeMode, equals(ThemeMode.light));
      expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

      await appState.setReviewerMode(true);
      expect(appState.themeMode, equals(ThemeMode.light));
      expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

      await appState.setReviewerMode(false);
      expect(appState.themeMode, equals(ThemeMode.light));
      expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));

      await appState.logout();
      expect(appState.themeMode, equals(ThemeMode.light));
      expect(appState.themePalette, equals(AppThemePalette.dynamicTheme));
    },
  );
}
