// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerOpenSourceLicenses();
  });

  group('GPLv3 Compliance & Attribution', () {
    test(
      'LicenseRegistry includes the Keystone entry with upstream notices',
      () async {
        final entries = await LicenseRegistry.licenses.toList();
        final entry = entries.firstWhere(
          (e) => e.packages.any((p) => p == 'Keystone'),
        );

        expect(entry, isNotNull);
        final paragraphs = entry.paragraphs.map((p) => p.text).join('\n');
        expect(paragraphs, contains('cogwheel0'));
        expect(paragraphs, contains('@nightcodex7'));
        expect(paragraphs, contains('GNU General Public License'));
        expect(paragraphs, contains('WITHOUT ANY WARRANTY'));
      },
    );

    test(
      'LicenseRegistry includes luci-app-advanced-reboot entry with upstream attribution',
      () async {
        final entries = await LicenseRegistry.licenses.toList();
        final rebootEntry = entries.firstWhere(
          (e) => e.packages.any((p) => p.contains('luci-app-advanced-reboot')),
        );

        expect(rebootEntry, isNotNull);
        final paragraphs = rebootEntry.paragraphs.map((p) => p.text).join('\n');
        expect(paragraphs, contains('Stan Grishin'));
        expect(paragraphs, contains('OpenWrt Contributors'));
        expect(paragraphs, contains('GNU General Public License'));
      },
    );
  });
}
