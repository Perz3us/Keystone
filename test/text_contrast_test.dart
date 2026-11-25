import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

void main() => test('signal colours read as small text', () {
  double c(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
  }

  for (final k in [KeystoneColors.light, KeystoneColors.dark]) {
    for (final t in [k.tx, k.mu, k.okTx, k.warnTx, k.bad]) {
      expect(c(t, k.bg), greaterThan(4.5));
    }
  }
});
