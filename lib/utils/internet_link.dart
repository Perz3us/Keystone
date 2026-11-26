// SPDX-License-Identifier: GPL-3.0-or-later

const _tunnels = {
  'wireguard',
  'amneziawg',
  'openvpn',
  'openconnect',
  'vpnc',
  'none',
};

bool _routed(Map i) {
  final r = i['route'];
  return r is List && r.any((x) => x is Map && '${x['mask']}' == '0');
}

Map? internetInterface(Iterable<Object?> interfaces) {
  Map? routedWan, routed, named;
  for (final i in interfaces.whereType<Map>()) {
    final name = '${i['interface']}';
    final isWan = name == 'wan' || name == 'wan6';
    if (_routed(i) && isWan) {
      routedWan ??= i;
    } else if (_routed(i) && !_tunnels.contains('${i['proto']}')) {
      routed ??= i;
    }
    if (isWan) named ??= i;
  }
  return routedWan ?? routed ?? named;
}

List<Object?> dumpInterfaces(Object? dump) =>
    dump is Map && dump['interface'] is List
    ? dump['interface'] as List
    : const [];

String? linkDevice(Map i) {
  for (final k in ['l3_device', 'device']) {
    final v = i[k]?.toString() ?? '';
    if (v.isNotEmpty && !v.startsWith('/')) return v;
  }
  return null;
}

String internetZone(Map firewall, String? network) {
  if (network != null) {
    for (final z in firewall.values.whereType<Map>()) {
      if (z['.type'] != 'zone') continue;
      final n = z['network'];
      final nets = n is List ? n.map((e) => '$e') : '${n ?? ''}'.split(' ');
      if (nets.contains(network) && z['name'] != null) return '${z['name']}';
    }
  }
  return 'wan';
}
