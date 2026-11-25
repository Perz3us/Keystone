import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/more/about_screen.dart';

void main() {
  testWidgets('About keeps the GPL notices and credits', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: const AboutScreen(),
      ),
    );
    await t.pump();
    expect(find.textContaining('© 2026 Perz3us'), findsOneWidget);
    expect(find.textContaining('cogwheel0'), findsOneWidget);
    expect(find.text('Sponsor Keystone'), findsOneWidget);
    expect(find.text('Licences'), findsOneWidget);
    expect(find.text('Perz3us on GitHub'), findsOneWidget);
  });
}
