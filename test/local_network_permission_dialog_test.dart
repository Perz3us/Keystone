// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/widgets/local_network_permission_dialog.dart';

void main() {
  Future<List<bool?>> open(WidgetTester t, {bool denied = false}) async {
    final results = <bool?>[];
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => results.add(
                await LocalNetworkPermissionDialog.show(
                  context,
                  isPermanentlyDenied: denied,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    return results;
  }

  testWidgets('explains the prompt before Android shows it', (t) async {
    final results = await open(t);
    expect(find.text('Find your router'), findsOneWidget);
    expect(
      find.textContaining('nothing leaves your home network'),
      findsOneWidget,
    );
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(results, [true]);
  });

  testWidgets('Not now closes without asking', (t) async {
    final results = await open(t);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(results, [false]);
  });

  testWidgets('after a refusal it points to Settings', (t) async {
    await open(t, denied: true);
    expect(find.text('Keystone can\'t reach your router'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });
}
