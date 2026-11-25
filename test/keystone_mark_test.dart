import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/widgets/keystone/keystone_mark.dart';

Widget _app(Widget child) => MaterialApp(
  theme: KeystoneTheme.buildLightTheme(),
  home: Center(child: child),
);

void main() {
  testWidgets('keeps the 40:24 shape', (tester) async {
    await tester.pumpWidget(_app(const KeystoneMark(width: 120)));
    expect(tester.getSize(find.byType(KeystoneMark)), const Size(120, 72));
  });

  testWidgets('paints mid-animation without errors', (tester) async {
    await tester.pumpWidget(
      _app(const KeystoneMark(width: 120, settle: 0, keyDrop: 0, shine: 0.5)),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('is labelled for screen readers', (tester) async {
    await tester.pumpWidget(_app(const KeystoneMark()));
    expect(find.bySemanticsLabel('Keystone'), findsOneWidget);
  });
}
