// SPDX-License-Identifier: GPL-3.0-or-later

import '../modules/noobwrt/datacap/data_plan.dart';
import '../screens/stats/wan_usage.dart';

class DataLines {
  const DataLines({
    required this.used,
    this.of = '',
    this.percent,
    this.split = '',
    this.reset = '',
    this.compact = '',
  });
  final String used, of, split, reset, compact;

  final int? percent;
}

String _gb(int bytes) => (bytes / 1e9).toStringAsFixed(1);

String _days(int n) => n == 1 ? '1 day' : '$n days';

DataLines? dataWidgetLines(SimPlan? p, DateTime now) {
  if (p == null) return null;
  if (p.kind == PlanKind.none) return const DataLines(used: 'Set a data plan');
  final s = capStatus(p, now);
  final left = s.daysLeft < 0 ? 0 : s.daysLeft;
  final limit = s.limit;
  if (limit == null) {
    final reset = left == 1 ? 'Resets tomorrow' : 'Resets in ${_days(left)}';
    return DataLines(
      used: sizeWords(p.used),
      of: p.kind == PlanKind.unlimited ? 'Unlimited' : '',
      split: '↓ ${_gb(p.down)} ↑ ${_gb(p.up)} GB',
      reset: reset,
      compact: '${sizeWords(p.used)} · unlimited · ${reset.toLowerCase()}',
    );
  }
  final over = p.used - limit;
  final state = over > 0
      ? '${_gb(over)} GB over'
      : over == 0
      ? 'Used up'
      : null;
  return DataLines(
    used: sizeWords(p.used),
    of: 'of ${p.allowanceGb} GB',
    percent: limit <= 0 ? 100 : (p.used * 100 ~/ limit).clamp(0, 100),
    split: '↓ ${_gb(p.down)} ↑ ${_gb(p.up)} GB',
    reset: state ?? '${_days(left)} left',
    compact: '${_gb(p.used)} / ${p.allowanceGb} GB · ${state ?? _days(left)}',
  );
}

String shortBand(String name) => name.trim().split(' ').first;

String _num(int n) => n < 0 ? '−${-n}' : '$n';

String? signalLine({List<String>? bands, int? rsrp, int? sinr}) {
  final parts = [
    if (bands != null && bands.isNotEmpty) bands.join(' + '),
    if (rsrp != null) '${_num(rsrp)} dBm',
    if (sinr != null) 'SINR ${_num(sinr)}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}
