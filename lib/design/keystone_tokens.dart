import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class KeystoneColors extends ThemeExtension<KeystoneColors> {
  const KeystoneColors({
    required this.bg,
    required this.node,
    required this.sheet,
    required this.tint,
    required this.line,
    required this.tx,
    required this.tx2,
    required this.mu,
    required this.ac,
    required this.acPress,
    required this.acSoft,
    required this.ok,
    required this.warn,
    required this.okTx,
    required this.warnTx,
    required this.bad,
  });

  final Color bg, node, sheet, tint, line, tx, tx2, mu;
  final Color ac, acPress, acSoft, ok, okTx, warn, warnTx, bad;

  static const ledGreen = Color(0xFF59DE65);
  static const ledRed = Color(0xFFF53E39);
  static const ledBlue = Color(0xFF3F93F7);
  static const ledOff = Color(0xFFC4C8CD);

  static const light = KeystoneColors(
    bg: Color(0xFFF5F7F9),
    node: Color(0xFFFDFDFF),
    sheet: Color(0xFFFDFDFF),
    tint: Color(0xFFE6ECF3),
    line: Color(0xFFDBDEE3),
    tx: Color(0xFF151B24),
    tx2: Color(0xFF2D333D),
    mu: Color(0xFF626A75),
    ac: Color(0xFF276ED2),
    acPress: Color(0xFF0555B7),
    acSoft: Color(0xFFD8E9FF),
    ok: Color(0xFF219761),
    okTx: Color(0xFF1A7A4E),
    warn: Color(0xFFDD881B),
    warnTx: Color(0xFF994A00),
    bad: Color(0xFFC93B3B),
  );

  static const dark = KeystoneColors(
    bg: Color(0xFF0A0D12),
    node: Color(0xFF14191F),
    sheet: Color(0xFF12161C),
    tint: Color(0xFF161B22),
    line: Color(0xFF242930),
    tx: Color(0xFFECEFF3),
    tx2: Color(0xFFCED1D6),
    mu: Color(0xFF9399A2),
    ac: Color(0xFF70A6F5),
    acPress: Color(0xFF588CDA),
    acSoft: Color(0xFF16273F),
    ok: Color(0xFF58C38B),
    okTx: Color(0xFF58C38B),
    warn: Color(0xFFF3AE58),
    warnTx: Color(0xFFF4B768),
    bad: Color(0xFFF2716A),
  );

  @override
  KeystoneColors copyWith() => this;

  @override
  KeystoneColors lerp(ThemeExtension<KeystoneColors>? other, double t) {
    if (other is! KeystoneColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KeystoneColors(
      bg: l(bg, other.bg),
      node: l(node, other.node),
      sheet: l(sheet, other.sheet),
      tint: l(tint, other.tint),
      line: l(line, other.line),
      tx: l(tx, other.tx),
      tx2: l(tx2, other.tx2),
      mu: l(mu, other.mu),
      ac: l(ac, other.ac),
      acPress: l(acPress, other.acPress),
      acSoft: l(acSoft, other.acSoft),
      ok: l(ok, other.ok),
      okTx: l(okTx, other.okTx),
      warn: l(warn, other.warn),
      warnTx: l(warnTx, other.warnTx),
      bad: l(bad, other.bad),
    );
  }
}

extension KeystoneContext on BuildContext {
  KeystoneColors get ks {
    dependOnInheritedWidgetOfExactType<KeystoneFontScope>();
    return Theme.of(this).extension<KeystoneColors>() ??
        (Theme.of(this).brightness == Brightness.dark
            ? KeystoneColors.dark
            : KeystoneColors.light);
  }
}

class KeystoneFontScope extends InheritedNotifier<ValueNotifier<KeystoneFont>> {
  KeystoneFontScope({super.key, required super.child})
    : super(notifier: KeystoneType.font);
}

enum KeystoneFont { keystone, system, geist }

const _fontKey = 'keystone_font';

Future<void> loadKeystoneFont() async {
  final saved = (await SharedPreferences.getInstance()).getString(_fontKey);
  KeystoneType.font.value =
      KeystoneFont.values.where((f) => f.name == saved).firstOrNull ??
      KeystoneFont.keystone;
}

Future<void> saveKeystoneFont(KeystoneFont f) async {
  KeystoneType.font.value = f;
  await (await SharedPreferences.getInstance()).setString(_fontKey, f.name);
}

abstract final class KeystoneType {
  static final font = ValueNotifier(KeystoneFont.keystone);

  static TextStyle ui(TextStyle s) => _family(
    (s.fontWeight?.value ?? 400) > 600
        ? s.copyWith(fontWeight: FontWeight.w600)
        : s,
    heading: false,
  );

  static TextStyle _family(TextStyle s, {required bool heading}) =>
      switch (font.value) {
        KeystoneFont.keystone =>
          heading
              ? GoogleFonts.schibstedGrotesk(textStyle: s)
              : GoogleFonts.onest(textStyle: s),
        KeystoneFont.geist => GoogleFonts.geist(textStyle: s),
        KeystoneFont.system => s,
      };

  static TextStyle _head(Color c, double size, double tracking) => _family(
    TextStyle(
      color: c,
      fontSize: size,
      fontWeight: FontWeight.w600,
      height: 1.1,
      letterSpacing: tracking,
    ),
    heading: true,
  );

  static TextStyle _text(
    Color c,
    double size,
    FontWeight w, [
    double h = 1.4,
  ]) => _family(
    TextStyle(
      color: c,
      fontSize: size,
      fontWeight: w,
      height: h,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
    heading: false,
  );

  static TextStyle headline(Color c) => _head(c, 32, -0.9);
  static TextStyle title(Color c) => _head(c, 28, -0.7);
  static TextStyle sheetTitle(Color c) => _head(c, 20, -0.2);
  static TextStyle body(Color c) => _text(c, 16, FontWeight.w400, 1.45);
  static TextStyle bodyStrong(Color c) => _text(c, 16, FontWeight.w600);
  static TextStyle secondary(Color c) => _text(c, 14, FontWeight.w400);
  static TextStyle caption(Color c) => _text(c, 12, FontWeight.w500);
  static TextStyle address(Color c) => _text(c, 16, FontWeight.w400);
}
