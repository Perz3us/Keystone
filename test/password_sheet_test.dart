import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/sign_in/password_sheet.dart';

Future<void> _open(
  WidgetTester t,
  List<bool> answers, {
  double textScale = 1,
  String user = 'root',
}) async {
  var i = 0;
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (c) => Scaffold(
          body: TextButton(
            onPressed: () => showPasswordSheet(
              c,
              user: user,
              onSubmit: (_) async => answers[i++],
              onChangeUser: () {},
              onShowReset: () {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  test('capitals check', () {
    expect(looksLikeCapsLock('ABC'), isTrue);
    expect(looksLikeCapsLock('ABc'), isFalse);
    expect(looksLikeCapsLock('AB'), isFalse);
    expect(looksLikeCapsLock('AB12'), isFalse);
    expect(looksLikeCapsLock('PASS123'), isTrue);
    expect(looksLikeCapsLock(''), isFalse);
  });

  testWidgets('shows the sheet', (t) async {
    await _open(t, [true]);
    expect(find.text('Router password'), findsOneWidget);
    expect(find.text('The one you use for LuCI in a browser.'), findsOneWidget);
    expect(find.textContaining('As root'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('warns about capitals only when everything is capitals', (
    t,
  ) async {
    await _open(t, [true]);
    await t.enterText(find.byType(TextField), 'QWE');
    await t.pump();
    expect(find.text('Typing in capitals. Is Caps Lock on?'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'qwe');
    await t.pump();
    expect(find.text('Typing in capitals. Is Caps Lock on?'), findsNothing);
  });

  testWidgets('a wrong password keeps the text, reset link after two', (
    t,
  ) async {
    await _open(t, [false, false]);
    await t.enterText(find.byType(TextField), 'secret');
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(find.textContaining("That password didn't work."), findsOneWidget);
    expect(find.text('secret'), findsOneWidget);
    expect(find.text('How to reset it'), findsNothing);
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(find.text('How to reset it'), findsOneWidget);
  });

  testWidgets('the eye shows and hides the password', (t) async {
    await _open(t, [true]);
    bool obscured() => t.widget<TextField>(find.byType(TextField)).obscureText;
    expect(obscured(), isTrue);
    await t.tap(find.byTooltip('Show password'));
    await t.pump();
    expect(obscured(), isFalse);
  });

  testWidgets('a right password closes the sheet', (t) async {
    await _open(t, [true]);
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(find.text('Router password'), findsNothing);
  });

  testWidgets('the largest text fits, even after two wrong tries', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _open(t, [false, false], textScale: 2, user: 'administrator');
    for (var i = 0; i < 2; i++) {
      await t.enterText(find.byType(TextField), 'nope');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
    }
    expect(find.text('How to reset it'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
