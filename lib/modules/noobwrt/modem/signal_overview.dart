// SPDX-License-Identifier: GPL-3.0-or-later

import '../cellular/cellular_data.dart';
import '../noob_rpc.dart';
import 'modem_metrics.dart';

class SignalCarrier {
  const SignalCarrier({
    required this.band,
    this.mhz,
    this.width,
    this.cell,
    this.nr = false,
    this.resting = false,
  });

  final String band;
  final String? mhz;
  final double? width;
  final String? cell;
  final bool nr;

  final bool resting;

  static final _name = RegExp(r'\b([bn])(\d+)', caseSensitive: false);
  static final _mhz = RegExp(r'\(\s*([\d.]+)\s*MHz', caseSensitive: false);
  static final _width = RegExp(r'@\s*([\d.]+)');

  static SignalCarrier fromBand(String raw, {String? cell}) {
    final m = _name.firstMatch(raw);
    final nr = m == null
        ? raw.toUpperCase().contains('NR')
        : m[1]!.toLowerCase() == 'n';
    return SignalCarrier(
      band: m == null ? raw.trim() : '${nr ? 'n' : 'B'}${m[2]}',
      mhz: _mhz.firstMatch(raw)?[1],
      width: _positive(_width.firstMatch(raw)?[1]),
      cell: cell,
      nr: nr,
    );
  }

  static SignalCarrier fromQmodem(Carrier c) {
    final nr = c.rat.toUpperCase() == 'NR';
    final n = RegExp(r'\d+').firstMatch(c.band)?[0];
    return SignalCarrier(
      band: n == null ? c.band : '${nr ? 'n' : 'B'}$n',
      width: _positive(RegExp(r'[\d.]+').firstMatch(c.width ?? '')?[0]),
      cell: '${c.pci} ${c.channel}',
      nr: nr,
    );
  }

  static double? _positive(String? v) {
    final n = double.tryParse(v ?? '');
    return n == null || n <= 0 ? null : n;
  }

  SignalCarrier rest() => SignalCarrier(
    band: band,
    mhz: mhz,
    width: width,
    cell: cell,
    nr: nr,
    resting: true,
  );
}

int signalBars(num rsrp) =>
    [-85, -95, -105, -115].where((s) => rsrp >= s).length;

class SignalOverview {
  const SignalOverview({
    this.operatorName,
    this.mode,
    this.percent,
    this.rsrp,
    this.sinr,
    this.rsrq,
    this.carriers = const [],
  });

  final String? operatorName;
  final String? mode;
  final int? percent;
  final String? rsrp, sinr, rsrq;
  final List<SignalCarrier> carriers;

  static SignalOverview fromMetrics(ModemMetrics m) => SignalOverview(
    operatorName: m['operator_name'],
    mode: m['mode'],
    percent: m.signalPercent,
    rsrp: _number(m['rsrp']),
    sinr: _number(m['sinr']),
    rsrq: _number(m['rsrq']),
    carriers: [
      for (final c in m.carriers)
        SignalCarrier.fromBand(c.band, cell: '${c.pci} ${c.earfcn}'),
    ],
  );

  static SignalOverview fromQmodem(
    List<CellEntry> info,
    String? mode,
    List<Carrier> carriers,
  ) {
    String? read(String key) => info
        .where((e) {
          final k = e.key.toLowerCase();
          return !e.isHeading && (k == key || k.endsWith(' $key'));
        })
        .firstOrNull
        ?.value;
    return SignalOverview(
      operatorName: read('isp') ?? read('operator'),
      mode: mode ?? read('network_mode'),
      rsrp: _number(read('rsrp')),
      sinr: _number(read('sinr')),
      rsrq: _number(read('rsrq')),
      carriers: [for (final c in carriers) SignalCarrier.fromQmodem(c)],
    );
  }

  static String? _number(String? v) {
    final s = noobValue(v);
    return s == null ? null : RegExp(r'^-?\d+(\.\d+)?').firstMatch(s)?[0];
  }

  bool get hasReadings => rsrp != null || percent != null;

  bool get idle => carriers.any((c) => c.resting);

  List<SignalCarrier> get active => [
    for (final c in carriers)
      if (!c.resting) c,
  ];

  SignalQuality get rsrpQuality => ModemMetrics({'rsrp': rsrp}).rsrpQuality;
  SignalQuality get sinrQuality => ModemMetrics({'sinr': sinr}).sinrQuality;
  SignalQuality get rsrqQuality => ModemMetrics({'rsrq': rsrq}).rsrqQuality;

  int? get bars {
    final n = double.tryParse(rsrp ?? '');
    if (n != null) return signalBars(n);
    return percent == null ? null : (percent! / 25).ceil().clamp(0, 4);
  }

