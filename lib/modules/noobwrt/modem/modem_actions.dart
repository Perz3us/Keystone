// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_rpc.dart';
import 'check_and_fix.dart';
import 'modem_controls.dart';

bool dumpOnline(Map<String, dynamic> dump) {
  final ifaces = dump['interface'];
  if (ifaces is! List) return false;
  for (final i in ifaces.whereType<Map>()) {
    if (i['up'] != true || i['route'] is! List) continue;
    for (final r in (i['route'] as List).whereType<Map>()) {
      final t = r['target'];
      if ((t == '0.0.0.0' || t == '::') && r['mask'] == 0) return true;
    }
  }
  return false;
}

Future<bool> routerOnline(AppState app) async {
  try {
    return dumpOnline(await noobCall(app, 'network.interface', 'dump'));
  } catch (_) {
    return false;
  }
}

enum ModemPart { network, fix, restart }

class ModemActions extends StatefulWidget {
  const ModemActions({
    super.key,
    required this.controls,
    required this.online,
    this.parts = const {ModemPart.network, ModemPart.fix, ModemPart.restart},
  });

  final ModemControls controls;
  final Future<bool> Function() online;
  final Set<ModemPart> parts;

  @override
  State<ModemActions> createState() => _ModemActionsState();
}

class _ModemActionsState extends State<ModemActions> {
  List<NetMode> _modes = const [];
  String _mode = '';
  bool _canRestart = false;
  bool _canFix = false;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    (List<NetMode>, String)? modes;
    Future<bool> can(Future<bool> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return false;
      }
    }

    final c = widget.controls;
    final wantFix = widget.parts.contains(ModemPart.fix);
    final wantRestart = widget.parts.contains(ModemPart.restart);
    if (widget.parts.contains(ModemPart.network)) {
      try {
        modes = await c.netModes();
      } catch (_) {}
    }
    final restart = (wantFix || wantRestart) && await can(c.canRestart);
    final fix =
        wantFix &&
        (restart || await can(c.canReconnect) || await can(c.canPowerCycle));
    if (!mounted) return;
    setState(() {
      _modes = modes?.$1 ?? const [];
      _mode = modes?.$2 ?? '';
      _canRestart = wantRestart && restart;
      _canFix = fix;
      _loaded = true;
    });
  }

  Future<void> _do(String what, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ksSay(context, what);
    } catch (e) {
      if (mounted) ksSay(context, "The modem didn't take that: $e");
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _switch(NetMode m) async {
    if (m.id == _mode || _busy) return;
    final ok = await ksConfirm(
      context,
      title: 'Switch to ${m.label}?',
      body: 'The connection drops for a moment.',
      action: 'Switch',
    );
    if (ok && mounted) {
      await _do(
        'Switched to ${m.label}.',
        () => widget.controls.setNetMode(m.id),
      );
    }
  }

  Future<void> _restart() async {
    final ok = await ksConfirm(
      context,
      title: 'Restart the modem?',
      body: 'The connection drops for a moment.',
      action: 'Restart',
    );
    if (ok && mounted) {
      await _do('Modem restarting.', widget.controls.restart);
    }
  }

  Future<void> _fix() => ksSheet<void>(
    context,
    (_) => _FixSheet(steps: checkAndFix(widget.controls, widget.online)),
  );

  @override
  Widget build(BuildContext context) {
    if (!_loaded || (_modes.isEmpty && !_canFix && !_canRestart)) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_modes.isNotEmpty) const SizedBox(height: 16),
        if (_modes.isNotEmpty)
          KsSegmented<String>(
            label: 'Network',
            value: _mode,
            options: [for (final m in _modes) (m.id, m.label)],
            onChanged: (id) => _switch(_modes.firstWhere((m) => m.id == id)),
          ),
        if (_canFix)
          KsRow(
            title: 'Check and fix',
            subtitle: 'Reconnects, then restarts the modem if needed',
            onTap: _busy ? null : _fix,
          ),
        if (_canRestart)
          KsRow(title: 'Restart modem', onTap: _busy ? null : _restart),
      ],
    );
  }
}

class _FixSheet extends StatefulWidget {
  const _FixSheet({required this.steps});
  final Stream<FixStep> steps;

  @override
  State<_FixSheet> createState() => _FixSheetState();
}

class _FixSheetState extends State<_FixSheet> {
  final _steps = <FixStep>[];
  StreamSubscription<FixStep>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _sub = widget.steps.listen((s) {
      if (!mounted) return;
      setState(() {
        final i = _steps.indexWhere((e) => e.text == s.text);
        if (i >= 0) {
          _steps[i] = s;
          return;
        }
        _steps.add(s);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Check and fix', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 12),
        for (final s in _steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: switch (s.ok) {
                    null => const CircularProgressIndicator(strokeWidth: 2),
                    true => Icon(Icons.check, size: 20, color: ks.ok),
                    false => Icon(Icons.close, size: 20, color: ks.bad),
                  },
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(s.text, style: KeystoneType.body(ks.tx))),
              ],
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
