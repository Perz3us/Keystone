// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:yet_another_luci_app/state/app_state.dart';

import '../noob_rpc.dart';
import 'history_data.dart';

const _join = 5;

final _towerLine = RegExp(
  r'^(\d+)\s+\S+\s+\S+\s+\S+\s+\S+\s+(\S+)\s+(\S+)\s+(.+)$',
);

List<HistoryPoint> parseFiveG({
  required Map<String, List<(int, double)>> series,
  required String towerLog,
  required double uptimeNow,
  required DateTime now,
}) {
  final samples = <(int, String, double)>[
    for (final e in series.entries)
      for (final (t, v) in e.value)
        if (t <= uptimeNow) (t, e.key, v),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final byT = <int, Map<String, double>>{};
  int? start;
  for (final (t, k, v) in samples) {
    if (start == null || t - start > _join || byT[start]!.containsKey(k)) {
      start = t;
      byT.putIfAbsent(t, () => {});
    }
    if (v.isNaN || (k == 'ping' && v <= 0)) continue;
    byT[start]![k] = v;
  }
  final ts = byT.keys.toList()..sort();
  final tower = <int, (String, String, String)>{};
  for (final line in towerLog.split('\n')) {
    final m = _towerLine.firstMatch(line.trim());
    if (m == null || ts.isEmpty) continue;
    final up = int.parse(m[1]!);
    final nearest = ts.reduce(
      (a, b) => (a - up).abs() <= (b - up).abs() ? a : b,
    );
    if ((nearest - up).abs() <= 120) {
      tower[nearest] = (m[2]!, m[3]!, m[4]!.trim());
    }
  }
  return [
    for (final t in ts)
      HistoryPoint(
        t: now.subtract(Duration(seconds: (uptimeNow - t).round())),
        rsrp: byT[t]!['rsrp'],
        sinr: byT[t]!['sinr'],
        ping: byT[t]!['ping'],
        pci: tower[t]?.$1,
        earfcn: tower[t]?.$2,
        band: tower[t]?.$3,
      ),
  ];
}

List<SimTraffic> parseTraffic(
  Map<String, dynamic> listJson,
  Map<String, dynamic> trafficJson,
) {
  final labels = listJson['labels'] is Map ? listJson['labels'] as Map : {};
  final out = <SimTraffic>[];
  for (final e in trafficJson.entries) {
    final v = e.value;
    if (v is! Map || !e.key.contains('|')) continue;
    if (v['rx'] is! num && v['tx'] is! num) continue;
    final sim = e.key.split('|').first;
    out.add(
      SimTraffic(
        sim: sim,
        label: '${labels['op.$sim'] ?? sim}',
        month: e.key.split('|').last,
        down: (v['rx'] as num?)?.toInt() ?? 0,
        up: (v['tx'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return out;
}

class FiveGModemHistory implements HistorySource {
  FiveGModemHistory(
    this.app, {
    Future<String> Function(List<String> args)? stats,
    Future<String> Function(String path)? readFile,
    DateTime Function()? now,
  }) : _stats = stats ?? _exec(app),
       _read = readFile ?? ((p) => noobReadFile(app, p)),
       _now = now ?? DateTime.now;

  final AppState app;
  final Future<String> Function(List<String> args) _stats;
  final Future<String> Function(String path) _read;
  final DateTime Function() _now;

  static Future<String> Function(List<String>) _exec(AppState app) =>
      (args) async {
        final r = await noobCall(app, 'file', 'exec', {
          'command': '/usr/share/5gmodem/stats.sh',
          'params': args,
        });
        if (r['code'] is int && r['code'] != 0) {
          throw NoobRpcError('${r['stdout'] ?? 'Error ${r['code']}'}');
        }
        return '${r['stdout'] ?? ''}'.trim();
      };

  Future<Map<String, dynamic>> _json(List<String> args) async {
    final j = jsonDecode(await _stats(args));
    return j is Map ? Map<String, dynamic>.from(j) : const {};
  }

  Future<List<(int, double)>> _series(String name) async {
    final list = (await _json(['series', name]))['series'];
    if (list is! List) return const [];
    return [
      for (final p in list)
        if (p is List && p.length >= 2 && p[0] is num)
          (
            (p[0] as num).toInt(),
            p[1] is num ? (p[1] as num).toDouble() : double.nan,
          ),
    ];
  }

  @override
  Future<HistoryData?> load(DateTime from, DateTime to) async {
    final Map<String, dynamic> list;
    try {
      list = await _json(['list']);
    } catch (e) {
      if (historyMissing(e)) return null;
      rethrow;
    }
    List<String> names(String k) => [
      if (list[k] is List) ...(list[k] as List).map((e) => '$e'),
    ];
    Future<List<(int, double)>> safe(String name) async {
      try {
        return await _series(name);
      } catch (_) {
        return const [];
      }
    }

    final series = <String, List<(int, double)>>{};
    final rsrp = names('rsrp');
    final modem = rsrp.isEmpty ? null : rsrp.first;
    if (modem != null) {
      series['rsrp'] = await safe('rsrp.$modem');
      series['sinr'] = await safe('sinr.$modem');
    }
    final ping = names('ping');
    if (ping.isNotEmpty) series['ping'] = await safe('ping.${ping.first}');
    final double uptime;
    try {
      final u = double.tryParse((await _read('/proc/uptime')).split(' ').first);
      if (u == null) return null;
      uptime = u;
    } catch (e) {
      if (historyMissing(e)) return null;
      rethrow;
    }
    var tower = '';
    if (modem != null) {
      try {
        tower = await _read(
          '/tmp/5gmodem/hist_${modem.replaceFirst('m_', '')}_',
        );
      } catch (_) {}
    }
    final pts = parseFiveG(
      series: series,
      towerLog: tower,
      uptimeNow: uptime,
      now: _now(),
    ).where((p) => !p.t.isBefore(from) && !p.t.isAfter(to)).toList();
    var traffic = <SimTraffic>[];
    try {
      traffic = parseTraffic(list, await _json(['traffic']));
    } catch (_) {}
    return HistoryData(
      points: pts,
      traffic: traffic,
      since: pts.isNotEmpty && pts.first.t.isAfter(from) ? pts.first.t : null,
      pingMethod: 'icmp',
    );
  }
}
