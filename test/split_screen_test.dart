// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui' show DisplayFeature, DisplayFeatureType, DisplayFeatureState;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/breakpoints.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

void main() {
  setUp(() {
    SelfDeviceGuard.setMockLocalAddresses({
      '192.168.1.50',
      '00:11:22:33:44:55',
    });
  });

  tearDown(() {
    SelfDeviceGuard.setMockLocalAddresses(null);
  });

  group('KsBreakpoints Multi-Window & Freeform Sizing', () {
    testWidgets('Evaluates on narrow phone split-view (360x360)', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool isTabletResult;
      late bool isExpandedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              isTabletResult = KsBreakpoints.isTablet(context);
              isExpandedResult = KsBreakpoints.isExpanded(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isTabletResult, isFalse);
      expect(isExpandedResult, isFalse);
    });

    testWidgets(
      'Correctly prevents vertical rail collapse in short landscape split-screen (720x340)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(720, 340);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = KsBreakpoints.isTablet(context);
                isExpandedResult = KsBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isFalse);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Activates tablet mode only when both shortestSide >= 600 and height >= 400',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = KsBreakpoints.isTablet(context);
                isExpandedResult = KsBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isFalse);
      },
    );

    testWidgets(
      'Preserves phone mode on Pixel 6 Pro and high-DPI phones in portrait and landscape',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(411, 891);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletPortrait;
        late bool isTabletLandscape;
        late bool isTabletDensePortrait;
        late bool isTabletDenseLandscape;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletPortrait = KsBreakpoints.isTablet(context);
                return const SizedBox();
              },
            ),
          ),
        );

        tester.view.physicalSize = const Size(891, 411);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletLandscape = KsBreakpoints.isTablet(context);
                return const SizedBox();
              },
            ),
          ),
        );

        tester.view.physicalSize = const Size(485, 1040);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletDensePortrait = KsBreakpoints.isTablet(context);
                return const SizedBox();
              },
            ),
          ),
        );

        tester.view.physicalSize = const Size(1040, 485);
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletDenseLandscape = KsBreakpoints.isTablet(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletPortrait, isFalse);
        expect(isTabletLandscape, isFalse);
        expect(isTabletDensePortrait, isFalse);
        expect(isTabletDenseLandscape, isFalse);
      },
    );

    testWidgets(
      'Activates expanded layout on wide tablet/desktop viewports (1280x800)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late bool isTabletResult;
        late bool isExpandedResult;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                isTabletResult = KsBreakpoints.isTablet(context);
                isExpandedResult = KsBreakpoints.isExpanded(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(isTabletResult, isTrue);
        expect(isExpandedResult, isTrue);
      },
    );

    testWidgets(
      'Detects Apple Duo / dual-screen spanned mode and enables tablet layout',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1350, 900);
        tester.view.devicePixelRatio = 1.0;
        tester.view.displayFeatures = const [
          DisplayFeature(
            bounds: Rect.fromLTWH(660, 0, 30, 900),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureFlat,
          ),
        ];
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetDisplayFeatures);

        late bool hasHinge;
        late bool isSpanned;
        late bool isTablet;
        late Rect? hingeBounds;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                hasHinge = KsBreakpoints.hasHinge(context);
                isSpanned = KsBreakpoints.isDualScreenSpanned(context);
                isTablet = KsBreakpoints.isTablet(context);
                hingeBounds = KsBreakpoints.getHingeBounds(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(hasHinge, isTrue);
        expect(isSpanned, isTrue);
        expect(isTablet, isTrue);
        expect(hingeBounds, const Rect.fromLTWH(660, 0, 30, 900));
      },
    );
  });

  group('Dialog Responsive Viewport Resilience', () {
    testWidgets(
      'BanWirelessClientDialog renders without overflow in narrow 320x500 popup view',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 500);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => BanWirelessClientDialog(
                        macAddress: '11:22:33:44:55:66',
                        displayName: 'Galaxy-S24-Ultra',
                        onBanConfirmed: (sec) async {},
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(BanWirelessClientDialog), findsOneWidget);
        expect(find.text('Block Galaxy-S24-Ultra'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Accessibility Large Font Scaling & Clamping', () {
    testWidgets(
      'AddStaticLeaseDialog renders without overflow at 1.45x maximum clamped font scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => const AddStaticLeaseDialog(),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AddStaticLeaseDialog), findsOneWidget);
        expect(find.text('Give a fixed address'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'BanWirelessClientDialog renders without overflow at 1.45x maximum clamped font scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (ctx) => BanWirelessClientDialog(
                          macAddress: '11:22:33:44:55:66',
                          displayName: 'Galaxy-S24-Ultra',
                          onBanConfirmed: (sec) async {},
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(BanWirelessClientDialog), findsOneWidget);
        expect(find.text('Block Galaxy-S24-Ultra'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'OsPlatformIntegration.showFileDownloadedPrompt renders on 320x480 at 1.45x scale',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final dummyResult = FileSaveResult(
          filePath:
              '/storage/emulated/0/Download/backup-openwrt-2026-09-28.tar.gz',
          isPublicDownloads: true,
          storageMethodLabel: 'Public Downloads Folder',
        );

        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) {
              final mediaQuery = MediaQuery.of(context);
              final clampedTextScaler = mediaQuery.textScaler.clamp(
                minScaleFactor: 0.85,
                maxScaleFactor: 1.45,
              );
              return MediaQuery(
                data: mediaQuery.copyWith(textScaler: clampedTextScaler),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.45)),
              child: Builder(
                builder: (context) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      OsPlatformIntegration.showFileDownloadedPrompt(
                        context,
                        dummyResult,
                        title: 'Backup saved',
                        fileLabel: 'Backup Path',
                        icon: Icons.check_circle_outline,
                        accentColor: Colors.teal,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              SystemChannels.platform,
              (MethodCall methodCall) async => null,
            );
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.text('Backup saved'), findsOneWidget);
        expect(find.text('Public Downloads Folder'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
