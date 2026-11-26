// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/background/widget_data.dart';
import 'package:yet_another_luci_app/background/widget_lines.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

List<String> dataLines(SimPlan p, DateTime now) {
  final s = capStatus(p, now);
  final limit = s.limit;
  final counted = p.since;
  if (limit == null) {
    final since = counted != null
        ? 'since ${dayMonth(counted)}'
        : p.periodStart.day == 1
        ? 'this month'
        : 'since ${dayMonth(p.periodStart)}';
    return ['${sizeWords(p.used)} $since'];
  }
  final partial = counted == null ? null : 'Counted since ${dayMonth(counted)}';
  final resets = 'resets ${dayMonth(p.periodEnd.add(const Duration(days: 1)))}';
  if (p.kind == PlanKind.fairuse) {
    if (p.used >= limit) {
      return ['Past the ${p.allowanceGb} GB fair-use limit · $resets'];
    }
    final used = (p.used / 1e9).toStringAsFixed(1);
    return ['$used of ${p.allowanceGb} GB before it slows down', ?partial];
  }
  if (p.used >= limit) return ['Data used up · $resets'];
  final left = s.daysLeft == 1 ? '1 day left' : '${s.daysLeft} days left';
  return [
    '${(s.fraction! * 100).floor()}% used · $left',
    if (s.runsOutOn != null)
      'At this rate it runs out on ${dayMonth(s.runsOutOn!)}',
    ?partial,
  ];
}

WidgetSnapshot? homeSnapshot(
  String routerName,
  HomeStatus status, {
  int? bars,
  SimPlan? plan,
  SignalOverview? signal,
  required DateTime now,
}) => status.internet == LinkState.unknown
    ? null
    : WidgetSnapshot(
        routerName: routerName,
        online: status.internet != LinkState.down,
        bars: bars,
        dataLine: plan == null ? null : dataLines(plan, now).first,
        data: dataWidgetLines(plan, now),
        signal: signal == null
            ? null
            : signalLine(
                bands: [for (final c in signal.active) shortBand(c.band)],
                rsrp: double.tryParse(signal.rsrp ?? '')?.round(),
                sinr: double.tryParse(signal.sinr ?? '')?.round(),
              ),
        at: now,
      );

class HomeDataLine extends StatelessWidget {
  const HomeDataLine({
    super.key,
    required this.plan,
    required this.now,
    required this.onTap,
  });

  final SimPlan plan;
  final DateTime now;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final lines = dataLines(plan, now);
    final limit = capStatus(plan, now).limit;
    final over = limit != null && plan.used >= limit;
    final tone = !over
        ? ks.tx2
        : plan.kind == PlanKind.capped
        ? ks.bad
        : ks.warnTx;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: 44,
            minWidth: double.infinity,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lines.first,
                  style: KeystoneType.body(tone).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                for (final l in lines.skip(1))
                  Text(l, style: KeystoneType.secondary(ks.warnTx)),
                if (plan.kind == PlanKind.none)
                  Text('Set your plan', style: KeystoneType.secondary(ks.ac)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
