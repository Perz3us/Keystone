import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/more/more_view.dart';

void main() {
  Future<List<String>> pump(WidgetTester t, {double textScale = 1}) async {
    final taps = <String>[];
    MoreItem item(String t, String s) =>
        MoreItem(Icons.extension_outlined, t, s, () => taps.add(t));
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
          child: child!,
        ),
        home: Scaffold(
          body: MoreView(
            routerName: 'AW1000',
            sections: [
              ('On this router', [item('Passwall2', 'Proxy on or off')]),
              ('Router settings', [item('Firewall', 'Rules and zones')]),
              ('Keystone', [item('Appearance', 'Theme and font')]),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return taps;
  }

  testWidgets('only what is installed, then settings', (t) async {
    final taps = await pump(t);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Only what this router has installed.'), findsOneWidget);
    expect(find.text('On this router'), findsOneWidget);
    expect(find.text('Proxy on or off'), findsOneWidget);
    await t.tap(find.text('Passwall2'));
    await t.ensureVisible(find.text('Appearance'));
    await t.tap(find.text('Appearance'));
    expect(taps, ['Passwall2', 'Appearance']);
  });

  testWidgets('empty sections are left out', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: const Scaffold(
          body: MoreView(
            routerName: 'AW1000',
            sections: [('On this router', [])],
          ),
        ),
      ),
    );
    expect(find.text('On this router'), findsNothing);
  });

  testWidgets('fits at 2x text', (t) async {
    await pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('ends with sign out', (t) async {
    var out = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: Scaffold(
          body: MoreView(
            routerName: 'AW1000',
            sections: const [],
            signOutLabel: 'Sign out',
            onSignOut: () => out++,
          ),
        ),
      ),
    );
    await t.scrollUntilVisible(find.text('Sign out'), 100);
    await t.tap(find.text('Sign out'));
    expect(out, 1);
  });
}
