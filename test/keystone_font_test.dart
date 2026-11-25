import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => KeystoneType.font.value = KeystoneFont.keystone);

  test('each choice changes the type everywhere', () {
    expect(KeystoneType.body(Colors.black).fontFamily, contains('Onest'));
    expect(
      KeystoneType.headline(Colors.black).fontFamily,
      contains('SchibstedGrotesk'),
    );
    KeystoneType.font.value = KeystoneFont.geist;
    expect(KeystoneType.body(Colors.black).fontFamily, contains('Geist'));
    expect(KeystoneType.headline(Colors.black).fontFamily, contains('Geist'));
    KeystoneType.font.value = KeystoneFont.system;
    expect(KeystoneType.body(Colors.black).fontFamily, isNull);
    expect(KeystoneType.body(Colors.black).fontSize, 16);
  });

  test('the choice is saved and read back', () async {
    SharedPreferences.setMockInitialValues({});
    await saveKeystoneFont(KeystoneFont.geist);
    KeystoneType.font.value = KeystoneFont.keystone;
    await loadKeystoneFont();
    expect(KeystoneType.font.value, KeystoneFont.geist);
  });

  test('an unknown saved value falls back to Keystone', () async {
    SharedPreferences.setMockInitialValues({'keystone_font': 'comic'});
    await loadKeystoneFont();
    expect(KeystoneType.font.value, KeystoneFont.keystone);
  });

  testWidgets('an open screen redraws in the new font', (t) async {
    await t.pumpWidget(
      MaterialApp(
        builder: (c, child) => KeystoneFontScope(child: child!),
        home: Builder(
          builder: (c) => Text('x', style: KeystoneType.body(c.ks.tx)),
        ),
      ),
    );
    String? family() => t.widget<Text>(find.text('x')).style?.fontFamily;
    expect(family(), contains('Onest'));
    KeystoneType.font.value = KeystoneFont.geist;
    await t.pump();
    expect(family(), contains('Geist'));
  });
}
