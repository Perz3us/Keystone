// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

import 'widget_lines.dart';

class WidgetSnapshot {
  const WidgetSnapshot({
    required this.routerName,
    this.online,
    this.bars,
    this.dataLine,
    this.data,
    this.signal,
    required this.at,
  });
  final String routerName;
  final bool? online;

  final int? bars;
  final String? dataLine;
  final DataLines? data;

  final String? signal;
  final DateTime at;
}

Map<String, String> snapshotKeys(
  WidgetSnapshot s, {
  bool signal = true,
  bool data = true,
}) => {
  'widget.router': s.routerName,
  'widget.online': switch (s.online) {
    null => '',
    true => '1',
    false => '0',
  },
  if (signal) 'widget.bars': s.bars?.toString() ?? '',
  if (data) ...{
    'widget.data': s.dataLine ?? '',
    'widget.used': s.data?.used ?? '',
    'widget.of': s.data?.of ?? '',
    'widget.pct': s.data?.percent?.toString() ?? '',
    'widget.split': s.data?.split ?? '',
    'widget.reset': s.data?.reset ?? '',
    'widget.compact': s.data?.compact ?? '',
  },
  if (signal) 'widget.signal': s.signal ?? '',
  'widget.at': '${s.at.millisecondsSinceEpoch}',
};

Future<void> saveWidgetSnapshot(SharedPreferences p, WidgetSnapshot s) =>
    saveWidgetKeys(p, snapshotKeys(s));

Future<void> saveWidgetKeys(
  SharedPreferences p,
  Map<String, String> keys,
) async {
  for (final e in keys.entries) {
    await p.setString(e.key, e.value);
  }
}
