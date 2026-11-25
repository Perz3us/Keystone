import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({
    super.key,
    required this.themeMode,
    required this.onTheme,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onTheme;

  static const _fonts = [
    (KeystoneFont.keystone, 'Keystone · the default'),
    (KeystoneFont.system, "System · your phone's own font"),
    (KeystoneFont.geist, 'Geist · clean and technical'),
  ];

  static TextStyle _preview(KeystoneFont f, Color c) {
    final s = TextStyle(
      color: c,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
    );
    return switch (f) {
      KeystoneFont.keystone => GoogleFonts.schibstedGrotesk(textStyle: s),
      KeystoneFont.geist => GoogleFonts.geist(textStyle: s),
      KeystoneFont.system => s,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final current = KeystoneType.font.value;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('Appearance', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 20),
        Text('Theme', style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: {themeMode},
          showSelectedIcon: false,
          onSelectionChanged: (v) => onTheme(v.first),
        ),
        const SizedBox(height: 24),
        Text('Font', style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 8),
        for (final (font, label) in _fonts)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: ks.node,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: font == current ? ks.ac : ks.line,
                  width: font == current ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => saveKeystoneFont(font),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Everything's working.",
                              style: _preview(font, ks.tx),
                            ),
                            Text(label, style: KeystoneType.caption(ks.mu)),
                          ],
                        ),
                      ),
                      Icon(
                        font == current
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: font == current ? ks.ac : ks.line,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          "Text size follows your phone's setting.",
          style: KeystoneType.secondary(ks.mu),
        ),
      ],
    );
  }
}
