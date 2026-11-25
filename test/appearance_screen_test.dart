import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/more/appearance_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => KeystoneType.font.value = KeystoneFont.keystone);

  Future<List<ThemeMode>> pump(WidgetTester t, {double textScale = 1}) async {
    SharedPreferences.setMockInitialValues({});
    final modes = <ThemeMode>[];
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: KeystoneFontScope(child: child!),
        ),
        home: Scaffold(
          body: AppearanceView(themeMode: ThemeMode.system, onTheme: modes.add),
        ),
      ),
    );
    await t.pumpAndSettle();
    return modes;
  }

  testWidgets('theme and font, each previewing itself', (t) async {
    final modes = await pump(t);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text("Everything's working."), findsNWidgets(3));
    expect(find.text('Keystone · the default'), findsOneWidget);
    expect(
      find.text('Text size follows your phone\'s setting.'),
      findsOneWidget,
    );
    await t.tap(find.text('Dark'));
    expect(modes, [ThemeMode.dark]);
    await t.tap(find.text('Geist · clean and technical'));
    await t.pumpAndSettle();
    expect(KeystoneType.font.value, KeystoneFont.geist);
    expect(
      (await SharedPreferences.getInstance()).getString('keystone_font'),
      'geist',
    );
  });

  testWidgets('fits at 2x text', (t) async {
    await pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });
}
