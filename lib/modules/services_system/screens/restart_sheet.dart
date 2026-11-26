// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../restart_preset.dart';

class RestartForm extends StatefulWidget {
  const RestartForm({
    super.key,
    required this.guarded,
    this.current,
    required this.onSave,
  });

  final bool guarded;
  final String? current;
  final Future<void> Function(String? line) onSave;

  @override
  State<RestartForm> createState() => _RestartFormState();
}

class _RestartFormState extends State<RestartForm> {
  late final _was = widget.current == null
      ? null
      : readRestartPreset(widget.current!);
  late var _target = widget.guarded
      ? (_was?.target ?? RestartTarget.router)
      : RestartTarget.router;
  late var _time = (_was?.hour ?? 4) * 60 + (_was?.minute ?? 0);
  bool _busy = false;

  String _clock(int m) =>
      TimeOfDay(hour: m ~/ 60, minute: m % 60).format(context);

  Future<void> _save(String? line) async {
    setState(() => _busy = true);
    await widget.onSave(line);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final times = {for (var m = 0; m < 24 * 60; m += 30) m, _time}.toList()
      ..sort();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Restart every night', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'Some SIMs slow down after days online. A restart at a quiet hour '
          'clears it.',
          style: KeystoneType.secondary(ks.mu),
        ),
        if (widget.guarded)
          KsSegmented<RestartTarget>(
            label: 'Restart',
            value: _target,
            options: const [
              (RestartTarget.router, 'Router'),
              (RestartTarget.modem, 'Modem'),
            ],
            onChanged: (t) => setState(() => _target = t),
          ),
        KsChoice<int>(
          label: 'At',
          value: _time,
          options: [for (final m in times) (m, _clock(m))],
          onChanged: (m) => setState(() => _time = m),
        ),
        const SizedBox(height: 8),
        Text(
          widget.guarded
              ? 'Skipped during a phone call, a firmware upgrade, or the first '
                    'hour after the router starts.'
              : 'Install signal history to skip restarts during calls and '
                    'upgrades, and to restart only the modem.',
          style: KeystoneType.caption(ks.mu),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy
              ? null
              : () => _save(
                  restartCronLine(
                    target: _target,
                    hour: _time ~/ 60,
                    minute: _time % 60,
                    guarded: widget.guarded,
                  ),
                ),
          child: const Text('Save'),
        ),
        if (_was != null)
          TextButton(
            onPressed: _busy ? null : () => _save(null),
            child: Text('Stop restarting', style: KeystoneType.body(ks.bad)),
          ),
      ],
    );
  }
}
