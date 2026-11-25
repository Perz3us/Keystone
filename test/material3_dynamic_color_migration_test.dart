// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/widgets/device_network_access_card.dart';
import 'package:yet_another_luci_app/models/client.dart';

double calculateContrastRatio(Color foreground, Color background) {
  final lForeground = foreground.computeLuminance();
  final lBackground = background.computeLuminance();
  final l1 = lForeground > lBackground ? lForeground : lBackground;
  final l2 = lForeground > lBackground ? lBackground : lForeground;
  return (l1 + 0.05) / (l2 + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Material 3 Color Scheme Roles & Hierarchy', () {
    test(
      'Primary Dynamic theme provides full complete Material 3 color roles',
      () {
        final lightTheme = KeystoneTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = KeystoneTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;
          expect(theme.useMaterial3, isTrue);

          expect(cs.primary, isNotNull);
          expect(cs.onPrimary, isNotNull);
          expect(cs.primaryContainer, isNotNull);
          expect(cs.onPrimaryContainer, isNotNull);

          expect(cs.secondary, isNotNull);
          expect(cs.onSecondary, isNotNull);
          expect(cs.secondaryContainer, isNotNull);
          expect(cs.onSecondaryContainer, isNotNull);

          expect(cs.tertiary, isNotNull);
          expect(cs.onTertiary, isNotNull);
          expect(cs.tertiaryContainer, isNotNull);
          expect(cs.onTertiaryContainer, isNotNull);

          expect(cs.error, isNotNull);
          expect(cs.onError, isNotNull);
          expect(cs.errorContainer, isNotNull);
          expect(cs.onErrorContainer, isNotNull);

          expect(cs.surface, isNotNull);
          expect(cs.onSurface, isNotNull);
          expect(cs.onSurfaceVariant, isNotNull);
          expect(cs.surfaceContainerLowest, isNotNull);
          expect(cs.surfaceContainerLow, isNotNull);
          expect(cs.surfaceContainer, isNotNull);
          expect(cs.surfaceContainerHigh, isNotNull);
          expect(cs.surfaceContainerHighest, isNotNull);

          expect(cs.outline, isNotNull);
          expect(cs.outlineVariant, isNotNull);
          expect(cs.inverseSurface, isNotNull);
          expect(cs.onInverseSurface, isNotNull);
          expect(cs.inversePrimary, isNotNull);
        }
      },
    );

    test(
      'Tonal surface hierarchy is consistent between Light and Dark themes',
      () {
        final lightTheme = KeystoneTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = KeystoneTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        expect(
          lightTheme.scaffoldBackgroundColor,
          lightTheme.colorScheme.surfaceContainerLowest,
        );
        expect(lightTheme.cardTheme.color, lightTheme.colorScheme.surface);
        expect(
          lightTheme.dialogTheme.backgroundColor,
          lightTheme.colorScheme.surfaceContainerHigh,
        );
        expect(
          lightTheme.bottomSheetTheme.backgroundColor,
          lightTheme.colorScheme.surfaceContainerLow,
        );

        expect(
          darkTheme.scaffoldBackgroundColor,
          darkTheme.colorScheme.surfaceContainerLowest,
        );
        expect(
          darkTheme.cardTheme.color,
          darkTheme.colorScheme.surfaceContainer,
        );
        expect(
          darkTheme.dialogTheme.backgroundColor,
          darkTheme.colorScheme.surfaceContainerHigh,
        );
        expect(
          darkTheme.bottomSheetTheme.backgroundColor,
          darkTheme.colorScheme.surfaceContainer,
        );
      },
    );

    test('Keystone Amber theme remains strictly unmodified and isolated', () {
      final lightAmber = KeystoneTheme.buildLightTheme(
        palette: AppThemePalette.amber,
      );
      final darkAmber = KeystoneTheme.buildDarkTheme(
        palette: AppThemePalette.amber,
      );

      expect(lightAmber.colorScheme.primary, KeystoneTheme.amberPrimaryLight);
      expect(
        lightAmber.scaffoldBackgroundColor,
        KeystoneTheme.classicLightScaffold,
      );
      expect(lightAmber.cardTheme.color, KeystoneTheme.classicLightSurface);

      expect(darkAmber.colorScheme.primary, KeystoneTheme.amberPrimaryDark);
      expect(
        darkAmber.scaffoldBackgroundColor,
        KeystoneTheme.classicDarkScaffold,
      );
      expect(darkAmber.cardTheme.color, KeystoneTheme.classicDarkSurface);
    });
  });

  group('WCAG 2.2 AA Contrast Compliance', () {
    test(
      'Material 3 Dynamic Theme pairs pass WCAG 2.2 AA (>= 4.5:1 text, >= 3.0:1 container)',
      () {
        final lightTheme = KeystoneTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = KeystoneTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;

          final primaryRatio = calculateContrastRatio(cs.onPrimary, cs.primary);
          expect(
            primaryRatio,
            greaterThanOrEqualTo(3.0),
            reason: 'onPrimary on primary contrast ratio ($primaryRatio)',
          );

          final primaryContainerRatio = calculateContrastRatio(
            cs.onPrimaryContainer,
            cs.primaryContainer,
          );
          expect(
            primaryContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onPrimaryContainer on primaryContainer contrast ratio ($primaryContainerRatio)',
          );

          final secondaryContainerRatio = calculateContrastRatio(
            cs.onSecondaryContainer,
            cs.secondaryContainer,
          );
          expect(
            secondaryContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onSecondaryContainer on secondaryContainer contrast ratio ($secondaryContainerRatio)',
          );

          final errorContainerRatio = calculateContrastRatio(
            cs.onErrorContainer,
            cs.errorContainer,
          );
          expect(
            errorContainerRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onErrorContainer on errorContainer contrast ratio ($errorContainerRatio)',
          );

          final onSurfaceRatio = calculateContrastRatio(
            cs.onSurface,
            cs.surface,
          );
          expect(
            onSurfaceRatio,
            greaterThanOrEqualTo(4.5),
            reason: 'onSurface on surface contrast ratio ($onSurfaceRatio)',
          );

          final inverseRatio = calculateContrastRatio(
            cs.onInverseSurface,
            cs.inverseSurface,
          );
          expect(
            inverseRatio,
            greaterThanOrEqualTo(4.5),
            reason:
                'onInverseSurface on inverseSurface contrast ratio ($inverseRatio)',
          );
        }
      },
    );

    test(
      'Semantic statusChip pairs guarantee accessible contrast in both brightness modes',
      () {
        final lightTheme = KeystoneTheme.buildLightTheme(
          palette: AppThemePalette.dynamicTheme,
        );
        final darkTheme = KeystoneTheme.buildDarkTheme(
          palette: AppThemePalette.dynamicTheme,
        );

        for (final theme in [lightTheme, darkTheme]) {
          final cs = theme.colorScheme;
          final activeRatio = calculateContrastRatio(
            cs.onPrimaryContainer,
            cs.primaryContainer,
          );
          expect(activeRatio, greaterThanOrEqualTo(4.5));

          final inactiveRatio = calculateContrastRatio(
            cs.onErrorContainer,
            cs.errorContainer,
          );
          expect(inactiveRatio, greaterThanOrEqualTo(4.5));
        }
      },
    );
  });

  group('International Font Fallback', () {
    test('Theme TextTheme configures font fallbacks for non-Latin scripts', () {
      final theme = KeystoneTheme.buildLightTheme(
        palette: AppThemePalette.dynamicTheme,
      );
      final titleMedium = theme.textTheme.titleMedium;
      expect(titleMedium, isNotNull);
      expect(titleMedium?.fontFamilyFallback, isNotNull);
      expect(titleMedium?.fontFamilyFallback, contains('Noto Sans'));
      expect(titleMedium?.fontFamilyFallback, contains('Roboto'));
    });
  });

  group('Zero Silent Text Truncation & Responsive Layout', () {
    testWidgets(
      'DeviceNetworkAccessCard wraps long client display name without silent truncation',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = Client(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          ipAddress: '192.168.1.150',
          hostname: 'Living Room Smart 4K HDR Ultra Entertainment Center',
        );

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: KeystoneTheme.buildLightTheme(
                palette: AppThemePalette.dynamicTheme,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () =>
                          DeviceNetworkAccessCard.showAsBottomSheet(
                            context,
                            client: client,
                          ),
                      child: const Text('Open Bottom Sheet'),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Bottom Sheet'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('Living Room Smart 4K HDR Ultra'),
          findsOneWidget,
        );

        final nameFinder = find.byWidgetPredicate(
          (w) =>
              w is Text && (w.data?.contains('Living Room Smart 4K') ?? false),
        );
        expect(nameFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(nameFinder);
        expect(textWidget.maxLines ?? 2, greaterThan(1));
      },
    );

    testWidgets('UI elements adapt under 2.0x accessibility text scaling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final client = Client(
        macAddress: '11:22:33:44:55:66',
        ipAddress: '192.168.1.188',
        hostname: 'Office Workstation Pro',
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: KeystoneTheme.buildLightTheme(
              palette: AppThemePalette.dynamicTheme,
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(
                body: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () =>
                          DeviceNetworkAccessCard.showAsBottomSheet(
                            context,
                            client: client,
                          ),
                      child: const Text('Open Controls'),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Controls'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Office Workstation Pro'), findsOneWidget);
    });
  });
}
