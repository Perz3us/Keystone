// SPDX-License-Identifier: GPL-3.0-or-later

import 'history_data.dart';

const _maxGap = Duration(minutes: 10);
const _minSlow = Duration(minutes: 10);
const _minBest = Duration(minutes: 30);

class TowerUse {
  const TowerUse({
    required this.pci,
    required this.earfcn,
    this.band,
    required this.time,
    this.avgRsrp,
  });
  final String pci, earfcn;
  final String? band;
  final Duration time;
  final double? avgRsrp;
}

List<(DateTime, DateTime)> slowPeriods(List<HistoryPoint> p) {
  final out = <(DateTime, DateTime)>[];
  DateTime? start, last;
  void close() {
    if (start != null && last!.difference(start!) >= _minSlow) {
      out.add((start!, last!));
    }
    start = last = null;
  }

  for (final e in p) {
    if (last != null && e.t.difference(last!) > _maxGap) close();
    if (e.rsrp == null && e.sinr == null && e.ping == null) continue;
    final slow =
        (e.rsrp ?? 0) < -110 || (e.sinr ?? 0) < 0 || (e.ping ?? 0) > 150;
    if (!slow) {
      close();
      continue;
    }
    start ??= e.t;
    last = e.t;
  }
  close();
  return out;
}

List<TowerUse> towerSummary(List<HistoryPoint> p) {
  final time = <String, Duration>{};
  final sum = <String, double>{};
  final n = <String, int>{};
  final first = <String, HistoryPoint>{};
  for (var i = 0; i < p.length; i++) {
    final e = p[i];
    if (e.pci == null || e.earfcn == null) continue;
    final k = '${e.pci}|${e.earfcn}';
    first.putIfAbsent(k, () => e);
    time.putIfAbsent(k, () => Duration.zero);
    if (e.rsrp != null) {
      sum[k] = (sum[k] ?? 0) + e.rsrp!;
      n[k] = (n[k] ?? 0) + 1;
    }
    if (i + 1 < p.length) {
      final gap = p[i + 1].t.difference(e.t);
      time[k] = time[k]! + (gap > _maxGap ? _maxGap : gap);
    }
  }
  return [
    for (final k in time.keys)
      TowerUse(
        pci: first[k]!.pci!,
        earfcn: first[k]!.earfcn!,
        band: first[k]!.band,
        time: time[k]!,
        avgRsrp: n[k] == null ? null : sum[k]! / n[k]!,
      ),
  ]..sort((a, b) {
    final c = b.time.compareTo(a.time);
    if (c != 0) return c;
    final d = a.pci.compareTo(b.pci);
    return d != 0 ? d : a.earfcn.compareTo(b.earfcn);
  });
}

TowerUse? bestTower(List<TowerUse> t) {
  TowerUse? best;
  for (final e in t) {
    if (e.time < _minBest || e.avgRsrp == null) continue;
    if (best == null || e.avgRsrp! > best.avgRsrp!) best = e;
  }
  return best;
}

List<HistoryPoint> thin(List<HistoryPoint> p, int max) {
  if (p.isEmpty) return p;
  if (max <= 0) return const [];
  if (p.length <= max) return p;
  final keep = <int>{};
  for (var i = 1; i < p.length; i++) {
    if (p[i].pci != p[i - 1].pci || p[i].earfcn != p[i - 1].earfcn) {
      keep.add(i);
    }
  }
  if (keep.length >= max) {
    return [for (final i in (keep.toList()..sort()).take(max)) p[i]];
  }
  final buckets = max - keep.length;
  for (var b = 0; b < buckets; b++) {
    final from = b * p.length ~/ buckets;
    final to = (b + 1) * p.length ~/ buckets;
    var pick = from;
    for (var i = from; i < to; i++) {
      final r = p[i].rsrp;
      if (r != null && (p[pick].rsrp == null || r < p[pick].rsrp!)) pick = i;
    }
    keep.add(pick);
  }
  final idx = keep.toList()..sort();
  return [for (final i in idx) p[i]];
}
