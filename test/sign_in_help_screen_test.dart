import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_help_screen.dart';

const _reset =
    'Press and hold the reset button on the back for about 10 seconds, '
    'until the lights flash.';
const _warning =
    'This erases all its settings, including your Wi-Fi name and password.';

Future<void> _open(WidgetTester t, {bool openReset = false}) => t.pumpWidget(
  MaterialApp(
    theme: KeystoneTheme.buildLightTheme(),
    home: SignInHelpScreen(
      routerLabel: 'AW1000',
      address: '192.168.1.1',
      openReset: openReset,
    ),
  ),
);

void main() {
  testWidgets('names the router it is helping with', (t) async {
    await _open(t);
    expect(find.text('Help connecting'), findsOneWidget);
    expect(find.text('For an AW1000 at 192.168.1.1'), findsOneWidget);
    for (final q in [
      "Keystone can't find my router",
      "I don't know the password",
      'Which address should I use?',
      'What can Keystone change?',
    ]) {
      expect(find.text(q), findsOneWidget);
    }
    expect(find.text('Open LuCI in a browser'), findsOneWidget);
  });

  testWidgets('reset steps open on tap, with the warning', (t) async {
    await _open(t);
    expect(find.textContaining(_reset), findsNothing);
    await t.tap(find.text("I don't know the password"));
    await t.pumpAndSettle();
    expect(find.textContaining(_reset), findsOneWidget);
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('can open straight at the reset answer', (t) async {
    await _open(t, openReset: true);
    expect(find.textContaining(_reset), findsOneWidget);
  });
}
