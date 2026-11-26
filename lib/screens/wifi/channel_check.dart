// SPDX-License-Identifier: GPL-3.0-or-later

class ChannelLoad {
  const ChannelLoad(this.channel, this.networks, this.strongest);
  final int channel;
  final int networks;

  final int? strongest;
}

class ScanUnsupported implements Exception {
  const ScanUnsupported();
}

const _dfs = {
  52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, //
};

List<ChannelLoad> channelLoads(List<Object?> scan, {required bool is5g}) {
  final count = <int, int>{}, loud = <int, int>{};
  void add(int ch, int? dbm) {
    count[ch] = (count[ch] ?? 0) + 1;
    if (dbm != null && (loud[ch] == null || dbm > loud[ch]!)) loud[ch] = dbm;
  }

  for (final n in scan) {
    if (n is! Map) continue;
    final ch = int.tryParse('${n['channel']}');
    if (ch == null || ch <= 0) continue;
    final dbm = int.tryParse('${n['signal']}'.split('.').first);
    if (is5g) {
      add(ch, dbm);
    } else {
      for (var c = ch - 2; c <= ch + 2; c++) {
        if (c >= 1 && c <= 14) add(c, dbm);
      }
    }
  }
  final channels = is5g ? {...count.keys} : {for (var c = 1; c <= 13; c++) c};
  return [
    for (final c in channels.toList()..sort())
      ChannelLoad(c, count[c] ?? 0, loud[c]),
  ];
}

int suggestChannel(
  List<ChannelLoad> loads, {
  required bool is5g,
  required int current,
  required Set<int> allowed,
}) {
  int busy(int c) =>
      loads.where((l) => l.channel == c).firstOrNull?.networks ?? 0;
  final pool = is5g
      ? allowed.toList()
      : [1, 6, 11].where(allowed.contains).toList();
  if (pool.isEmpty) {
    return current > 0 ? current : (allowed.toList()..sort()).first;
  }
  pool.sort();
  int best(Iterable<int> from) {
    final list = from.toList();
    final least = list.map(busy).reduce((a, b) => a < b ? a : b);
    final ties = list.where((c) => busy(c) == least).toList();
    return ties.contains(current) ? current : ties.first;
  }

  final any = best(pool);
  if (!is5g) return any;
  final calm = pool.where((c) => !_dfs.contains(c));
  if (calm.isEmpty) return any;
  final plain = best(calm);
  return busy(plain) <= busy(any) + 1 ? plain : any;
}
