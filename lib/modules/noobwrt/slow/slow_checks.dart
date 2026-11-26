// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../datacap/data_plan.dart';

enum SlowCause {
  weakSignal,
  linePing,
  phoneWifi,
  heavyDevice,
  proxyOn,
  fairUse,
  sqm,
}

class SlowFix {
  const SlowFix(this.label, this.open);
  final String label;
  final void Function(BuildContext context) open;
}

class SlowFinding {
  const SlowFinding({
    required this.cause,
    required this.score,
    required this.detail,
    this.fix,
  });
  final SlowCause cause;

  final int score;
  final String detail;
  final SlowFix? fix;
}

class SlowReport {
  const SlowReport({
    this.top,
    this.others = const [],
    this.couldntCheck = const [],
  });
  final SlowFinding? top;
  final List<SlowFinding> others;
  final List<SlowCause> couldntCheck;
}

typedef SlowCheck = Future<SlowFinding?> Function();

Future<SlowReport> runSlowChecks(
  Map<SlowCause, SlowCheck> checks, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final missed = <SlowCause>[];
  final found = <SlowFinding>[];
  await Future.wait([
    for (final MapEntry(key: cause, value: check) in checks.entries)
      Future(check).timeout(timeout).then((f) {
        if (f != null && f.score >= 30) found.add(f);
      }, onError: (_) => missed.add(cause)),
  ]);
  found.sort((a, b) => b.score.compareTo(a.score));
  missed.sort((a, b) => a.index.compareTo(b.index));
  return SlowReport(
    top: found.firstOrNull,
    others: found.skip(1).toList(),
    couldntCheck: missed,
  );
}

SlowFinding? signalFinding({num? rsrp, num? sinr, SlowFix? fix}) {
  if (rsrp != null && rsrp < -110) {
    return SlowFinding(
      cause: SlowCause.weakSignal,
      score: 85,
      detail: 'The mobile signal is weak ($rsrp dBm).',
      fix: fix,
    );
  }
  if (sinr != null && sinr < 0) {
    return SlowFinding(
      cause: SlowCause.weakSignal,
      score: 80,
      detail: 'The mobile signal is noisy (SINR $sinr dB).',
      fix: fix,
    );
  }
  return null;
}

SlowFinding? linePingFinding(List<double> pings) {
  if (pings.isEmpty) return null;
  final last = pings.last;
  if (last > 150) {
    return SlowFinding(
      cause: SlowCause.linePing,
      score: 85,
      detail: 'The line is slow to answer (${last.round()} ms).',
    );
  }
  if (pings.length >= 2) {
    var sum = 0.0;
    for (var i = 1; i < pings.length; i++) {
      sum += (pings[i] - pings[i - 1]).abs();
    }
    final jitter = sum / (pings.length - 1);
    if (jitter > 50) {
      return SlowFinding(
        cause: SlowCause.linePing,
        score: 80,
        detail: 'The line is unsteady (ping jumps about ${jitter.round()} ms).',
      );
    }
  }
  return null;
}

SlowFinding? phoneWifiFinding(int? rssi) => rssi != null && rssi < -75
    ? SlowFinding(
        cause: SlowCause.phoneWifi,
        score: 80,
        detail: 'This phone is far from the router ($rssi dBm). Move closer.',
      )
    : null;

SlowFinding? heavyDeviceFinding({
  required String name,
  required String mac,
  required double deviceBps,
  required double totalBps,
  void Function(BuildContext, String mac)? pause,
}) {
  if (totalBps <= 0 || deviceBps <= 5e6 || deviceBps / totalBps <= 0.7) {
    return null;
  }
  return SlowFinding(
    cause: SlowCause.heavyDevice,
    score: 80,
    detail:
        '$name is using ${(deviceBps / 1e6).toStringAsFixed(0)} Mbit/s, '
        'most of the line.',
    fix: SlowFix('Pause $name', (c) => pause?.call(c, mac)),
  );
}

SlowFinding? proxyFinding(bool on, {SlowFix? fix}) => on
    ? SlowFinding(
        cause: SlowCause.proxyOn,
        score: 40,
        detail:
            'Passwall is on. Traffic goes through its server, which can be slower.',
        fix: fix,
      )
    : null;

SlowFinding? fairUseFinding(SimPlan? p) {
  if (p == null || p.kind != PlanKind.fairuse) return null;
  final limit = capStatus(p, DateTime.now()).limit;
  return limit != null && p.used >= limit
      ? SlowFinding(
          cause: SlowCause.fairUse,
          score: 90,
          detail:
              'You are past the ${p.allowanceGb} GB fair-use limit, so the '
              'carrier may be slowing the SIM.',
        )
      : null;
}

SlowFinding? sqmFinding({required bool enabled, required int downloadKbit}) =>
    enabled && downloadKbit > 0
    ? SlowFinding(
        cause: SlowCause.sqm,
        score: 40,
        detail:
            'SQM holds downloads to ${max(1, downloadKbit ~/ 1000)} Mbit/s. '
            'If the line is faster now, raise it.',
      )
    : null;

String slowHeadline(SlowReport r) =>
    r.top?.detail ?? 'Nothing looks wrong right now';
