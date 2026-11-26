// SPDX-License-Identifier: GPL-3.0-or-later

enum PlanKind { none, unlimited, capped, fairuse }

class SimPlan {
  const SimPlan({
    required this.sim,
    required this.kind,
    this.allowanceGb,
    required this.billingDay,
    required this.periodStart,
    required this.periodEnd,
    required this.down,
    required this.up,
    this.since,
  });

  final String sim;
  final PlanKind kind;
  final int? allowanceGb;
  final int billingDay;

  final DateTime periodStart, periodEnd;
  final int down, up;

  final DateTime? since;

  int get used => down + up;

  static SimPlan? from(Object? j) {
    if (j is! Map || j['sim'] is! String) return null;
    final start = _day(j['period_start']), end = _day(j['period_end']);
    if (start == null || end == null) return null;
    final gb = _int(j['allowance_gb']) ?? 0;
    return SimPlan(
      sim: j['sim'] as String,
      kind: switch (j['plan']) {
        'unlimited' => PlanKind.unlimited,
        'capped' => PlanKind.capped,
        'fairuse' => PlanKind.fairuse,
        _ => PlanKind.none,
      },
      allowanceGb: gb > 0 ? gb : null,
      billingDay: _int(j['billing_day']) ?? 1,
      periodStart: start,
      periodEnd: end,
      down: _int(j['down']) ?? 0,
      up: _int(j['up']) ?? 0,
      since: _day(j['since']),
    );
  }
}

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');

DateTime? _day(Object? v) {
  final d = DateTime.tryParse('$v');
  return d == null ? null : DateTime.utc(d.year, d.month, d.day);
}

class DataPlans {
  const DataPlans({required this.activeSim, required this.plans});
  final String activeSim;
  final List<SimPlan> plans;

  SimPlan? get active => plans.where((p) => p.sim == activeSim).firstOrNull;
}

class CapStatus {
  const CapStatus({
    required this.used,
    this.limit,
    required this.daysLeft,
    this.runsOutOn,
  });
  final int used;
  final int? limit;
  final int daysLeft;
  final DateTime? runsOutOn;

  double? get fraction => limit == null ? null : used / limit!;
}

CapStatus capStatus(SimPlan p, DateTime now) {
  final today = DateTime.utc(now.year, now.month, now.day);
  final left = p.periodEnd.difference(today).inDays + 1;
  final limited = p.kind == PlanKind.capped || p.kind == PlanKind.fairuse;
  final limit = limited && p.allowanceGb != null
      ? p.allowanceGb! * 1000000000
      : null;
  DateTime? out;
  final from = p.since ?? p.periodStart;
  final day = today.difference(from).inDays + 1;
  if (p.kind == PlanKind.capped &&
      limit != null &&
      p.used > 0 &&
      p.used < limit &&
      day >= 3) {
    final end = from.add(Duration(days: (limit * day / p.used).ceil() - 1));
    if (end.isBefore(p.periodEnd)) out = end;
  }
  return CapStatus(
    used: p.used,
    limit: limit,
    daysLeft: left < 0 ? 0 : left,
    runsOutOn: out,
  );
}
