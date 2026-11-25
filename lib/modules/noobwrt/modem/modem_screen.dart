// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_rpc.dart';
import '../noob_widgets.dart';
import '../cellular/cellular_data.dart';
import '../cellular/lock_controls.dart';
import '../cellular/preferred_towers.dart';
import '../history/helper_sheet.dart';
import 'align_screen.dart';
import 'modem_actions.dart';
import 'modem_controls.dart';
import 'modem_metrics.dart';
import 'modem_pages.dart';
import 'modem_settings.dart';

const _metricsDir = '/tmp/5gmodem';

Future<List<String>> listModemMetrics(WidgetRef ref) async {
  final names = await noobListDir(ref.read(appStateProvider), _metricsDir);
  return names
      .where((n) => n.startsWith('metrics_') && n.endsWith('.json'))
      .toList()
    ..sort();
}

Future<ModemMetrics> readModemMetrics(WidgetRef ref, String file) async {
  final data = await noobReadJson(
    ref.read(appStateProvider),
    '$_metricsDir/$file',
  );
  return ModemMetrics(data);
}

class ModemScreen extends ConsumerStatefulWidget {
  const ModemScreen({super.key});

  @override
  ConsumerState<ModemScreen> createState() => _ModemScreenState();
}

class _ModemScreenState extends ConsumerState<ModemScreen> {
  Timer? _timer;
  List<String> _files = const [];
  String? _file;
  ModemMetrics? _metrics;
  final _live = ValueNotifier<ModemMetrics?>(null);
  String? _error;
  bool _loading = true;
  late final _locks = FiveGModemLocks(ref.read(appStateProvider));
  late final _controls = FiveGModemControls(ref.read(appStateProvider));

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_file == null) {
        _files = await listModemMetrics(ref);
        if (_files.isEmpty) throw const NoobRpcError('No metrics files');
        _file = _files.first;
      }
      final m = await readModemMetrics(ref, _file!);
      if (!mounted) return;
      _live.value = m;
      setState(() {
        _metrics = m;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _body();
    return NoobPage(
      title: 'Modem',
      body: body is _Sections ? null : body,
      onRefresh: _load,
      actions: [
        if (_files.length > 1)
          PopupMenuButton<String>(
            tooltip: 'Which SIM',
            color: context.ks.sheet,
            icon: Icon(Icons.sim_card_outlined, color: context.ks.mu),
            onSelected: (f) {
              setState(() => _file = f);
              _load();
            },
            itemBuilder: (_) => [
              for (final f in _files)
                PopupMenuItem(
                  value: f,
                  child: Text(f.replaceAll(RegExp(r'^metrics_|_?\.json$'), '')),
                ),
            ],
          ),
      ],
      children: body is _Sections ? body.children : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final m = _metrics;
    if (m == null) {
      return NoobProblem(
        title: 'No modem data',
        detail:
            'The app reads the modem from luci-app-5gmodem. Install it from '
            'System > Software, then open Modem > 5G Modem in LuCI once so it '
            'starts collecting.',
        error: _error,
        onRetry: () {
          setState(() {
            _loading = true;
            _file = null;
          });
          _load();
        },
      );
    }
    final app = ref.read(appStateProvider);
    final file = _file!;
    Future<bool> online() async =>
        (await readModemMetrics(ref, file)).connected;
    final bands = m.carriers.map((c) => c.band.split(' ').first).join(' + ');
    final sim = [
      if (m['simslot'] case final s?) 'SIM $s',
      ?m['iface_apn'],
    ].join(' · ');
    return _Sections([
      _summary(m),
      ModemActions(
        key: const ValueKey('modem-network'),
        controls: _controls,
        online: online,
        parts: const {ModemPart.network},
      ),
      NoobSection(
        title: 'Signal',
        icon: Icons.signal_cellular_alt,
        children: [
          NoobRow(
            'Strength (RSRP)',
            _unit(m['rsrp'], 'dBm'),
            color: m.rsrpQuality.tone(context.ks),
          ),
          if (m['sinr'] != null)
            NoobRow(
              'Clearness (SINR)',
              _unit(m['sinr'], 'dB'),
              color: m.sinrQuality.tone(context.ks),
            ),
          if (m['rsrq'] != null)
            NoobRow(
              'Quality (RSRQ)',
              _unit(m['rsrq'], 'dB'),
              color: m.rsrqQuality.tone(context.ks),
            ),
        ],
      ),
      const SizedBox(height: 16),
      HistoryRow(app: app),
      KsRow(
        title: 'Aim the antenna',
        subtitle: 'Live signal with a tone',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AlignScreen(read: () => readModemMetrics(ref, file)),
            ),
          );
        },
      ),
      ModemActions(
        key: const ValueKey('modem-fix'),
        controls: _controls,
        online: online,
        parts: const {ModemPart.fix},
      ),
      const SizedBox(height: 16),
      ModemPageRow(
        title: 'Towers and bands',
        subtitle: bands.isEmpty ? 'Carriers, bands and cell lock' : bands,
        live: _live,
        children: (_) => _towers(_live.value ?? m, app),
      ),
      ModemPageRow(
        title: 'SIM and APN',
        subtitle: sim.isEmpty ? 'SIM, APN and roaming' : sim,
        live: _live,
        children: (_) => [
          SimSettings(key: const ValueKey('sim-settings'), controls: _controls),
        ],
      ),
      ModemPageRow(
        title: 'Speed options',
        subtitle: 'Carrier aggregation and 256QAM',
        live: _live,
        children: (_) => [
          SpeedOptions(
            key: const ValueKey('speed-options'),
            controls: _controls,
          ),
        ],
      ),
      ModemPageRow(
        title: 'Modem details',
        subtitle: 'All readings, addresses and restart',
        live: _live,
        children: (_) => _details(_live.value ?? m, online),
      ),
    ]);
  }

  List<Widget> _towers(ModemMetrics m, AppState app) => [
    ...valueRows('The tower', Icons.cell_tower, [
      ('Network', m['operator_name']),
      ('Tower (eNB)', m['enbid']),
      ('Cell ID', m['cid_dec']),
      ('Area (TAC)', m['tac_dec']),
      ('Roaming', m['roaming'] == '1' ? 'Yes' : null),
    ]),
    ...valueRows('Carriers', Icons.stacked_bar_chart, [
      for (final c in m.carriers)
        (c.label, '${c.band}\nPCI ${c.pci ?? '-'}  EARFCN ${c.earfcn ?? '-'}'),
    ]),
    LockControls(
      key: const ValueKey('lock-controls'),
      locks: _locks,
      nearby: FiveGBands.nearby(m.raw['neighbors']),
      towers: PreferredTowers(app),
    ),
  ];

  List<Widget> _details(ModemMetrics m, Future<bool> Function() online) => [
    ...valueRows('Connection', Icons.public, [
      ('IPv4', m['ipaddr']),
      ('IPv6', m['ipaddr6']),
      ('APN', m['iface_apn']),
      ('Downloaded', m['rx']),
      ('Uploaded', m['tx']),
      ('Protocol', m['protocol']),
      (
        'MCC / MNC',
        m['operator_mcc'] == null
            ? null
            : '${m['operator_mcc']} / ${m['operator_mnc'] ?? '-'}',
      ),
    ]),
    ...valueRows('Other signal readings', Icons.signal_cellular_alt, [
      ('Power (RSSI)', _unit(m['rssi'], 'dBm')),
      ('Bars (CSQ)', m['csq']),
    ]),
    ...valueRows('Modem and SIM', Icons.memory, [
      ('Model', m['modem']),
      ('Firmware', m['firmware']),
      ('Temperature', m.temperature),
      ('SIM slot', m['simslot']),
      ('IMEI', m['imei']),
      ('IMSI', m['imsi']),
      ('ICCID', m['iccid']),
    ]),
    const SizedBox(height: 24),
    ModemActions(
      key: const ValueKey('modem-restart'),
      controls: _controls,
      online: online,
      parts: const {ModemPart.restart},
    ),
  ];

  Widget _summary(ModemMetrics m) {
    final ks = context.ks;
    final pct = m.signalPercent;
    final line = [
      switch (m.rsrpQuality) {
        SignalQuality.excellent => 'Excellent signal',
        SignalQuality.good => 'Good signal',
        SignalQuality.fair => 'Fair signal',
        SignalQuality.poor => 'Weak signal',
        SignalQuality.unknown => null,
      },
      m.connected ? connectedFor(m['conn_time_sec']) : 'not connected',
    ].nonNulls.join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            KsDot(m.connected ? ks.ok : ks.bad),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                [
                  m['operator_name'] ?? 'Mobile network',
                  m['mode']?.split('|').first.trim() ?? 'No service',
                ].join(' · '),
                style: KeystoneType.bodyStrong(ks.tx),
              ),
            ),
            if (pct != null)
              Text('$pct%', style: KeystoneType.secondary(ks.tx2)),
          ],
        ),
        if (pct != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: ks.line,
              color: m.rsrpQuality.tone(ks),
            ),
          ),
        ],
        if (line.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(line, style: KeystoneType.secondary(ks.mu)),
        ],
      ],
    );
  }
}

String? _unit(String? v, String unit) => v == null ? null : '$v $unit';

class _Sections extends StatelessWidget {
  const _Sections(this.children);
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(children: children);
}
