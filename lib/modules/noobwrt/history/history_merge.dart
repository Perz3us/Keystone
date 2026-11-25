// SPDX-License-Identifier: GPL-3.0-or-later

import 'history_data.dart';

Future<HistoryData?> loadHistory(
  List<HistorySource> sources,
  DateTime from,
  DateTime to,
) async {
  final results = await Future.wait([
    for (final s in sources)
      s
          .load(from, to)
          .then<(HistoryData?, Object?, StackTrace?)>(
            (d) => (d, null, null),
            onError: (Object e, StackTrace st) => (null, e, st),
          ),
  ]);
  HistoryData? out;
  for (final r in results) {
    out = out == null ? r.$1 : mergeHistory(out, r.$1);
  }
  final failed = results.where((r) => r.$2 != null).firstOrNull;
  if (out == null && failed != null) {
    Error.throwWithStackTrace(failed.$2!, failed.$3!);
  }
  return out;
}

const _near = Duration(minutes: 3);

HistoryData? mergeHistory(HistoryData? fiveG, HistoryData? helper) {
  if (fiveG == null || helper == null) return fiveG ?? helper;
  final first = fiveG.points.isEmpty ? null : fiveG.points.first.t;
  final older = first == null
      ? helper.points
      : helper.points.where((p) => p.t.isBefore(first)).toList();
  var helperPing = older.any((p) => p.ping != null);
  final h = helper.points;
  var j = 0;
  final filled = <HistoryPoint>[];
  for (final p in fiveG.points) {
    if ((p.ping != null && p.rsrp != null && p.sinr != null) || h.isEmpty) {
      filled.add(p);
      continue;
    }
    while (j + 1 < h.length &&
        h[j + 1].t.difference(p.t).abs() <= h[j].t.difference(p.t).abs()) {
      j++;
    }
    final n = h[j];
    if (n.t.difference(p.t).abs() > _near) {
      filled.add(p);
      continue;
    }
    if (p.ping == null && n.ping != null) helperPing = true;
    filled.add(
      HistoryPoint(
        t: p.t,
        rsrp: p.rsrp ?? n.rsrp,
        sinr: p.sinr ?? n.sinr,
        ping: p.ping ?? n.ping,
        pci: p.pci,
        earfcn: p.earfcn,
        band: p.band,
      ),
    );
  }
  return HistoryData(
    points: [...older, ...filled],
    traffic: fiveG.traffic.isNotEmpty ? fiveG.traffic : helper.traffic,
    since: older.isEmpty
        ? fiveG.since
        : helper.since != null && helper.since!.isBefore(older.first.t)
        ? helper.since
        : older.first.t,
    pingMethod: helperPing ? helper.pingMethod : fiveG.pingMethod,
  );
}
