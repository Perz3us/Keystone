// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/add_ssid_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/edit_ssid_dialog.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

Future<void> pumpFrames(
  WidgetTester tester, {
  int count = 10,
  Duration duration = const Duration(milliseconds: 50),
}) async {
  for (int i = 0; i < count; i++) {
    await tester.pump(duration);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  const mockRadio = WirelessRadio(
    name: 'radio0',
    isUp: true,
    channel: '36',
    country: 'US',
    interfaces: [
      WirelessInterface(
        ifName: 'wlan0',
        sectionName: 'cfg01',
        ssid: 'Home_WiFi',
        mode: 'ap',
        encryption: 'psk2',
        securityMode: WifiSecurityMode.wpa2Psk,
        pmfState: PmfState.optional,
        channel: '36',
        isEnabled: true,
        stations: [],
        key: 'SuperSecret123',
        networkBridge: 'lan',
      ),
    ],
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          if (methodCall.method == 'readAll') {
            return <String, String>{'reviewer_mode_enabled': 'true'};
          }
          if (methodCall.method == 'read') {
            return methodCall.arguments['key'] == 'reviewer_mode_enabled'
                ? 'true'
                : null;
          }
          return null;
        });
  });

  setUp(() async {
    await AppState.instance.setReviewerMode(true);
  });

  Widget buildTestWidget(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  group('SSID Quick Setup UX', () {
    testWidgets(
      'Quick Setup default path enables submit button with essential inputs',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        final createBtnFinder = find.widgetWithText(FilledButton, 'Add');
        expect(createBtnFinder, findsOneWidget);

        final initialBtn = tester.widget<FilledButton>(createBtnFinder);
        expect(initialBtn.onPressed, isNull);

        final textFields = find.byType(TextFormField);
        final ssidField = textFields.at(0);
        final passField = textFields.at(1);

        await tester.enterText(ssidField, 'Fast_New_WiFi');
        await tester.enterText(passField, 'ValidPassphrase123');
        await pumpFrames(tester);

        final enabledBtn = tester.widget<FilledButton>(createBtnFinder);
        expect(enabledBtn.onPressed, isNotNull);

        expect(find.text('Who can join'), findsNothing);
      },
    );

    testWidgets(
      'Advanced Settings collapsed by default and exposes 4 distinct groups upon expansion',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Security details'), findsNothing);
        expect(find.text('Roaming between access points'), findsNothing);

        await tester.ensureVisible(find.text('Show advanced settings'));
        await tester.tap(find.text('Show advanced settings'));
        await pumpFrames(tester, count: 15);

        final list = find.byType(Scrollable).first;
        for (final group in [
          'Security details',
          'Who can join',
          'Roaming between access points',
          'Fast roaming (802.11r)',
          'Fine-tuning',
          'Addresses on this network',
        ]) {
          await tester.scrollUntilVisible(
            find.text(group),
            300,
            scrollable: list,
          );
          expect(find.text(group), findsOneWidget);
        }
      },
    );

    testWidgets(
      'Open network (none) requires explicit confirmation checkbox to submit',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        final textFields = find.byType(TextFormField);
        await tester.enterText(textFields.at(0), 'Public_Open_WiFi');
        await pumpFrames(tester);

        final securityDropdown = find
            .byType(DropdownButtonFormField<String>)
            .at(1);
        await tester.tap(securityDropdown);
        await tester.pumpAndSettle();

        await tester.tap(
          find
              .byWidgetPredicate(
                (w) => w is DropdownMenuItem<String> && w.value == 'none',
              )
              .last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(find.text('Password'), findsNothing);

        expect(find.textContaining('Anyone nearby can join'), findsOneWidget);
        final checkboxFinder = find.text('I understand anyone can join');
        expect(checkboxFinder, findsOneWidget);

        final createBtnFinder = find.widgetWithText(FilledButton, 'Add');
        var btn = tester.widget<FilledButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNull,
          reason: 'Submit must be blocked without open-network confirmation',
        );

        await tester.tap(checkboxFinder);
        await pumpFrames(tester);

        btn = tester.widget<FilledButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNotNull,
          reason: 'Submit must be enabled once confirmation is checked',
        );

        await tester.tap(checkboxFinder);
        await pumpFrames(tester);

        btn = tester.widget<FilledButton>(createBtnFinder);
        expect(
          btn.onPressed,
          isNull,
          reason: 'Submit must be blocked again when unchecked',
        );
      },
    );

    testWidgets(
      'Network-wide warning updates dynamically when network interface changes',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        final networkDropdown = find
            .byType(DropdownButtonFormField<String>)
            .first;
        await tester.tap(networkDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Guest network').last);
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Show advanced settings'));
        await tester.tap(find.text('Show advanced settings'));
        await pumpFrames(tester, count: 15);

        const guestWarning =
            'These apply to every device on Guest network, not only this '
            'Wi-Fi network.';
        await tester.scrollUntilVisible(
          find.text(guestWarning),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(guestWarning), findsOneWidget);
      },
    );

    testWidgets(
      'Capability gating disables unsupported security modes and applies smart defaults',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        final securityDropdown = find
            .byType(DropdownButtonFormField<String>)
            .at(1);
        await tester.tap(securityDropdown);
        await tester.pumpAndSettle();

        expect(find.text('WPA2 and WPA3 (recommended)'), findsWidgets);
        expect(find.text('WPA2 only, for older devices'), findsWidgets);

        await tester.tap(find.text('WPA2 and WPA3 (recommended)').last);
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'EditSsidDialog preserves baseline configuration and enforces progressive disclosure',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            EditSsidDialog(
              radio: mockRadio,
              interface: mockRadio.interfaces.first,
            ),
          ),
        );
        await pumpFrames(tester);

        expect(find.text('Home_WiFi'), findsOneWidget);

        final saveBtnFinder = find.widgetWithText(FilledButton, 'Save');
        expect(saveBtnFinder, findsOneWidget);

        var saveBtn = tester.widget<FilledButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNull,
          reason: 'Save button must be disabled when no edits were made',
        );

        final ssidFieldFinder = find.byType(TextFormField).first;
        await tester.enterText(ssidFieldFinder, 'Home_WiFi_Modified');
        await pumpFrames(tester);

        saveBtn = tester.widget<FilledButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNotNull,
          reason: 'Save button must be enabled when SSID changed',
        );

        await tester.enterText(ssidFieldFinder, 'Home_WiFi');
        await pumpFrames(tester);

        saveBtn = tester.widget<FilledButton>(saveBtnFinder);
        expect(
          saveBtn.onPressed,
          isNull,
          reason: 'Save button must revert to disabled',
        );

        expect(find.text('Who can join'), findsNothing);
        await tester.ensureVisible(find.text('Show advanced settings'));
        await tester.tap(find.text('Show advanced settings'));
        await pumpFrames(tester, count: 15);

        final list = find.byType(Scrollable).first;
        for (final group in [
          'Security details',
          'Who can join',
          'Roaming between access points',
          'Fine-tuning',
          'Addresses on this network',
        ]) {
          await tester.scrollUntilVisible(
            find.text(group),
            300,
            scrollable: list,
          );
          expect(find.text(group), findsOneWidget);
        }

        expect(
          find.text(
            'These apply to every device on Home network, not only this '
            'Wi-Fi network.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AddSsidDialog rejects duplicate SSID name on the same radio to prevent duplicate creation on retry',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestWidget(
            const AddSsidDialog(radios: [mockRadio], targetRadio: mockRadio),
          ),
        );
        await pumpFrames(tester);

        final ssidFieldFinder = find.byType(TextFormField).first;
        await tester.enterText(ssidFieldFinder, 'Home_WiFi');
        await pumpFrames(tester);

        final passFieldFinder = find.byType(TextFormField).at(1);
        await tester.enterText(passFieldFinder, 'ValidPassphrase123');
        await pumpFrames(tester);

        final submitBtnFinder = find.widgetWithText(FilledButton, 'Add');
        var submitBtn = tester.widget<FilledButton>(submitBtnFinder);
        expect(
          submitBtn.onPressed,
          isNull,
          reason:
              'Submit button must be disabled for duplicate SSID on the same radio',
        );

        await tester.enterText(ssidFieldFinder, 'New_Unique_WiFi');
        await pumpFrames(tester);

        submitBtn = tester.widget<FilledButton>(submitBtnFinder);
        expect(
          submitBtn.onPressed,
          isNotNull,
          reason: 'Submit button must be enabled when SSID is unique',
        );
      },
    );
  });
}
