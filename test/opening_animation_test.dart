import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/sign_in/opening_animation.dart';

Future<int Function()> _pump(
  WidgetTester t, {
  bool reduceMotion = false,
}) async {
  var done = 0;
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: OpeningAnimation(onHoldDone: () => done++),
    ),
  );
  return () => done;
}

void main() {
  testWidgets('plays once, then says it is done', (t) async {
    final done = await _pump(t);
    await t.pump();
    expect(done(), 0);
    await t.pump(const Duration(milliseconds: 1550));
    expect(find.text('Keystone'), findsOneWidget);
    expect(find.text('by perz3us'), findsOneWidget);
    expect(done(), 1);
    await t.pump(const Duration(seconds: 2));
    expect(done(), 1);
  });

  testWidgets('reduced motion skips straight to the end', (t) async {
    final done = await _pump(t, reduceMotion: true);
    await t.pump();
    expect(done(), 1);
  });
}
