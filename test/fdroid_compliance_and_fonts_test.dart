// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('F-Droid Compliance & Bundled Fonts', () {
    test(
      'The Geist and Geist Mono weights the app uses and OFL.txt exist in assets',
      () async {
        final fontFiles = [
          'assets/fonts/Geist-Regular.ttf',
          'assets/fonts/Geist-Medium.ttf',
          'assets/fonts/Geist-SemiBold.ttf',
          'assets/fonts/Geist-Bold.ttf',
          'assets/fonts/Geist-ExtraBold.ttf',
          'assets/fonts/GeistMono-Regular.ttf',
          'assets/fonts/GeistMono-Medium.ttf',
          'assets/fonts/GeistMono-SemiBold.ttf',
          'assets/fonts/GeistMono-Bold.ttf',
          'assets/fonts/GeistMono-ExtraBold.ttf',
        ];

        for (final fontFile in fontFiles) {
          final byteData = await rootBundle.load(fontFile);
          expect(
            byteData.lengthInBytes,
            greaterThan(10000),
            reason: 'Font $fontFile must be a non-empty TTF file',
          );
        }

        final licenseString = await rootBundle.loadString(
          'assets/fonts/OFL.txt',
        );
        expect(licenseString, contains('SIL OPEN FONT LICENSE Version 1.1'));
        expect(licenseString, contains('The Geist Project Authors'));
      },
    );

    test(
      'GoogleFonts config allowRuntimeFetching can be disabled for offline compliance',
      () {
        GoogleFonts.config.allowRuntimeFetching = false;
        expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
      },
    );
  });
}
