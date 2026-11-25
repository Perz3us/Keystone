// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class AdGuardPauseDialog extends StatelessWidget {
  const AdGuardPauseDialog({super.key});

  static Future<Duration?> show(BuildContext context) =>
      ksSheet<Duration>(context, (_) => const AdGuardPauseDialog());

  Future<void> _until(BuildContext context) async {
    final now = DateTime.now();
    final start = now.add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null || !context.mounted) return;
    final d = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    ).difference(DateTime.now());
    if (d <= Duration.zero) {
      ksSay(context, 'Pick a time later than now.');
      return;
    }
    Navigator.of(context).pop(d);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    const presets = [
      ('agh_pause_15m_option', '15 minutes', Duration(minutes: 15)),
      ('agh_pause_30m_option', '30 minutes', Duration(minutes: 30)),
      ('agh_pause_1h_option', '1 hour', Duration(hours: 1)),
      ('agh_pause_24h_option', 'A day', Duration(hours: 24)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pause ad blocking', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 8),
        for (final (key, label, d) in presets)
          KsRow(
            key: Key(key),
            title: label,
            chevron: false,
            onTap: () => Navigator.of(context).pop(d),
          ),
        KsRow(
          key: const Key('agh_pause_custom_option'),
          title: 'Until…',
          onTap: () => _until(context),
        ),
        KsRow(
          key: const Key('agh_pause_off_option'),
          title: 'Until I turn it back on',
          chevron: false,
          onTap: () => Navigator.of(context).pop(Duration.zero),
        ),
      ],
    );
  }
}
