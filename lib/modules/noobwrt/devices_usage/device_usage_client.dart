// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

import '../datacap/data_plan_client.dart';
import '../history/helper_history.dart';
import '../noob_rpc.dart';

class DeviceUsage {
  const DeviceUsage(this.mac, this.down, this.up);
  final String mac;
  final int down, up;
  int get total => down + up;
}

class UsagePeriod {
  const UsagePeriod({required this.start, this.end, required this.byMac});
  final DateTime start;

  final DateTime? end;

  final Map<String, DeviceUsage> byMac;

  DeviceUsage? of(String mac) => byMac[ClientNamingHelper.normalizeMac(mac)];
}

class DevicesInfo {
  const DevicesInfo({
    required this.backend,
    required this.offload,
    required this.periods,
  });
  final String backend;

  final bool offload;

  final List<DateTime> periods;
}

DateTime? _day(Object? v) {
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

int _n(Object? v) => v is num ? v.toInt() : 0;

class DeviceUsageClient {
  DeviceUsageClient(this._call);
  DeviceUsageClient.of(AppState app)
    : this((m, p) => noobCall(app, 'keystone.devices', m, p));

  final HelperCall _call;

  Future<Map<String, dynamic>?> _ask(String m, Map<String, dynamic> p) async {
    try {
      return await _call(m, p);
    } catch (e) {
      if (keystoneMissing(e)) return null;
      rethrow;
    }
  }

  Future<DevicesInfo?> info() async {
    final r = await _ask('info', {});
    if (r == null) return null;
    return DevicesInfo(
      backend: '${r['backend'] ?? 'none'}',
      offload: r['offload'] == true,
      periods: [
        for (final p in r['periods'] is List ? r['periods'] as List : const [])
          ?_day(p),
      ],
    );
  }

  Future<UsagePeriod?> usage([DateTime? start]) async {
    final r = await _ask('usage', {if (start != null) 'period': _ymd(start)});
    final s = _day(r?['period_start']);
    if (r == null || s == null) return null;
    return UsagePeriod(
      start: s,
      end: _day(r['period_end']),
      byMac: {
        for (final d in r['devices'] is List ? r['devices'] as List : const [])
          if (d is Map && '${d['mac']}'.length == 17)
            ClientNamingHelper.normalizeMac('${d['mac']}'): DeviceUsage(
              ClientNamingHelper.normalizeMac('${d['mac']}'),
              _n(d['down']),
              _n(d['up']),
            ),
      },
    );
  }

  Future<List<(DateTime, int)>> history(String mac) async {
    final i = await info();
    if (i == null) return const [];
    final out = <(DateTime, int)>[];
    for (final p in i.periods.take(3)) {
      final u = await usage(p);
      out.add((p, u?.of(mac)?.total ?? 0));
    }
    return out;
  }
}
