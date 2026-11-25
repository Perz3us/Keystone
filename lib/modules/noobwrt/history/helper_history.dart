// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/state/app_state.dart';

import '../noob_rpc.dart';
import 'history_data.dart';

typedef HelperCall =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

HelperCall _rpc(AppState app) =>
    (method, params) => noobCall(app, 'keystone.history', method, params);

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v');

String? _str(Object? v) => v == null || v == '-' ? null : '$v';

class HelperHistory implements HistorySource {
  HelperHistory(AppState app, {HelperCall? call}) : _call = call ?? _rpc(app);

  final HelperCall _call;

  @override
  Future<HistoryData?> load(DateTime from, DateTime to) async {
    final method = _call('info', {}).then<String?>(
      (i) => i['ping_method'] is String ? i['ping_method'] as String : null,
      onError: (_) => null,
    );
    final Map<String, dynamic> r;
    try {
      r = await _call('history', {
        'from': from.millisecondsSinceEpoch ~/ 1000,
        'to': to.millisecondsSinceEpoch ~/ 1000,
      });
    } catch (e) {
      if (historyMissing(e, denied: true)) return null;
      rethrow;
    }
    try {
      final points = <HistoryPoint>[];
      for (final row in r['points'] is List ? r['points'] as List : const []) {
        final ts = row is List && row.length >= 7 ? _num(row[0]) : null;
        if (row is! List || ts == null || !ts.isFinite) continue;
        points.add(
          HistoryPoint(
            t: DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000),
            rsrp: _num(row[1]),
            sinr: _num(row[2]),
            ping: _num(row[3]),
            pci: _str(row[4]),
            earfcn: _str(row[5]),
            band: _str(row[6]),
          ),
        );
      }
      points.sort((a, b) => a.t.compareTo(b.t));
      final traffic = <SimTraffic>[];
      for (final t in r['traffic'] is List ? r['traffic'] as List : const []) {
        if (t is! Map || t['month'] == null) continue;
        final down = _num(t['down']), up = _num(t['up']);
        if (down == null && up == null) continue;
        traffic.add(
          SimTraffic(
            sim: 'helper',
            label: 'Router',
            month: '${t['month']}',
            down: down?.toInt() ?? 0,
            up: up?.toInt() ?? 0,
          ),
        );
      }
      return HistoryData(
        points: points,
        traffic: traffic,
        since: points.isNotEmpty && points.first.t.isAfter(from)
            ? points.first.t
            : null,
        pingMethod: await method,
      );
    } catch (_) {
      return null;
    }
  }
}

Future<String?> helperVersion(AppState app, {HelperCall? call}) async {
  try {
    final r = await (call ?? _rpc(app))('info', {});
    final v = r['version'];
    return v == null ? null : '$v';
  } catch (_) {
    return null;
  }
}
