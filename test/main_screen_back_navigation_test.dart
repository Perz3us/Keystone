// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  setUp(() => HomePrefsStore.instance.value = const HomePrefs(flow: false));

  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  group('MainScreen Back Button & Exit Confirmation', () {
    setUp(() async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.markReviewerNoticeShown();
    });

    testWidgets(
      'Pressing back on a secondary tab returns to Dashboard tab without closing app',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MainScreen(initialTab: 3)),
          ),
        );
        await tester.pumpAndSettle();

        final popHandled = await tester.binding.handlePopRoute();
        expect(popHandled, isTrue);
        await tester.pumpAndSettle();

        expect(find.text('Exit Keystone?'), findsNothing);
      },
    );

    testWidgets(
      'Pressing back on Dashboard displays Exit Confirmation Dialog and Cancel dismisses it',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MainScreen(initialTab: 0)),
          ),
        );
        await tester.pumpAndSettle();

        final popHandled = await tester.binding.handlePopRoute();
        expect(popHandled, isTrue);
        await tester.pumpAndSettle();

        expect(find.text('Exit Keystone?'), findsOneWidget);
        expect(
          find.text('Are you sure you want to exit the application?'),
          findsOneWidget,
        );
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Exit'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.text('Exit Keystone?'), findsNothing);
      },
    );

    testWidgets(
      'Tab navigation history pops through visited tabs before showing exit dialog',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(home: MainScreen(initialTab: 0)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Devices').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Wi-Fi').first);
        await tester.pumpAndSettle();

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Exit Keystone?'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Exit Keystone?'), findsNothing);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.text('Exit Keystone?'), findsOneWidget);
      },
    );
  });
}
