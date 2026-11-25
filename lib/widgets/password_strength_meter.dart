// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

enum PasswordStrength { weak, fair, strong, veryStrong }

class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  PasswordStrength? get _strength {
    if (password.length < 8) return null;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[@$!%*?&#^()_+\-=\[\]{};:"\\|,.<>/\~`]').hasMatch(password)) {
      score++;
    }

    if (score <= 1) return PasswordStrength.weak;
    if (score == 2) return PasswordStrength.fair;
    if (score == 3 || score == 4) return PasswordStrength.strong;
    return PasswordStrength.veryStrong;
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength;
    if (strength == null) return const SizedBox.shrink();
    final ks = context.ks;
    final (bars, color, words) = switch (strength) {
      PasswordStrength.weak => (1, ks.bad, 'Weak, easy to guess'),
      PasswordStrength.fair => (2, ks.warnTx, 'Fair, add length or symbols'),
      PasswordStrength.strong => (3, ks.ok, 'Strong'),
      PasswordStrength.veryStrong => (4, ks.ok, 'Very strong'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i < bars ? color : ks.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(words, style: KeystoneType.caption(color)),
        ],
      ),
    );
  }
}
