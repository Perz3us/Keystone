import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/screens/home/home_signal.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';
import 'package:yet_another_luci_app/widgets/keystone/speed_chart.dart';

class HomeShortcut {
  const HomeShortcut(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.routerName,
    required this.status,
    required this.lights,
    this.model,
    required this.shortcuts,
    required this.downMbps,
    required this.upMbps,
    required this.downHistory,
    required this.upHistory,
    this.onRouterMenu,
    this.onSettings,
    this.onInternet,
    this.onDevices,
    this.onRouter,
    this.onAction,
    this.usage,
    this.onRefresh,
    this.address,
    this.onOpenWifiSettings,
    this.onEditShortcuts,
    this.prefs = const HomePrefs(),
    this.devices = const [],
    this.signal,
    this.onSignal,
  });

  final String routerName;
  final String? model;
  final HomeStatus status;
  final RouterLights lights;
  final List<HomeShortcut> shortcuts;
  final double downMbps;
  final double upMbps;
  final List<double> downHistory;
  final List<double> upHistory;
  final VoidCallback? onRouterMenu;
  final VoidCallback? onSettings;
  final VoidCallback? onInternet;
  final VoidCallback? onDevices;
  final VoidCallback? onRouter;
  final VoidCallback? onAction;

  final WanUsage? usage;
  final Future<void> Function()? onRefresh;

  final String? address;

  final VoidCallback? onOpenWifiSettings;
  final VoidCallback? onEditShortcuts;

  final HomePrefs prefs;

  final List<FlowDevice> devices;

  final SignalOverview? signal;
  final VoidCallback? onSignal;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final big = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final beside = _beside();
    final side = math.max(20.0, (MediaQuery.sizeOf(context).width - 600) / 2);
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(side, 8, side, 24),
      children: [
        _topBar(ks),
        const SizedBox(height: 20),
        Text(status.headline, style: KeystoneType.headline(ks.tx)),
        const SizedBox(height: 6),
        Text(status.detail, style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 20),
        _picture(ks, big ? null : beside),
        if (status.unreachable)
          ..._unreachable(ks)
        else ...[
          if (status.tip != null) ...[const SizedBox(height: 20), _problem(ks)],
          if (big && beside != null) ...[const SizedBox(height: 16), beside],
          if (prefs.signal && signal != null) ...[
            const SizedBox(height: 16),
            SignalDetails(signal!, prefs: prefs, onTap: onSignal),
          ],
          if (prefs.shortcuts && shortcuts.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Shortcuts',
                    style: KeystoneType.secondary(ks.mu),
                  ),
                ),
                if (onEditShortcuts != null)
                  TextButton(
                    onPressed: onEditShortcuts,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text('Edit', style: KeystoneType.secondary(ks.ac)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (final row in _rows(
              MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 2 : 4,
            )) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in row)
                    Expanded(
                      child: s == null
                          ? const SizedBox.shrink()
                          : _ShortcutButton(s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
          if (prefs.speed) ...[const SizedBox(height: 28), _speed(ks)],
          if (prefs.usage && usage != null) ...[
            SizedBox(height: prefs.speed ? 24 : 28),
            _usage(ks, usage!),
          ],
        ],
      ],
    );
    return SafeArea(
      bottom: false,
      child: onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: onRefresh!, child: list),
    );
  }

  List<List<HomeShortcut?>> _rows(int columns) => [
    for (var i = 0; i < shortcuts.length; i += columns)
      [
        for (var j = i; j < i + columns; j++)
          j < shortcuts.length ? shortcuts[j] : null,
      ],
  ];

  List<Widget> _unreachable(KeystoneColors ks) {
    Widget check(int n, String q, String a) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ks.tint, shape: BoxShape.circle),
            child: Text('$n', style: KeystoneType.caption(ks.tx2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q, style: KeystoneType.body(ks.tx)),
                Text(a, style: KeystoneType.caption(ks.mu)),
              ],
            ),
          ),
        ],
      ),
    );
    return [
      const SizedBox(height: 24),
      check(
        1,
        "Is this phone on the router's Wi-Fi?",
        "Mobile data can't reach ${address ?? 'the router'}",
      ),
      check(2, 'Is the router on?', 'The lights on the front should be lit'),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: onRefresh,
        style: FilledButton.styleFrom(
          backgroundColor: ks.tx,
          foregroundColor: ks.bg,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text('Try again', style: KeystoneType.bodyStrong(ks.bg)),
      ),
      if (onOpenWifiSettings != null) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: onOpenWifiSettings,
          style: FilledButton.styleFrom(
            backgroundColor: ks.tint,
            foregroundColor: ks.tx,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.wifi_rounded, size: 20),
          label: Text(
            'Open Wi-Fi settings',
            style: KeystoneType.bodyStrong(ks.tx),
          ),
        ),
      ],
    ];
  }

  Widget _topBar(KeystoneColors ks) => Row(
    children: [
      Expanded(
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRouterMenu,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              foregroundColor: ks.tx,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    routerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KeystoneType.bodyStrong(
                      ks.tx,
                    ).copyWith(fontSize: 18),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 20, color: ks.mu),
              ],
            ),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Settings',
        onPressed: onSettings,
        icon: Icon(Icons.settings_outlined, color: ks.mu, size: 22),
      ),
    ],
  );

  Widget _problem(KeystoneColors ks) => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
    decoration: BoxDecoration(
      color: ks.node,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ks.line),
    ),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(status.tip!, style: KeystoneType.body(ks.tx2)),
        ),
        FilledButton(
          onPressed: onAction,
          style: FilledButton.styleFrom(
            backgroundColor: ks.tx,
            foregroundColor: ks.bg,
            minimumSize: const Size(44, 44),
            shape: const StadiumBorder(),
          ),
          child: Text(
            _actionLabel(status.action),
            style: KeystoneType.bodyStrong(ks.bg).copyWith(fontSize: 14),
          ),
        ),
      ],
    ),
  );

  static String _actionLabel(HomeAction? a) => switch (a) {
    HomeAction.findSpot => 'Find a spot',
    HomeAction.openModem => 'Check the modem',
    null => 'Open',
  };

  Widget _speed(KeystoneColors ks) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: ks.ok, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Right now', style: KeystoneType.bodyStrong(ks.tx)),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 20,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [_rate(ks, downMbps, 'down'), _rate(ks, upMbps, 'up')],
      ),
      if (prefs.chart) ...[
        const SizedBox(height: 14),
        SizedBox(
          height: 64,
          child: SpeedChart(down: downHistory, up: upHistory),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          children: [
            Text('— Download', style: KeystoneType.caption(ks.ac)),
            Text('··· Upload', style: KeystoneType.caption(ks.mu)),
          ],
        ),
      ],
    ],
  );

  Widget _usage(KeystoneColors ks, WanUsage u) {
    final downShare = u.total == 0 ? 0.5 : u.down / u.total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ks.node,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ks.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data used', style: KeystoneType.secondary(ks.mu)),
          const SizedBox(height: 4),
          Text(sizeWords(u.total), style: KeystoneType.title(ks.tx)),
          Text(
            'since the internet came up ${onlineFor(u.seconds)} ago',
            style: KeystoneType.secondary(ks.mu),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: (downShare * 1000).round().clamp(1, 999),
                    child: ColoredBox(
                      key: const Key('usage-down'),
                      color: ks.ac,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: ((1 - downShare) * 1000).round().clamp(1, 999),
                    child: ColoredBox(
                      color: ks.mu,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(
                '${sizeWords(u.down)} down',
                style: KeystoneType.caption(ks.ac),
              ),
              Text(
                '${sizeWords(u.up)} up',
                style: KeystoneType.caption(ks.tx2),
              ),
              if (u.seconds > 0)
                Text(() {
                  final mbs = prefs.unit == SpeedUnit.mbs;
                  final v = mbs ? u.averageMbps / 8 : u.averageMbps;
                  final n = v.toStringAsFixed(v < 1 ? 2 : 1);
                  return 'Averaged $n ${mbs ? 'MB/s' : 'Mbps'}';
                }(), style: KeystoneType.caption(ks.mu)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _rate(KeystoneColors ks, double mbps, String way) {
    final mbs = prefs.unit == SpeedUnit.mbs;
    final v = mbs ? mbps / 8 : mbps;
    final unit = '${mbs ? 'MB/s' : 'Mbps'} $way';
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1),
          style: KeystoneType.title(ks.tx),
        ),
        const SizedBox(width: 6),
        Text(unit, style: KeystoneType.secondary(ks.mu)),
      ],
    );
  }

  Widget? _beside() {
    final s = signal;
    if (!prefs.beside || s == null) return null;
    final r = SignalReadings(s, items: prefs.besideItems, onTap: onSignal);
    return r.isEmpty ? null : r;
  }

  Widget _picture(KeystoneColors ks, Widget? beside) {
    final problem = switch (status.internet) {
      LinkState.weak => ks.warn,
      LinkState.down => ks.bad,
      _ => null,
    };
    final s = signal;
    final up =
        status.internet == LinkState.ok || status.internet == LinkState.weak;
    final bars = prefs.signalBars && up ? s?.bars : null;
    return HomeFlow(
      beside: beside,
      internetBars: bars,
      barsColor: bars == null || s!.rsrpQuality == SignalQuality.unknown
          ? null
          : s.rsrpQuality.tone(ks),
      layout: prefs.layout,
      flow: prefs.flow,
      devices: devices,
      more: math.max(0, status.devices - devices.length),
      internetLine: bars == null
          ? status.internetLine
          : signalLine(s!) ?? status.internetLine,
      internetMbps: math.max(
        downMbps + upMbps,
        devices.fold(0.0, (s, d) => s + d.mbps),
      ),
      internetIcon: status.internet == LinkState.weak
          ? Icons.cell_tower_rounded
          : Icons.public_rounded,
      lights: lights,
      model: model,
      problem: problem,
      unknown: status.internet == LinkState.unknown,
      unreachable: status.unreachable,
      onInternet: onInternet,
      onRouter: onRouter,
      onMore: onDevices,
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton(this.s);
  final HomeShortcut s;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: s.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: ks.tint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(s.icon, size: 22, color: ks.tx2),
            ),
            const SizedBox(height: 6),
            Text(
              s.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
              style: KeystoneType.caption(ks.tx2),
            ),
          ],
        ),
      ),
    );
  }
}
