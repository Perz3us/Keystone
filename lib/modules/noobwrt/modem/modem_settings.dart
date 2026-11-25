// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import 'modem_controls.dart';

Future<void> _run(
  BuildContext context,
  String? done,
  Future<void> Function() action,
) async {
  try {
    await action();
    if (done != null && context.mounted) ksSay(context, done);
  } catch (e) {
    if (context.mounted) ksSay(context, "The modem didn't take that: $e");
  }
}

class SpeedOptions extends StatefulWidget {
  const SpeedOptions({super.key, required this.controls});

  final ModemControls controls;

  @override
  State<SpeedOptions> createState() => _SpeedOptionsState();
}

class _SpeedOptionsState extends State<SpeedOptions> {
  final Map<SpeedOption, bool> _on = {};
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final on = <SpeedOption, bool>{};
    for (final o in SpeedOption.values) {
      try {
        final v = await widget.controls.speed(o);
        if (v != null) on[o] = v;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _on
        ..clear()
        ..addAll(on);
    });
  }

  Future<void> _toggle(SpeedOption o, bool v) async {
    final ok = await ksConfirm(
      context,
      title: 'Turn ${o.label} ${v ? 'on' : 'off'}?',
      body: 'The modem restarts its radio. The connection drops for a moment.',
      action: v ? 'Turn on' : 'Turn off',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await _run(context, null, () => widget.controls.setSpeed(o, v));
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const _Wait();
    if (_on.isEmpty) {
      return const KsNote('This modem has no speed options to change.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 2,
          child: _busy ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        for (final e in _on.entries)
          KsSwitchRow(
            title: e.key.label,
            value: e.value,
            busy: _busy,
            onChanged: (v) => _toggle(e.key, v),
          ),
      ],
    );
  }
}

class _Wait extends StatelessWidget {
  const _Wait();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(child: CircularProgressIndicator()),
  );
}

class SimSettings extends StatefulWidget {
  const SimSettings({super.key, required this.controls});

  final ModemControls controls;

  @override
  State<SimSettings> createState() => _SimSettingsState();
}

class _SimSettingsState extends State<SimSettings> {
  SimSlots? _sims;
  (bool, String)? _apn;
  bool? _roaming;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T?> _try<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final sims = await _try(widget.controls.sims);
    final apn = await _try(widget.controls.apn);
    final roaming = await _try(widget.controls.roaming);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _sims = sims;
      _apn = apn;
      _roaming = roaming;
    });
  }

  Future<void> _do(String? done, Future<void> Function() action) async {
    setState(() => _busy = true);
    await _run(context, done, action);
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _switch(String id, String label) async {
    final ok = await ksConfirm(
      context,
      title: 'Switch to $label?',
      body: 'The connection drops for a moment.',
      action: 'Switch',
    );
    if (ok && mounted) await _do(null, () => widget.controls.setSim(id));
  }

  Future<void> _roam(bool v) async {
    final ok = await ksConfirm(
      context,
      title: 'Turn data roaming ${v ? 'on' : 'off'}?',
      body: 'The connection drops for a moment.',
      action: v ? 'Turn on' : 'Turn off',
    );
    if (ok && mounted) await _do(null, () => widget.controls.setRoaming(v));
  }

  Future<void> _apnSheet() async {
    final r = await ksSheet<(bool, String)>(
      context,
      (_) => _ApnSheet(_apn!.$1, _apn!.$2),
    );
    if (r != null && mounted) {
      await _do(
        'Saved. The modem reconnects.',
        () => widget.controls.setApn(manual: r.$1, apn: r.$2),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sims = _sims;
    final apn = _apn;
    final roaming = _roaming;
    if (!_loaded) return const _Wait();
    if (sims == null && apn == null && roaming == null) {
      return const KsNote('This modem has no SIM settings to change.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 2,
          child: _busy ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        if (sims != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('SIM card', style: KeystoneType.body(context.ks.tx)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, label, present) in sims.slots)
                KsChip(
                  label,
                  selected: id == sims.active,
                  onTap: _busy || !present || id == sims.active
                      ? null
                      : () => _switch(id, label),
                ),
            ],
          ),
        ],
        if (roaming != null)
          KsSwitchRow(
            title: 'Data roaming',
            value: roaming,
            busy: _busy,
            onChanged: _roam,
          ),
        if (apn != null)
          KsRow(
            title: 'APN',
            subtitle: apn.$1 && apn.$2.isNotEmpty ? apn.$2 : 'Automatic',
            onTap: _busy ? null : _apnSheet,
          ),
      ],
    );
  }
}

class _ApnSheet extends StatefulWidget {
  const _ApnSheet(this.manual, this.apn);
  final bool manual;
  final String apn;

  @override
  State<_ApnSheet> createState() => _ApnSheetState();
}

class _ApnSheetState extends State<_ApnSheet> {
  late final _text = TextEditingController(text: widget.apn);
  late bool _manual = widget.manual;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APN', style: KeystoneType.sheetTitle(context.ks.tx)),
        const SizedBox(height: 12),
        KsChips<bool>(
          options: const [(false, 'Automatic'), (true, 'Type it')],
          selected: _manual,
          onSelected: (v) => setState(() => _manual = v),
        ),
        if (_manual)
          KsField(
            label: 'APN',
            controller: _text,
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: 20),
        Text(
          'Saving reconnects the modem. The connection drops for a moment.',
          style: KeystoneType.secondary(context.ks.tx2),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _manual && _text.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, (
                  _manual,
                  _manual ? _text.text.trim() : '',
                )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
