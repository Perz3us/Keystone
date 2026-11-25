// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/error_words.dart';

void main() {
  setUp(() => HomePrefsStore.instance.value = const HomePrefs(flow: false));

  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('Quality & Polish Enhancements', () {
    setUp(() async {
      ActionRateLimiter.reset();
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });

    test('AppState routerBackOnline listener registration and dispatch', () {
      final appState = AppState.instance;
      bool callbackSuccess = false;
      int callbackCount = 0;

      void listener(bool success) {
        callbackSuccess = success;
        callbackCount++;
      }

      appState.addRouterBackOnlineListener(listener);
      appState.addRouterBackOnlineListener(listener);

      bool legacyCalled = false;
      appState.onRouterBackOnline = () {
        legacyCalled = true;
      };

      appState.notifyRouterBackOnlineForTesting(success: true);

      expect(callbackCount, equals(1));
      expect(callbackSuccess, isTrue);
      expect(legacyCalled, isTrue);

      appState.removeRouterBackOnlineListener(listener);
      appState.notifyRouterBackOnlineForTesting(success: false);

      expect(callbackCount, equals(1));
    });

    test('ActionRateLimiter blocks rapid subsequent calls within cooldown', () {
      const key = 'test_action';
      ActionRateLimiter.reset(key);

      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isFalse,
      );

      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isTrue,
      );
      expect(ActionRateLimiter.getSuppressionCount(key), equals(1));

      ActionRateLimiter.reset(key);
      expect(
        ActionRateLimiter.isRateLimited(
          key,
          cooldown: const Duration(milliseconds: 500),
        ),
        isFalse,
      );
    });

    testWidgets(
      'MainScreen displays connectivity banner when reconnecting or disconnected',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.reconnecting,
        );

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MainScreen(initialTab: 0)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reconnecting to router...'), findsOneWidget);

        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.disconnected,
        );
        await tester.pumpAndSettle();

        expect(find.text('Router disconnected'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);

        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.connected,
        );
        await tester.pumpAndSettle();

        expect(find.text('Router disconnected'), findsNothing);
        expect(find.text('Reconnecting to router...'), findsNothing);
      },
    );

    testWidgets(
      'MainScreen connectivity banner uses dynamic primary tokens in dynamic dark theme',
      (WidgetTester tester) async {
        final appState = AppState.instance;
        await appState.setThemePalette(AppThemePalette.dynamicTheme);
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.reconnecting,
        );

        final dynamicDarkTheme = KeystoneTheme.buildDarkTheme(
          dynamicColorScheme: KeystoneTheme.fallbackDynamicDark,
          palette: AppThemePalette.dynamicTheme,
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: dynamicDarkTheme,
              darkTheme: dynamicDarkTheme,
              themeMode: ThemeMode.dark,
              home: const MainScreen(initialTab: 0),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Reconnecting to router...'), findsOneWidget);

        final textWidget = tester.widget<Text>(
          find.text('Reconnecting to router...'),
        );
        expect(
          textWidget.style?.color,
          equals(dynamicDarkTheme.colorScheme.onPrimaryContainer),
        );

        await appState.setThemePalette(AppThemePalette.amber);
        appState.setConnectionStatusForTesting(
          RouterConnectionStatus.connected,
        );
      },
    );
  });
}
