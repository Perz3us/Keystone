// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/screens/home/home_data.dart';

enum AlertType { internet, signal, device, data, restart }

enum AlertMode { buzz, log, off }

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.type,
    this.start,
    this.end,
    required this.approx,
    required this.detail,
  });

  final int id;
  final AlertType type;
  final DateTime? start, end;

  final bool approx;
  final Map<String, dynamic> detail;

  bool get lasts => type == AlertType.internet || type == AlertType.signal;

  static AlertEvent? from(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], type = AlertType.values.asNameMap()['${j['type']}'];
    if (id is! int || type == null) return null;
    final d = j['detail'];
    return AlertEvent(
      id: id,
      type: type,
      start: _time(j['start']),
      end: _time(j['end']),
      approx: j['approx'] == true,
      detail: d is Map ? Map<String, dynamic>.from(d) : const {},
    );
  }

  Map<String, dynamic> toCache() => {
    'id': id,
    'type': type.name,
    'start': _secs(start),
    'end': _secs(end),
    'approx': approx,
    'detail': detail,
  };
}

DateTime? _time(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt() * 1000) : null;

int? _secs(DateTime? t) => t == null ? null : t.millisecondsSinceEpoch ~/ 1000;

class AlertSettings {
  const AlertSettings({
    this.modes = const {
      AlertType.internet: AlertMode.buzz,
      AlertType.signal: AlertMode.log,
      AlertType.device: AlertMode.buzz,
      AlertType.data: AlertMode.buzz,
      AlertType.restart: AlertMode.log,
    },
    this.rsrpBelow = -110,
    this.warnPct = 80,
    this.fairusePct = 90,
  });

  final Map<AlertType, AlertMode> modes;
  final int rsrpBelow, warnPct, fairusePct;

  factory AlertSettings.from(Object? j) {
    const d = AlertSettings();
    if (j is! Map) return d;
    Map<dynamic, dynamic> part(String k) =>
        j[k] is Map ? j[k] as Map : const {};
    int n(Object? v, int or) => v is num ? v.toInt() : int.tryParse('$v') ?? or;
    return AlertSettings(
      modes: {
        for (final t in AlertType.values)
          t:
              AlertMode.values.asNameMap()['${part(t.name)['mode']}'] ??
              d.modes[t]!,
      },
      rsrpBelow: n(part('signal')['rsrp_below'], d.rsrpBelow),
      warnPct: n(part('data')['warn_pct'], d.warnPct),
      fairusePct: n(part('data')['fairuse_pct'], d.fairusePct),
    );
  }

  AlertSettings copyWith({
    (AlertType, AlertMode)? mode,
    int? rsrpBelow,
    int? warnPct,
    int? fairusePct,
  }) => AlertSettings(
    modes: mode == null ? modes : {...modes, mode.$1: mode.$2},
    rsrpBelow: rsrpBelow ?? this.rsrpBelow,
    warnPct: warnPct ?? this.warnPct,
    fairusePct: fairusePct ?? this.fairusePct,
  );

  Map<String, dynamic> toRouter() => {
    for (final t in AlertType.values)
      t.name: {
        'mode': modes[t]!.name,
        if (t == AlertType.signal) 'rsrp_below': rsrpBelow,
        if (t == AlertType.data) ...{
          'warn_pct': warnPct,
          'fairuse_pct': fairusePct,
        },
      },
  };
}

String spanWords(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  if (d.inHours < 1) return '${d.inMinutes} min';
  if (d.inDays < 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  final h = d.inHours % 24;
  return h == 0 ? '${d.inDays} d' : '${d.inDays} d $h h';
}

String alertTitle(AlertEvent e) {
  final d = e.detail;
  switch (e.type) {
    case AlertType.internet:
      final start = e.start, end = e.end;
      if (end == null) return 'Internet is down';
      if (start == null) return 'Internet was down';
      return 'Internet was down for ${spanWords(end.difference(start))}';
    case AlertType.signal:
      final r = d['rsrp'];
      return r is num ? 'Signal dropped to $r dBm' : 'Signal dropped';
    case AlertType.device:
      final who = [
        d['name'],
        d['mac'],
      ].whereType<String>().where((s) => s.isNotEmpty).firstOrNull;
      return who == null ? 'New device joined' : 'New device: $who';
    case AlertType.data:
      switch (d['level']) {
        case 'full':
          return 'Your data is used up';
        case 'fairuse':
          return 'Close to the fair-use limit';
        case 'pace':
          final out = DateTime.tryParse('${d['runs_out']}');
          return out == null
              ? 'Data is being used too fast'
              : 'At this rate data runs out on ${dayMonth(out)}';
        default:
          final p = d['pct'];
          return p is num
              ? '$p% of your data used'
              : 'Most of your data is used';
      }
    case AlertType.restart:
      return d['what'] == 'modem' ? 'Modem restarted' : 'Router restarted';
  }
}
