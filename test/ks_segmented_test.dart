// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

void main() {
  for (final (name, theme) in [
    ('light', KeystoneTheme.buildLightTheme()),
    ('dark', KeystoneTheme.buildDarkTheme()),
  ]) {
    testWidgets('segmented control picks the tapped option ($name)', (t) async {
      var value = 4;
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, set) => KsSegmented<int>(
                label: 'Devices shown',
                value: value,
                options: const [(3, '3'), (4, '4'), (5, '5')],
                onChanged: (v) => set(() => value = v),
                help: 'More devices, shorter names.',
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('5'));
      await t.pumpAndSettle();
      expect(value, 5);
      expect(find.text('More devices, shorter names.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