  String? get type {
    final m = mode?.split('|').first.toUpperCase() ?? '';
    final nr = carriers.where((c) => c.nr).length;
    final lte = carriers.length - nr;
    if (RegExp(r'WCDMA|UMTS|HSPA|HSDPA|HSUPA|3G').hasMatch(m)) return '3G';
    if (RegExp(r'GSM|EDGE|GPRS|2G').hasMatch(m)) return '2G';
    if (nr > 0) return lte > 0 ? '5G NSA' : '5G SA';
    if (RegExp(r'NSA|EN-?DC').hasMatch(m)) return '5G NSA';
    if (RegExp(r'\bSA\b').hasMatch(m)) return '5G SA';
    if (RegExp(r'5G|\bNR').hasMatch(m)) return '5G';
    if (lte > 1) return '4G+';
    if (RegExp(r'LTE-?A\b|LTE\+|4G\+').hasMatch(m)) return '4G+';
    if (m.contains('LTE') || m.contains('4G')) return '4G';
    return lte > 0 ? '4G' : null;
  }

  String? get summary {
    final n = carriers.length;
    if (idle) return 'Idle. $n carriers when last busy';
    if (n == 0) return null;
    final count = n == 1 ? '1 carrier' : '$n carriers combined';
    return switch (type) {
      '5G NSA' => '4G main carrier with 5G added',
      '4G' || '4G+' => 'LTE, $count',
      _ => count,
    };
  }

  String? get bands {
    final b = [for (final c in active) c.band];
    if (b.isEmpty) return null;
    final line = b.length > 3
        ? '${b.first} + ${b.length - 1} more'
        : b.join(' + ');
    return idle ? '$line, idle' : line;
  }

  String? get totalWidth {
    if (active.isEmpty || active.any((c) => c.width == null)) return null;
    return '${_trim(active.fold(0.0, (s, c) => s + c.width!))} MHz';
  }

  List<(String, String)> get rows {
    if (carriers.isEmpty) return const [];
    final rest = carriers.skip(1).toList();
    bool isLeg(SignalCarrier c) => type == '5G NSA' && c.nr;
    final added = rest.where((c) => !isLeg(c)).toList();
    final leg = rest.where(isLeg).toList();
    return [
      ('Main', _line([carriers.first])),
      if (added.isNotEmpty) ('Added', _line(added)),
      if (leg.isNotEmpty) ('5G', _line(leg)),
    ];
  }

  static String _line(List<SignalCarrier> cs) => [
    cs.map((c) => c.band).join(' + '),
    if (cs.length == 1 && cs.first.mhz != null) '${cs.first.mhz} MHz',
    if (cs.every((c) => c.width != null))
      '${_trim(cs.fold(0.0, (s, c) => s + c.width!))} MHz wide',
    if (cs.every((c) => c.resting)) 'idle',
  ].join(' · ');

  static String _trim(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v';

  SignalOverview _with({
    String? mode,
    int? percent,
    String? rsrp,
    String? sinr,
    String? rsrq,
    List<SignalCarrier>? carriers,
  }) => SignalOverview(
    operatorName: operatorName,
    mode: mode ?? this.mode,
    percent: percent ?? this.percent,
    rsrp: rsrp ?? this.rsrp,
    sinr: sinr ?? this.sinr,
    rsrq: rsrq ?? this.rsrq,
    carriers: carriers ?? this.carriers,
  );
}

class SignalMemory {
  static const holdReadings = Duration(minutes: 1);
  static const holdCarriers = Duration(minutes: 10);
  static const idleMbps = 1.0;

  SignalOverview? _last, _busy;
  DateTime? _lastAt, _busyAt;

  void clear() {
    _last = _busy = null;
    _lastAt = _busyAt = null;
  }

  static bool _sameCell(SignalOverview a, SignalOverview b) {
    final x = a.carriers.firstOrNull, y = b.carriers.firstOrNull;
    return x != null && y != null && x.band == y.band && x.cell == y.cell;
  }

  SignalOverview? next(
    SignalOverview? now, {
    required DateTime at,
    required double mbps,
    bool keepCarriers = true,
  }) {
    final last = _last;
    final fresh = last != null && at.difference(_lastAt!) < holdReadings;
    if (now == null || !now.hasReadings) return fresh ? last : null;

    var out = now;
    final hold = fresh && _sameCell(now, last);
    if (hold) {
      out = out._with(
        percent: now.percent ?? last.percent,
        rsrp: now.rsrp ?? last.rsrp,
        sinr: now.sinr ?? last.sinr,
        rsrq: now.rsrq ?? last.rsrq,
      );
    }
    final complete =
        now.rsrp != null && (now.sinr != null || last?.sinr == null);
    if (complete || !hold) {
      _last = now;
      _lastAt = at;
    }

    final busy = _busy;
    if (keepCarriers &&
        busy != null &&
        mbps < idleMbps &&
        at.difference(_busyAt!) < holdCarriers &&
        _sameCell(now, busy) &&
        now.carriers.length < busy.carriers.length) {
      final left = [...now.carriers];
      final merged = <SignalCarrier>[];
      for (final c in busy.carriers) {
        final i = left.indexWhere((x) => x.band == c.band && x.cell == c.cell);
        merged.add(i < 0 ? c.rest() : left.removeAt(i));
      }
      return out._with(mode: busy.mode, carriers: [...merged, ...left]);
    }
    _busy = now.carriers.length > 1 ? now : null;
    _busyAt = at;
    return out;
  }
}
