import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/widgets/keystone/aw1000_drawing.dart';
import 'package:yet_another_luci_app/widgets/keystone/router_drawing.dart';

Widget _app(Widget child) => MaterialApp(
  theme: KeystoneTheme.buildLightTheme(),
  home: Center(child: RepaintBoundary(child: child)),
);

const _g = LightColor.green, _r = LightColor.red, _off = LightColor.off;
const _live = RouterLights([_g, _r, _g, _g, _g, _off]);

void main() {
  testWidgets('an AW1000 gets its own drawing at 100:132', (tester) async {
    await tester.pumpWidget(
      _app(const RouterDrawing(model: 'Arcadyan AW1000', width: 100)),
    );
    expect(tester.getSize(find.byType(RouterDrawing)), const Size(100, 132));
    expect(find.byType(Aw1000Drawing), findsOneWidget);
  });

  testWidgets('other routers get the plain shape', (tester) async {
    await tester.pumpWidget(_app(const RouterDrawing(model: 'TP-Link Archer')));
    expect(find.byType(Aw1000Drawing), findsNothing);
    expect(find.bySemanticsLabel('Router'), findsOneWidget);
  });

  testWidgets('screen readers hear what the lights say', (tester) async {
    await tester.pumpWidget(
      _app(const RouterDrawing(model: 'AW1000', lights: _live)),
    );
    expect(
      find.bySemanticsLabel(
        'AW1000. Lights: power green, 5G red, mobile signal green, '
        'Wi-Fi green, internet green, phone off.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('lit AW1000 matches the reference', (tester) async {
    await tester.pumpWidget(
      _app(const RouterDrawing(model: 'AW1000', lights: _live, width: 200)),
    );
    await expectLater(
      find.byType(RouterDrawing),
      matchesGoldenFile('goldens/aw1000_lit.png'),
    );
  }, skip: !Platform.isWindows);
}
