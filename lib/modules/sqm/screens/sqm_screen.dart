// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/sqm_controller.dart';
import '../models/sqm_preset.dart';
import '../models/sqm_queue.dart';
import '../models/sqm_telemetry.dart';

const sqmPresetWords = {
  'cake_fiber': 'Fibre, cable, mobile or Ethernet',
  'layer_cake': 'Same, but calls and games always go first',
  'vdsl_pppoe': 'VDSL, or fibre that signs in with PPPoE',
  'docsis_cable': 'Cable modem',
  'adsl_atm': 'ADSL over the phone line',
  'low_cpu': 'Lighter on the router, a little less smooth',
};

String sqmMbps(int kbit) {
  if (kbit <= 0) return '';
  final m = kbit / 1000;
  return m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
}

String? sqmHealthLine(SqmQueueTelemetry? t) {
  if (t == null) return null;
  final waiting = t.backlogPackets;
  final dropped = t.droppedPackets;
  return [
    waiting == 0 ? 'Nothing waiting' : '$waiting packets waiting',
    if (dropped > 0) '$dropped dropped to keep things moving',
  ].join(' · ');
}

class SqmView extends StatelessWidget {
  const SqmView({
    super.key,
    required this.on,
    required this.busy,
    required this.down,
    required this.up,
    required this.presetId,
    required this.interface,
    required this.interfaces,
    required this.onToggle,
    required this.onPreset,
    required this.onInterface,
    required this.onSave,
    this.changed = false,
    this.health,
    this.offloading = false,
    this.onOffloading,
    this.otherQueues = 0,
  });

  final bool on;
  final bool busy;
  final TextEditingController down;
  final TextEditingController up;

  final String? presetId;
  final String interface;
  final List<String> interfaces;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onPreset;
  final ValueChanged<String> onInterface;
  final VoidCallback onSave;
  final bool changed;
  final String? health;

  final bool offloading;
  final VoidCallback? onOffloading;
  final int otherQueues;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final noSpeeds = down.text.trim().isEmpty && up.text.trim().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KsSwitchRow(
          title: 'Smoothing',
          subtitle: on
              ? (health ?? 'On')
              : noSpeeds
              ? 'Enter your speeds below first'
              : 'Off',
          value: on,
          busy: busy,
          onChanged: (busy || (!on && noSpeeds)) ? null : onToggle,
        ),
        if (offloading)
          KsNote(
            'Fast-path offloading is on, so most traffic skips the '
            'smoothing. Turning it off costs a little speed.',
            action: onOffloading == null ? null : 'Turn it off',
            onAction: onOffloading,
          ),
        const KsSection('Your speeds'),
        Text(
          'Use about 90% of what a speed test shows. Lower is smoother, '
          'higher is faster.',
          style: KeystoneType.secondary(ks.mu),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: KsField(
                label: 'Download (Mbps)',
                controller: down,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KsField(
                label: 'Upload (Mbps)',
                controller: up,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
            ),
          ],
        ),
        const KsSection('Your connection'),
        KsChoice<String>(
          label: 'Type',
          value: presetId ?? 'custom',
          options: [
            for (final p in SqmPreset.presets)
              (p.id, sqmPresetWords[p.id] ?? p.title),
            if (presetId == null) ('custom', 'Set up by hand on the router'),
          ],
          onChanged: (v) {
            if (v != 'custom') onPreset(v);
          },
        ),
        if (interfaces.length > 1)
          KsChoice<String>(
            label: 'Smooth this connection',
            value: interface,
            help: 'The one that goes to the internet',
            options: [for (final i in interfaces) (i, i)],
            onChanged: onInterface,
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: (changed && !busy) ? onSave : null,
          child: const Text('Save'),
        ),
        if (otherQueues > 0)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'This router has $otherQueues more queue'
              '${otherQueues == 1 ? '' : 's'} set up. Keystone leaves '
              '${otherQueues == 1 ? 'it' : 'them'} as they are.',
              style: KeystoneType.caption(ks.mu),
            ),
          ),
      ],
    );
  }
}

class SqmScreen extends ConsumerStatefulWidget {
  final String? routerId;
  const SqmScreen({super.key, this.routerId});

  @override
  ConsumerState<SqmScreen> createState() => _SqmScreenState();
}

class _SqmScreenState extends ConsumerState<SqmScreen> {
  late final String _routerId =
      widget.routerId ??
      ref.read(appStateProvider).selectedRouter?.id ??
      'default';
  SqmController? _controller;
  final _down = TextEditingController();
  final _up = TextEditingController();
  String? _presetId;
  String? _interface;

