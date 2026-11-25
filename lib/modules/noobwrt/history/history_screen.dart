// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../cellular/preferred_towers.dart';
import 'history_analysis.dart';
import 'helper_installer.dart';
import 'helper_sheet.dart';
import 'history_chart.dart';
import 'history_data.dart';

const _maxPoints = 400;
final _ranges = {
  const Duration(hours: 6): '6 h',
  const Duration(hours: 24): '24 h',
  const Duration(days: 7): '7 d',
  const Duration(days: 30): '30 d',
};
const _failed =
    "Couldn't reach the router. Check you're on its Wi-Fi, then try again.";

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.load,
    this.towers,
    this.helper,
    this.now,
    this.maxDays = 7,
  });

  final Future<HistoryData?> Function(DateTime from, DateTime to) load;
  final PreferredTowers? towers;
  final HelperInstaller? helper;
  final DateTime Function()? now;
  final int maxDays;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Duration _range = const Duration(hours: 24);
  HistoryData? _data;
  String? _summary;
  DateTime? _from, _to;
  bool _loading = true, _empty = false, _failedLoad = false;
  int _seq = 0;
  HistoryPoint? _pick;
  String? _version;
  bool _versionKnown = false;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
    _helperVersion();
  }

  Future<void> _helperVersion() async {
    final v = await widget.helper?.installed();
    if (!mounted) return;
    setState(() {
      _version = v;
      _versionKnown = true;
    });
  }

  Future<void> _openHelper() async {
    await showHelperSheet(context, widget.helper!);
    if (mounted) await Future.wait([_helperVersion(), _load()]);
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final to = _now();
    final from = to.subtract(_range);
    setState(() => _loading = true);
    try {
      final d = await widget.load(from, to);
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _failedLoad = false;
        _empty = d == null;
        _data = d;
        _summary = d == null
            ? null
            : historySummary(d.points, slowPeriods(d.points));
        _from = from;
        _to = to;
        _pick = null;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _failedLoad = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final d = _data;
    return KsPage(
      title: 'History',
      onRefresh: _load,
      children: [
        KsSegmented<Duration>(
          label: 'Show the last',
          value: _range,
          options: [
            for (final e in _ranges.entries)
              if (e.key.inDays < 30 || widget.maxDays >= 30) (e.key, e.value),
          ],
          onChanged: (r) {
            if (r == _range) return;
            setState(() => _range = r);
            _load();
          },
        ),
        SizedBox(
          height: 14,
          child: _loading && d != null
              ? const Align(child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        if (d == null)
          _alone(ks)
        else ...[
          if (_failedLoad)
            KsNote(_staleNote(), action: 'Try again', onAction: _load),
          ..._content(ks, d),
        ],
        if (widget.helper != null) ...[
          const SizedBox(height: 24),
          KsRow(
            title: 'Signal history on the router',
            subtitle: !_versionKnown
                ? null
                : _version == null
                ? 'Not installed'
                : 'Version $_version',
            onTap: _openHelper,
          ),
        ],
      ],
    );
  }

  Widget _alone(KeystoneColors ks) {
    final Widget child;
    if (_failedLoad) {
      child = Column(
        children: [
          Text(
            _failed,
            textAlign: TextAlign.center,
            style: KeystoneType.body(ks.mu),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    } else if (_empty) {
      child = Text(
        'No history on this router yet.',
        textAlign: TextAlign.center,
        style: KeystoneType.body(ks.mu),
      );
    } else {
      child = const CircularProgressIndicator();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Center(child: child),
    );
  }

  String _staleNote() {
    final shown = _to!.difference(_from!);
    if (shown == _range) return _failed;
    return "Couldn't load the last ${_ranges[_range]}. "
        'Still showing the last ${_ranges[shown]}.';
  }

  String _when(DateTime t) {
    final n = _now();
    final today = t.year == n.year && t.month == n.month && t.day == n.day;
    return DateFormat(today ? 'HH:mm' : 'd MMM HH:mm').format(t);
  }

  List<Widget> _content(KeystoneColors ks, HistoryData d) {
    final from = _from!, to = _to!;
    final shown = thin(d.points, _maxPoints);
    final slow = slowPeriods(d.points);
    final pings = _values(shown, (p) => p.ping);
    final rsrps = _values(shown, (p) => p.rsrp);
    final sinrs = _values(shown, (p) => p.sinr);
    final hasSignal = rsrps.isNotEmpty || sinrs.isNotEmpty;
    final zone = Theme.of(context).brightness == Brightness.dark ? .12 : .08;
    final pingTitle = d.pingMethod == 'tcp' ? 'Connection time' : 'Line ping';
    final summary = _summary;
    final pingTop = pings.fold<double>(100, (a, b) => b > a ? b : a);
    final used = towerSummary(d.points);
    final best = bestTower(used);
    final label = KeystoneType.caption(ks.mu);
    final span = _ranges[to.difference(from)] ?? '';
    final month = DateFormat('yyyy-MM').format(_now());
    final traffic = d.traffic.where((s) => s.month == month).toList();
    final slowWords = slow.isEmpty
        ? ''
        : ', ${slow.length} slow ${slow.length == 1 ? 'period' : 'periods'}';

    Widget chart(
      String key,
      String semantics,
      double height,
      HistoryChart painter,
    ) => Semantics(
      container: true,
      excludeSemantics: true,
      label: semantics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) => GestureDetector(
              onTapUp: (e) => _tap(
                shown,
                from,
                to,
                e.localPosition.dx,
                painter.plotWidth(c.maxWidth),
              ),
              child: CustomPaint(
                key: ValueKey(key),
                size: Size(c.maxWidth, height),
                painter: painter,
              ),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, c) => Padding(
              padding: EdgeInsets.only(
                right: c.maxWidth - painter.plotWidth(c.maxWidth),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(_when(from), style: label)),
                  Text('Now', style: label),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    List<Widget> signal(
      String key,
      String title,
      String name,
      String unit,
      List<double> seen,
      double? Function(HistoryPoint) value,
      _Zones z,
    ) => [
      KsSection(title, trailing: Text(unit, style: label)),
      chart(
        key,
        '$name, last $span: ${_n(seen.reduce(min))} '
        'to ${_n(seen.reduce(max))} $unit$slowWords',
        96,
        HistoryChart(
          points: shown,
          from: from,
          to: to,
          slow: slow,
          slowColor: ks.warn,
          grid: ks.line,
          labelStyle: label,
          ticks: true,
          top: _n(z.hi),
          bottom: _n(z.lo),
          pick: _pick?.t,
          bands: [
            (
              lo: z.good,
              hi: z.hi,
              color: ks.ok.withValues(alpha: zone),
              label: 'good',
            ),
            (
              lo: z.fair,
              hi: z.good,
              color: ks.warn.withValues(alpha: zone),
              label: 'fair',
            ),
            (
              lo: z.lo,
              hi: z.fair,
              color: ks.bad.withValues(alpha: zone),
              label: 'poor',
            ),
          ],
          line: (value: value, lo: z.lo, hi: z.hi, color: ks.ac, width: 2),
        ),
      ),
    ];

    return [
      if (d.since != null && d.since!.isAfter(from))
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Since the router restarted at ${_when(d.since!)}.',
            style: KeystoneType.secondary(ks.mu),
          ),
        ),
      if (summary != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            summary,
            key: const ValueKey('summary'),
            style: KeystoneType.body(ks.tx),
          ),
        ),
      if (hasSignal || pings.isNotEmpty) _readoutSlot(ks),
      if (rsrps.isNotEmpty)
        ...signal(
          'rsrp-chart',
          'Strength (RSRP)',
          'Strength',
          'dBm',
          rsrps,
          (p) => p.rsrp,
          _rsrpZones,
        ),
      if (sinrs.isNotEmpty)
        ...signal(
          'sinr-chart',
          'Clearness (SINR)',
          'Clearness',
          'dB',
          sinrs,
          (p) => p.sinr,
          _sinrZones,
        ),
      if (pings.isNotEmpty) ...[
        KsSection(pingTitle, trailing: Text('ms', style: label)),
        chart(
          'ping-chart',
          '$pingTitle, last $span: ${pings.reduce(min).round()} '
              'to ${pings.reduce(max).round()} ms$slowWords',
          72,
          HistoryChart(
            points: shown,
            from: from,
            to: to,
            slow: slow,
            slowColor: ks.warn,
            grid: ks.line,
            labelStyle: label,
            top: '${pingTop.round()}',
            bottom: '0',
            pick: _pick?.t,
            line: (
              value: (p) => p.ping,
              lo: 0,
              hi: pingTop,
              color: ks.ac,
              width: 1.6,
            ),
          ),
        ),
      ],
      if (!hasSignal && pings.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Text(
            'Nothing recorded in this time.',
            style: KeystoneType.body(ks.mu),
          ),
        ),
      if (used.isNotEmpty) ...[
        const KsSection('Towers'),
        for (final u in used) ...[
          KsRow(
            title: 'PCI ${u.pci} · EARFCN ${u.earfcn}',
            subtitle: [
              ?u.band,
              _duration(u.time),
              if (u.avgRsrp != null) 'avg ${u.avgRsrp!.round()} dBm',
              if (u == best) 'best signal',
            ].join(' · '),
          ),
          if (u == best && widget.towers != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _prefer(u),
                child: const Text('Add to Preferred towers'),
              ),
            ),
        ],
      ],
      if (traffic.isNotEmpty) ...[
        const KsSection('Data this month'),
        for (final s in traffic)
          KsRow(
            title: s.sim == 'helper' && s.label == 'Router'
                ? "Router's mobile line"
                : s.label,
            subtitle: '${_gb(s.down)} down · ${_gb(s.up)} up',
          ),
      ],
    ];
  }

  void _tap(
    List<HistoryPoint> shown,
    DateTime from,
    DateTime to,
    double dx,
    double width,
  ) {
    if (shown.isEmpty || width <= 0) return;
    final span = to.difference(from).inMilliseconds;
    final at = from.add(
      Duration(milliseconds: (span * (dx / width).clamp(0.0, 1.0)).round()),
    );
    var best = shown.first;
    for (final p in shown) {
      if (p.t.difference(at).abs() < best.t.difference(at).abs()) best = p;
    }
    setState(() => _pick = best);
  }

  Widget _readoutSlot(KeystoneColors ks) {
    final style = KeystoneType.secondary(_pick == null ? ks.mu : ks.tx2);
    final scaler = MediaQuery.textScalerOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: LayoutBuilder(
        builder: (context, c) {
          final widest = TextPainter(
            text: TextSpan(
              text: _readout(
                HistoryPoint(
                  t: _now().subtract(const Duration(days: 6)),
                  rsrp: -140,
                  sinr: -20.5,
                  ping: 9999,
                  pci: '1007',
                  earfcn: '2079999',
                ),
              ),
              style: style,
            ),
            textScaler: scaler,
            textDirection: Directionality.of(context),
          )..layout(maxWidth: c.maxWidth);
          final height = widest.height;
          widest.dispose();
          return SizedBox(
            height: height,
            child: Text(
              _pick == null ? 'Tap a chart for details.' : _readout(_pick!),
              key: const ValueKey('readout'),
              style: style,
            ),
          );
        },
      ),
    );
  }

  String _readout(HistoryPoint p) => [
    _when(p.t),
    if (p.rsrp?.isFinite ?? false) 'RSRP ${_n(p.rsrp!)} dBm',
    if (p.sinr?.isFinite ?? false)
      'SINR ${p.sinr!.toStringAsFixed(1).replaceFirst('-', '−')} dB',
    if (p.ping?.isFinite ?? false) 'ping ${p.ping!.round()} ms',
    if (p.pci != null) 'PCI ${p.pci} · EARFCN ${p.earfcn ?? '-'}',
  ].join(' · ');

  Future<void> _prefer(TowerUse u) async {
    try {
      await widget.towers!.add(u.earfcn, u.pci);
      if (mounted) ksSay(context, 'Added to Preferred towers.');
    } catch (e) {
      if (mounted) ksSay(context, "The router didn't take that: $e");
    }
  }
}

typedef _Zones = ({double lo, double fair, double good, double hi});

const _Zones _rsrpZones = (lo: -125, fair: -105, good: -90, hi: -70);
const _Zones _sinrZones = (lo: -5, fair: 0, good: 13, hi: 30);

List<double> _values(List<HistoryPoint> p, double? Function(HistoryPoint) v) =>
    [
      for (final e in p)
        if (v(e)?.isFinite ?? false) v(e)!,
    ];

String _cap(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

String? historySummary(List<HistoryPoint> p, List<(DateTime, DateTime)> slow) {
  final rsrp = _values(p, (e) => e.rsrp)..sort();
  final sinr = _values(p, (e) => e.sinr)..sort();
  if (rsrp.isEmpty && sinr.isEmpty) return null;
  double at(List<double> s, double q) => s[((s.length - 1) * q).round()];
  double mid(List<double> s) => (s[(s.length - 1) ~/ 2] + s[s.length ~/ 2]) / 2;
  int grade(List<double> s, _Zones z) {
    if (s.isEmpty) return 0;
    final m = mid(s);
    return m >= z.good ? 0 : (m >= z.fair ? 1 : 2);
  }

  final quality = const [
    'good',
    'fair',
    'poor',
  ][max(grade(rsrp, _rsrpZones), grade(sinr, _sinrZones))];
  final head = rsrp.isEmpty
      ? '${_cap(quality)}.'
      : at(rsrp, .9) - at(rsrp, .1) <= 8
      ? 'Steady and $quality.'
      : 'Up and down, mostly $quality.';
  final values = [
    if (rsrp.isNotEmpty) 'strength about ${_n(mid(rsrp))} dBm',
    if (sinr.isNotEmpty) 'clearness about ${_n(mid(sinr))} dB',
  ].join(', ');
  final drops = switch (slow.length) {
    0 => 'No slow periods.',
    1 => '1 slow period.',
    final n => '$n slow periods.',
  };
  return '$head ${_cap(values)}. $drops';
}

String _n(num v) => v.round().toString().replaceFirst('-', '−');

String _gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(2)} GB';

String _duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}
