// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import '../noob_rpc.dart';

class CellEntry {
  final String key;
  final String value;
  final String? unit;
  final double? min;
  final double? max;
  const CellEntry(this.key, this.value, {this.unit, this.min, this.max});

  bool get isHeading => key == value;

  bool get isMain => const {'rsrp', 'rsrq', 'sinr'}.contains(key.toLowerCase());

  double? get fill {
    final v = double.tryParse(value), lo = min, hi = max;
    if (v == null || lo == null || hi == null || hi == lo) return null;
    return ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  static List<CellEntry> parse(Map<String, dynamic> r) => [
    for (final e in (r['modem_info'] as List? ?? const []))
      if (e is Map &&
          noobValue(e['key']) != null &&
          noobValue(e['value']) != null)
        CellEntry(
          noobValue(e['key'])!,
          noobValue(e['value'])!,
          unit: noobValue(e['unit']),
          min: double.tryParse('${e['min_value']}'),
          max: double.tryParse('${e['max_value']}'),
        ),
  ];
}

class Carrier {
  final String role;
  final String rat;
  final String band;
  final String? channel;
  final String? channelType;
  final String? pci;
  final String? width;
  final String? scs;
  const Carrier({
    required this.role,
    required this.rat,
    required this.band,
    this.channel,
    this.channelType,
    this.pci,
    this.width,
    this.scs,
  });

  String get label => switch (role) {
    'scc' => 'Aggregated',
    'nsa' => '5G (NSA)',
    _ => rat == 'NR' ? 'Primary (5G SA)' : 'Primary',
  };

  String get detail => [
    [band, if (width != null) '$width MHz', ?scs].join(' · '),
    [
      if (pci != null) 'PCI $pci',
      if (channel != null) '${channelType ?? 'ARFCN'} $channel',
    ].join('  '),
  ].where((s) => s.isNotEmpty).join('\n');

  static (String?, List<Carrier>) parse(Map<String, dynamic> r) {
    final cb = r['current_band'];
    if (cb is! Map || cb['status'] != 'ok') return (null, const []);
    return (
      noobValue(cb['network_mode']),
      [
        for (final c in (cb['cells'] as List? ?? const []))
          if (c is Map)
            Carrier(
              role: '${c['role']}',
              rat: '${c['rat']}',
              band: noobValue(c['band_name']) ?? 'Band ${c['band']}',
              channel: noobValue(c['channel']),
              channelType: noobValue(c['channel_type']),
              pci: noobValue(c['pci']),
              width: noobValue(c['dl_bandwidth']),
              scs: noobValue(c['scs']),
            ),
      ],
    );
  }
}

class BandClass {
  final String id;
  final List<(String, String)> available;
  final Set<String> locked;
  const BandClass(this.id, this.available, this.locked);

  String get title => switch (id) {
    'LTE' || 'Lte' => '4G',
    'NR_NSA' => '5G NSA',
    'NR' => '5G SA',
    'UMTS' => '3G',
    _ => id,
  };

  static List<BandClass> parse(Map<String, dynamic> r) {
    final lb = r['lockband'];
    if (lb is! Map) return const [];
    return [
      for (final MapEntry(:key, :value) in lb.entries)
        if (value is Map && value['available_band'] is List)
          BandClass(
            '$key',
            [
              for (final b in value['available_band'] as List)
                if (b is Map && noobValue(b['band_id']) != null)
                  (
                    noobValue(b['band_id'])!,
                    (noobValue(b['band_name']) ?? '${b['band_id']}')
                        .replaceFirst(
                          RegExp(r'^(UMTS_|LTE_|NSA_NR_|SA_NR_)'),
                          '',
                        ),
                  ),
            ],
            {
              for (final b in (value['lock_band'] as List? ?? const []))
                ?noobValue(b),
            },
          ),
    ].where((c) => c.available.isNotEmpty).toList();
  }
}

class NearbyCell {
  final String rat;
  final String arfcn;
  final String pci;
  final String? rsrp;
  final String? rsrq;
  final bool serving;
  const NearbyCell(
    this.rat,
    this.arfcn,
    this.pci,
    this.rsrp,
    this.rsrq, {
    this.serving = false,
  });
}

class CellLockUnsupported implements Exception {
  const CellLockUnsupported();
}

class CellLock {
  final String? lte;
  final String? nr;
  final List<NearbyCell> nearby;
  const CellLock(this.lte, this.nr, this.nearby);

  bool get locked => lte != null || nr != null;

  static CellLock parse(Map<String, dynamic> r) {
    final n = r['neighborcell'];
    if (n is! Map) return const CellLock(null, null, []);
    final s = n['lockcell_status'] is Map ? n['lockcell_status'] as Map : {};
    String? lock(String rat, String ch) => s[rat] == 'locked'
        ? 'PCI ${s['${rat}_PCI'] ?? '?'} · $ch ${s['${rat}_Freq'] ?? '?'}'
        : null;
    return CellLock(lock('LTE', 'EARFCN'), lock('NR', 'ARFCN'), [
      for (final rat in ['NR', 'LTE'])
        for (final c in (n[rat] is List ? n[rat] as List : const []))
          if (c is Map &&
              noobValue(c['pci']) != null &&
              noobValue(c['arfcn']) != null)
            NearbyCell(
              rat,
              noobValue(c['arfcn'])!,
              noobValue(c['pci'])!,
              noobValue(c['rsrp']),
              noobValue(c['rsrq']),
            ),
    ]);
  }
}

class FiveGBands {
  static Map<String, dynamic> decode(String out) {
    final j = jsonDecode(out);
    return j is Map ? Map<String, dynamic>.from(j) : const {};
  }

  static List<BandClass> classes(Map<String, dynamic> j) {
    String id(dynamic b) => b is Map ? '${b['band']}' : '$b';
    BandClass? one(String cls, String sup, String en, String prefix) {
      final s = j[sup];
      if (s is! List || s.isEmpty) return null;
      return BandClass(
        cls,
        [for (final b in s) (id(b), '$prefix${id(b)}')],
        {for (final b in (j[en] as List? ?? const [])) id(b)},
      );
    }

    return [
      ?one('LTE', 'supported', 'enabled', 'B'),
      ?one('NR_NSA', 'supported5gnsa', 'enabled5gnsa', 'n'),
      ?one('NR', 'supported5gsa', 'enabled5gsa', 'n'),
    ];
  }

  static CellLock lock(Map<String, dynamic> j) {
    String? one(dynamic v, String ch) {
      final p = '${v ?? ''}'.split(' ');
      return p.length >= 3 && p[0] == 'cell'
          ? 'PCI ${p[2]} · $ch ${p[1]}'
          : null;
    }

    return CellLock(
      one(j['celllock'], 'EARFCN'),
      one(j['celllock5g'], 'ARFCN'),
      const [],
    );
  }

  static List<NearbyCell> nearby(dynamic list) => [
    if (list is List)
      for (final n in list)
        if (n is Map &&
            noobValue(n['pci']) != null &&
            noobValue(n['earfcn']) != null)
          NearbyCell(
            '${n['band']}'.toLowerCase().startsWith('n') ? 'NR' : 'LTE',
            noobValue(n['earfcn'])!,
            noobValue(n['pci'])!,
            noobValue(n['rsrp']),
            noobValue(n['rsrq']),
            serving: n['serving'] == true,
          ),
  ];
}