  SqmQueue? _shown;
  bool _busy = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _down.addListener(_edited);
    _up.addListener(_edited);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller = ref.read(sqmControllerProvider(_routerId).notifier);
      _controller?.refresh(forceTelemetry: true);
      _controller?.startLiveTelemetry();
    });
  }

  @override
  void dispose() {
    _controller?.stopLiveTelemetry();
    _down.dispose();
    _up.dispose();
    super.dispose();
  }

  void _edited() => setState(() {});

  SqmQueue? _main(SqmState s) =>
      s.queues.where((q) => q.interface == s.primaryWanInterface).firstOrNull ??
      s.queues.firstOrNull;

  void _fill(SqmQueue? q, SqmState s) {
    _shown = q;
    _down.text = sqmMbps(q?.download ?? 0);
    _up.text = sqmMbps(q?.upload ?? 0);
    _presetId = q == null ? SqmPreset.cakeFiber.id : SqmPreset.match(q)?.id;
    _interface = sqmTargetInterface(q, s);
  }

  int _kbit(String t) => ((double.tryParse(t.trim()) ?? 0) * 1000).round();

  SqmQueue _edit(SqmState s, {bool? enabled}) {
    final base =
        _shown ??
        SqmQueue(
          name: _freeName(s),
          interface: _interface ?? 'wan',
          enabled: false,
        );
    final p = SqmPreset.presets.where((p) => p.id == _presetId).firstOrNull;
    return base.copyWith(
      enabled: enabled ?? base.enabled,
      interface: _interface,
      download: _kbit(_down.text),
      upload: _kbit(_up.text),
      qdisc: p?.qdisc,
      script: p?.script,
      linklayer: p?.linklayer,
      overhead: p?.overhead,
      qdiscAdvanced: p?.qdiscAdvanced,
    );
  }

  String _freeName(SqmState s) {
    final taken = {
      ...s.queues.map((q) => q.name.toLowerCase()),
      ...s.networkInterfaces.map((i) => i.toLowerCase()),
    };
    var n = 1;
    while (taken.contains('sqm$n')) {
      n++;
    }
    return 'sqm$n';
  }

  bool _changed(SqmState s) {
    final q = _shown;
    if (q == null) return _kbit(_down.text) > 0 || _kbit(_up.text) > 0;
    final e = _edit(s);
    return e.download != q.download ||
        e.upload != q.upload ||
        e.interface != q.interface ||
        e.qdisc != q.qdisc ||
        e.script != q.script ||
        e.linklayer != q.linklayer ||
        e.overhead != q.overhead;
  }

  Future<void> _run(Future<bool> Function() work) async {
    setState(() => _busy = true);
    final ok = await work();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _shown = null;
    });
    if (!ok) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  Future<void> _save(SqmState s) =>
      _run(() => _controller!.saveQueue(_edit(s), context: context));

  Future<void> _toggle(SqmState s, bool on) => _run(() async {
    final c = _controller!;
    if (!await c.saveQueue(_edit(s, enabled: on), context: context)) {
      return false;
    }
    final keepRunning = on || s.queues.any((q) => q != _shown && q.enabled);
    if (!mounted) return false;
    return c.toggleService(keepRunning, context: context);
  });

  Future<void> _install() async {
    setState(() => _installing = true);
    final res = await _controller!.installSqmPackage();
    if (!mounted) return;
    setState(() => _installing = false);
    if (!res.isSuccess) {
      ksSay(
        context,
        res.errorMessage ?? "It didn't install. Check the router has space.",
      );
    }
  }

  Future<void> _offloadingOff() async {
    final ok = await ksConfirm(
      context,
      title: 'Turn off offloading?',
      body:
          'Smoothing then works on all traffic. Very fast connections may '
          'lose a little top speed.',
      action: 'Turn off',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final ok = await ref
          .read(appStateProvider)
          .updateFirewallFlowOffloading(
            software: false,
            hardware: false,
            context: context,
          );
      if (ok) await _controller?.refresh();
      return ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final s = ref.watch(sqmControllerProvider(_routerId));
    final q = _main(s);
    if (_shown == null && !s.isLoading && !_busy) {
      if (q != null || s.lastUpdated != null) _fill(q, s);
    }
    final first = s.lastUpdated == null && s.isLoading;

    final List<Widget> children;
    if (first) {
      children = const [
        Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (s.errorMessage != null && s.lastUpdated == null) {
      children = [
        KsNote(
          "Keystone couldn't read the smoothing settings from the router.",
          action: 'Try again',
          onAction: () => _controller?.refresh(forceTelemetry: true),
        ),
      ];
    } else if (!s.isInstalled) {
      children = [
        Text(
          'When someone downloads or streams, calls and games on the same '
          'connection start to lag. Smoothing keeps a little room free '
          'so they stay quick.',
          style: KeystoneType.body(ks.tx2),
        ),
        const SizedBox(height: 8),
        Text(
          'It needs a small add-on on the router (sqm-scripts, under 1 MB).',
          style: KeystoneType.secondary(ks.mu),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _installing ? null : _install,
          child: Text(_installing ? 'Installing…' : 'Install it'),
        ),
      ];
    } else {
      final on = (q?.enabled ?? false) && s.isServiceRunning;
      children = [
        SqmView(
          on: on,
          busy: _busy,
          down: _down,
          up: _up,
          presetId: _presetId,
          interface: _interface ?? 'wan',
          interfaces: {
            ...s.networkInterfaces,
            ?_interface,
          }.where((i) => i.isNotEmpty).toList(),
          changed: _changed(s),
          health: on
              ? sqmHealthLine(s.telemetryByInterface[q?.interface])
              : null,
          offloading: s.hasSoftwareFlowOffload || s.hasHardwareFlowOffload,
          onOffloading: _offloadingOff,
          otherQueues: s.queues.length > 1 ? s.queues.length - 1 : 0,
          onToggle: (v) => _toggle(s, v),
          onPreset: (v) => setState(() => _presetId = v),
          onInterface: (v) => setState(() => _interface = v),
          onSave: () => _save(s),
        ),
      ];
    }
    return KsPage(
      title: 'Smooth connection',
      subtitle: 'Keeps calls and games smooth while others download',
      onRefresh: () async {
        setState(() => _shown = null);
        await _controller?.refresh(forceTelemetry: true);
      },
      children: children,
    );
  }
}
