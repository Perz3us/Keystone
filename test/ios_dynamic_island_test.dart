// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/screens/splash_screen.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('iOS Dynamic Island & Safe Area Verification', () {
    setUp(() async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });

    testWidgets(
      'SplashScreen respects Dynamic Island top inset without overflowing',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 59.0, bottom: 34.0);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        await tester.runAsync(() async {
          await tester.pumpWidget(
            const ProviderScope(
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: SplashScreen(),
              ),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 600));
        });

        expect(tester.takeException(), isNull);

        final appTitleFinder = find.text('Keystone');
        expect(appTitleFinder, findsOneWidget);

        final appTitleTop = tester.getTopLeft(appTitleFinder).dy;
        expect(appTitleTop, greaterThanOrEqualTo(59.0));
      },
    );

    testWidgets(
      'Compact iPhone screen (375x667) with Dynamic Type (1.4x scale) renders MainScreen without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(375, 667);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 20.0, bottom: 0.0);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        await tester.pumpWidget(
          const MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(1.4),
              size: Size(375, 667),
              padding: EdgeInsets.only(top: 20.0),
            ),
            child: ProviderScope(
              child: MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: MainScreen(initialTab: 4),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(MainScreen), findsOneWidget);
      },
    );

    testWidgets(
      'iPad Slide-Over ultra-narrow view (320x1024) adapts without overflow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 1024);
        tester.view.devicePixelRatio = 1.0;
        tester.view.padding = const FakeViewPadding(top: 24.0, bottom: 20.0);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);

        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MainScreen(initialTab: 4),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(tester.takeException(), isNull);
        expect(find.byType(MainScreen), findsOneWidget);
      },
    );
  });
}
