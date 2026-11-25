class WanUsage {
  const WanUsage({required this.down, required this.up, required this.seconds});

  final int down;
  final int up;

  final int seconds;

  int get total => down + up;
  double get averageMbps => seconds <= 0 ? 0 : total * 8 / seconds / 1e6;

  static WanUsage? from(Object? dump, Object? devices) {
    final list = dump is Map ? dump['interface'] : null;
    if (list is! List || devices is! Map) return null;
    for (final i in list.whereType<Map>()) {
      final routes = i['route'];
      final isDefault =
          i['up'] == true &&
          routes is List &&
          routes.whereType<Map>().any(
            (r) =>
                (r['target'] == '0.0.0.0' || r['target'] == '::') &&
                '${r['mask']}' == '0',
          );
      if (!isDefault) continue;
      final dev = i['l3_device'] ?? i['device'];
      final stats = devices[dev] is Map ? (devices[dev] as Map)['stats'] : null;
      if (stats is! Map) return null;
      return WanUsage(
        down: (stats['rx_bytes'] as num?)?.toInt() ?? 0,
        up: (stats['tx_bytes'] as num?)?.toInt() ?? 0,
        seconds: (i['uptime'] as num?)?.toInt() ?? 0,
      );
    }
    return null;
  }
}

String sizeWords(int bytes) {
  if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
  if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
  return '${(bytes / 1e3).toStringAsFixed(0)} KB';
}
