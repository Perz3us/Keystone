import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('colour tokens match the design', () {
    expect(KeystoneColors.light.bg, const Color(0xFFF5F7F9));
    expect(KeystoneColors.dark.bg, const Color(0xFF0A0D12));
    expect(KeystoneColors.light.ac, const Color(0xFF276ED2));
    expect(KeystoneColors.dark.bad, const Color(0xFFF2716A));
  });

  test('lerp reaches the other theme', () {
    expect(
      KeystoneColors.light.lerp(KeystoneColors.dark, 1).tx,
      KeystoneColors.dark.tx,
    );
  });

  testWidgets('both themes carry the tokens', (tester) async {
    KeystoneColors? light;
    KeystoneColors? dark;
    await tester.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: Builder(
          builder: (c) {
            light = Theme.of(c).extension<KeystoneColors>();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Builder(
          builder: (c) {
            dark = Theme.of(c).extension<KeystoneColors>();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(dark!.bg, KeystoneColors.dark.bg);
  });

  test('type scale', () {
    final h = KeystoneType.headline(Colors.black);
    expect(h.fontSize, 32);
    expect(h.fontFamily, contains('SchibstedGrotesk'));
    expect(KeystoneType.body(Colors.black).fontSize, 16);
    expect(
      KeystoneType.address(Colors.black).fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });
}
