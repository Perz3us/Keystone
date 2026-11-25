// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/adguard_top_lists_bottom_sheet.dart';

Widget buildTestApp({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockStats10 = AdGuardStats(
    numDnsQueries: 50000,
    numBlockedFiltering: 12000,
    numReplacedSafebrowsing: 0,
    numReplacedSafesearch: 0,
    numReplacedParental: 0,
    avgProcessingTime: 0.02,
    topQueriedDomains: List.generate(
      8,
      (i) => AdGuardTopItem(identifier: 'queried$i.com', count: 1000 - i * 50),
    ),
    topBlockedDomains: List.generate(
      10,
      (i) => AdGuardTopItem(identifier: 'blocked$i.net', count: 500 - i * 20),
    ),
    topClients: List.generate(
      6,
      (i) => AdGuardTopItem(
        identifier: '192.168.1.${10 + i}',
        count: 800 - i * 30,
      ),
    ),
    dnsQueriesTrend: const [],
    blockedFilteringTrend: const [],
    blockRatePercentage: 24.0,
  );

  group('AdGuardTopListsCard & AdGuardTopListsBottomSheet', () {
    testWidgets('Bottom sheet search field filters domains dynamically', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildTestApp(
          child: AdGuardTopListsBottomSheet(
            stats: mockStats10,
            initialTabIndex: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsOneWidget);
      expect(find.text('blocked7.net'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('agh_top_lists_sheet_search_field')),
        'blocked7',
      );
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsNothing);
      expect(find.text('blocked7.net'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      expect(find.text('blocked0.net'), findsOneWidget);
    });

    testWidgets('Close button dismisses the bottom sheet', (tester) async {
      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  AdGuardTopListsBottomSheet.show(context, stats: mockStats10),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('agh_top_lists_bottom_sheet')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('agh_top_lists_sheet_close_button')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('agh_top_lists_bottom_sheet')), findsNothing);
    });
  });
}
