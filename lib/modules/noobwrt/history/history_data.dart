// SPDX-License-Identifier: GPL-3.0-or-later

import '../noob_rpc.dart';

const _missing = {
  'Invalid command',
  'Method not found',
  'Not found',
  'Not supported',
};

bool historyMissing(Object e, {bool denied = false}) =>
    e is FormatException ||
    (e is NoobRpcError &&
        (_missing.contains(e.message) ||
            denied && e.message == 'Permission denied'));

class HistoryPoint {
  const HistoryPoint({
    required this.t,
    this.rsrp,
    this.sinr,
    this.ping,
    this.pci,
    this.earfcn,
    this.band,
  });
  final DateTime t;
  final double? rsrp, sinr, ping;
  final String? pci, earfcn, band;
}

class SimTraffic {
  const SimTraffic({
    required this.sim,
    required this.label,
    required this.month,
    required this.down,
    required this.up,
  });
  final String sim;
  final String label;
  final String month;
  final int down, up;
}

class HistoryData {
  const HistoryData({
    required this.points,
    required this.traffic,
    this.since,
    this.pingMethod,
  });
  final List<HistoryPoint> points;
  final List<SimTraffic> traffic;
  final DateTime? since;
  final String? pingMethod;
}

abstract class HistorySource {
  Future<HistoryData?> load(DateTime from, DateTime to);
}
