// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';
import '../devices_usage/device_usage_client.dart';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/devices/device_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../datacap/data_plan_client.dart';
import '../history/helper_history.dart';
import '../history/history_data.dart';
import '../modem/modem_screen.dart';
import '../noob_rpc.dart';
import '../passwall/passwall_module.dart';
import 'slow_checks.dart';

const _names = {
  SlowCause.weakSignal: 'mobile signal',
  SlowCause.linePing: 'line ping',
  SlowCause.phoneWifi: "this phone's Wi-Fi",
  SlowCause.heavyDevice: 'busy devices',
  SlowCause.proxyOn: 'Passwall',
  SlowCause.fairUse: 'fair-use limit',
  SlowCause.sqm: 'SQM',
};

void _open(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

Map<SlowCause, SlowCheck> routerSlowChecks(AppState app) {
  final now = DateTime.now();
  final recent = HelperHistory(app).load(
    now.subtract(const Duration(hours: 1)),
    now.add(const Duration(hours: 1)),
  );
  Future<Map<String, dynamic>?> global(String config) async {
    final s = await noobUciSections(app, config);
    return s.where((x) => x['.type'] == 'global').firstOrNull;
  }

  return {
    SlowCause.weakSignal: () async {
      final p = (await recent)?.points.where((p) => p.rsrp != null).lastOrNull;
      if (p == null) throw StateError('no signal readings');
      return signalFinding(
        rsrp: p.rsrp,
        sinr: p.sinr,
        fix: SlowFix('Check the modem', (c) => _open(c, const ModemScreen())),
      );
    },
    SlowCause.linePing: () async {
      final pings = <double>[
        for (final p in (await recent)?.points ?? const <HistoryPoint>[])
          ?p.ping,
      ];
      if (pings.isEmpty) throw StateError('no ping readings');
      return linePingFinding(
        pings.skip(pings.length > 5 ? pings.length - 5 : 0).toList(),
      );
    },
    SlowCause.phoneWifi: () async {
      final mine = {
        for (final i in await NetworkInterface.list())
          if (i.name.startsWith('wlan'))
            for (final a in i.addresses) a.address,
      };
      final me = app.clients
          .where((c) => mine.contains(c.ipAddress))
          .firstOrNull;
      if (me?.signalDbm == null) throw StateError('phone not found');
      return phoneWifiFinding(me!.signalDbm);
    },
    SlowCause.heavyDevice: () async {
      final r = await noobCall(app, 'luci.bandix', 'getStatus');
      final rows = [
        for (final d in r['d'] is List ? r['d'] as List : const [])
          if (d is Map && d['mac'] != null)
            (
              '${d['mac']}'.toLowerCase(),
              (((d['t_rx_r'] as num?) ?? 0) + ((d['t_tx_r'] as num?) ?? 0)) *
                  8.0,
            ),
      ];
      if (rows.isEmpty) throw StateError('no traffic readings');
      rows.sort((a, b) => b.$2.compareTo(a.$2));
      final total = rows.fold(0.0, (s, r) => s + r.$2);
      final top = rows.first;
      final c = app.clients
          .where((c) => c.macAddress.toLowerCase() == top.$1)
          .firstOrNull;
      final month = await DeviceUsageClient.of(
        app,
      ).usage().then((u) => u?.of(top.$1), onError: (_) => null);
      final f = heavyDeviceFinding(
        name: c?.displayName ?? top.$1,
        mac: top.$1,
        deviceBps: top.$2,
        totalBps: total,
        pause: (ctx, mac) => _open(ctx, DeviceScreen(mac: mac)),
      );
      if (f == null || month == null) return f;
      return SlowFinding(
        cause: f.cause,
        score: f.score,
        detail: '${f.detail} ${sizeWords(month.total)} so far this period.',
        fix: f.fix,
      );
    },
    SlowCause.proxyOn: () async {
      for (final (config, kind) in [
        ('passwall2', PasswallKind.v2),
        ('passwall', PasswallKind.v1),
      ]) {
        try {
          final g = await global(config);
          if (g?['enabled'] == '1') {
            return proxyFinding(
              true,
              fix: SlowFix(
                'Open Passwall',
                (c) => _open(c, PasswallScreen(kind: kind)),
              ),
            );
          }
        } catch (_) {}
      }
      return null;
    },
    SlowCause.fairUse: () async {
      final d = await DataPlanClient.of(app).load();
      if (d == null) throw StateError('no data plan');
      return fairUseFinding(d.active);
    },
    SlowCause.sqm: () async {
      final queues = await noobUciSections(app, 'sqm');
      for (final q in queues) {
        if (q['enabled'] == '1') {
          return sqmFinding(
            enabled: true,
            downloadKbit: int.tryParse('${q['download']}') ?? 0,
          );
        }
      }
      return null;
    },
  };
}

class SlowScreen extends StatefulWidget {
  const SlowScreen({super.key, required this.checks});

  final Map<SlowCause, SlowCheck> Function() checks;

  @override
  State<SlowScreen> createState() => _SlowScreenState();
}

class _SlowScreenState extends State<SlowScreen> {
  SlowReport? _report;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _report = null);
    final r = await runSlowChecks(widget.checks());
    if (mounted) setState(() => _report = r);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final r = _report;
    return KsPage(
      title: 'Why is it slow?',
      onRefresh: _run,
      children: [
        if (r == null) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 10),
          Text(
            'Checking the signal, the line, Wi-Fi and devices…',
            style: KeystoneType.secondary(ks.mu),
          ),
        ] else ...[
          Text(slowHeadline(r), style: KeystoneType.sheetTitle(ks.tx)),
          if (r.top?.fix case final fix?) ...[
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => fix.open(context),
              child: Text(fix.label),
            ),
          ],
          if (r.others.isNotEmpty) ...[
            const KsSection('Also worth knowing'),
            for (final f in r.others)
              KsRow(
                title: f.detail,
                onTap: f.fix == null ? null : () => f.fix!.open(context),
              ),
          ],
          if (r.couldntCheck.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              "Couldn't check: ${r.couldntCheck.map((c) => _names[c]).join(', ')}",
              style: KeystoneType.caption(ks.mu),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _run, child: const Text('Check again')),
        ],
      ],
    );
  }
}
