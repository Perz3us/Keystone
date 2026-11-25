// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

class Ipv4Range {
  final int start;
  final int end;

  const Ipv4Range(this.start, this.end);

  bool overlaps(Ipv4Range other) {
    return start <= other.end && other.start <= end;
  }
}

class Ipv6Range {
  final BigInt start;
  final BigInt end;

  const Ipv6Range(this.start, this.end);

  bool overlaps(Ipv6Range other) {
    return start <= other.end && other.start <= end;
  }
}

class PortForwardConflictResult {
  final bool hasConflict;
  final String? conflictingSectionKey;
  final String? reason;

  const PortForwardConflictResult({
    required this.hasConflict,
    this.conflictingSectionKey,
    this.reason,
  });

  const PortForwardConflictResult.noConflict()
    : hasConflict = false,
      conflictingSectionKey = null,
      reason = null;

  const PortForwardConflictResult.conflict({
    required this.conflictingSectionKey,
    required this.reason,
  }) : hasConflict = true;
}

class ManagementPortSafetyResult {
  final bool isUnsafe;
  final int port;
  final String serviceName;
  final String reason;

  const ManagementPortSafetyResult({
    required this.isUnsafe,
    required this.port,
    required this.serviceName,
    required this.reason,
  });

  const ManagementPortSafetyResult.safe()
    : isUnsafe = false,
      port = 0,
      serviceName = '',
      reason = '';
}

enum IncomingTrafficPreflightStatus {
  alreadyBlocked,
  currentlyAllowed,
  unableToDetermine,
}

class IncomingTrafficPreflightResult {
  final IncomingTrafficPreflightStatus status;
  final String? reason;
  final String? conflictingRuleName;
  final String? conflictingSectionKey;
  final String? resolvedDestZone;

  const IncomingTrafficPreflightResult({
    required this.status,
    this.reason,
    this.conflictingRuleName,
    this.conflictingSectionKey,
    this.resolvedDestZone,
  });

  bool get isAlreadyBlocked =>
      status == IncomingTrafficPreflightStatus.alreadyBlocked;
  bool get isCurrentlyAllowed =>
      status == IncomingTrafficPreflightStatus.currentlyAllowed;
  bool get isUnableToDetermine =>
      status == IncomingTrafficPreflightStatus.unableToDetermine;
}

class FirewallValidator {
  static const Map<int, String> routerManagementPorts = {
    22: 'SSH (Dropbear)',
    80: 'HTTP (LuCI Web Admin)',
    443: 'HTTPS (LuCI Web Admin)',
  };

  static List<List<int>> parsePortRanges(String? portSpec) {
    final clean = portSpec?.trim().toLowerCase() ?? '';
    if (clean.isEmpty || clean == 'any' || clean == 'all' || clean == '*') {
      return [
        [1, 65535],
      ];
    }

    final intervals = <List<int>>[];
    final parts = clean.split(',');

    for (final part in parts) {
      final token = part.trim();
      if (token.isEmpty) continue;

      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length == 2) {
          final s = int.tryParse(bounds[0].trim());
          final e = int.tryParse(bounds[1].trim());
          if (s != null && e != null && s <= e && s >= 1 && e <= 65535) {
            intervals.add([s, e]);
            continue;
          }
        }
      } else if (token.contains(':')) {
        final bounds = token.split(':');
        if (bounds.length == 2) {
          final s = int.tryParse(bounds[0].trim());
          final e = int.tryParse(bounds[1].trim());
          if (s != null && e != null && s <= e && s >= 1 && e <= 65535) {
            intervals.add([s, e]);
            continue;
          }
        }
      }

      final p = int.tryParse(token);
      if (p != null && p >= 1 && p <= 65535) {
        intervals.add([p, p]);
      }
    }

    return intervals.isEmpty
        ? [
            [1, 65535],
          ]
        : intervals;
  }

  static bool portsOverlap(String? portSpec1, String? portSpec2) {
    final ranges1 = parsePortRanges(portSpec1);
    final ranges2 = parsePortRanges(portSpec2);

    for (final r1 in ranges1) {
      for (final r2 in ranges2) {
        if (r1[0] <= r2[1] && r2[0] <= r1[1]) {
          return true;
        }
      }
    }
    return false;
  }

  static Set<String> normalizeProtocols(String? proto) {
    final clean = proto?.trim().toLowerCase() ?? '';
    if (clean.isEmpty ||
        clean == 'any' ||
        clean == 'all' ||
        clean == '*' ||
        clean == 'none') {
      return {'tcp', 'udp', 'icmp', 'other'};
    }

    final tokens = clean
        .replaceAll('/', ' ')
        .replaceAll('+', ' ')
        .split(RegExp(r'\s+'));
    final result = <String>{};

    for (final token in tokens) {
      if (token == 'tcpudp' || token == 'tcp_udp') {
        result.add('tcp');
        result.add('udp');
      } else if (token == 'tcp') {
        result.add('tcp');
      } else if (token == 'udp') {
        result.add('udp');
      } else if (token == 'icmp' || token == 'icmpv6') {
        result.add('icmp');
      } else if (token.isNotEmpty) {
        result.add(token);
      }
    }

    return result.isEmpty ? {'tcp', 'udp', 'icmp', 'other'} : result;
  }

  static bool protocolsOverlap(String? proto1, String? proto2) {
    final set1 = normalizeProtocols(proto1);
    final set2 = normalizeProtocols(proto2);

    return set1.intersection(set2).isNotEmpty;
  }

  static Ipv4Range? parseIpv4Cidr(String input) {
    final clean = input.trim();
    if (clean.isEmpty ||
        clean == '0.0.0.0/0' ||
        clean == 'Any' ||
        clean == '*') {
      return const Ipv4Range(0, 0xFFFFFFFF);
    }

    String ipStr = clean;
    int prefix = 32;

    if (clean.contains('/')) {
      final parts = clean.split('/');
      ipStr = parts[0].trim();
      final p = int.tryParse(parts[1].trim());
      if (p == null || p < 0 || p > 32) return null;
      prefix = p;
    }

    final octets = ipStr.split('.');
    if (octets.length != 4) return null;

    int ip = 0;
    for (int i = 0; i < 4; i++) {
      final o = int.tryParse(octets[i]);
      if (o == null || o < 0 || o > 255) return null;
      ip = (ip << 8) | o;
    }

    final mask = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;
    final start = ip & mask;
    final end = start | (~mask & 0xFFFFFFFF);

    return Ipv4Range(start, end);
  }

  static Ipv6Range? parseIpv6Cidr(String input) {
    final clean = input.trim().toLowerCase();
    if (clean.isEmpty || clean == '::/0' || clean == 'any' || clean == '*') {
      return Ipv6Range(BigInt.zero, (BigInt.one << 128) - BigInt.one);
    }

    String ipStr = clean;
    int prefix = 128;

    if (clean.contains('/')) {
      final parts = clean.split('/');
      ipStr = parts[0].trim();
      final p = int.tryParse(parts[1].trim());
      if (p == null || p < 0 || p > 128) return null;
      prefix = p;
    }

    final groups = <String>[];
    if (ipStr.contains('::')) {
      final halves = ipStr.split('::');
      if (halves.length > 2) return null;

      final left = halves[0].isEmpty
          ? <String>[]
          : halves[0].split(':').where((s) => s.isNotEmpty).toList();
      final right = halves.length > 1 && halves[1].isNotEmpty
          ? halves[1].split(':').where((s) => s.isNotEmpty).toList()
          : <String>[];

      final missing = 8 - (left.length + right.length);
      if (missing < 0) return null;

      groups.addAll(left);
      for (int i = 0; i < missing; i++) {
        groups.add('0');
      }
      groups.addAll(right);
    } else {
      groups.addAll(ipStr.split(':').where((s) => s.isNotEmpty));
    }

    if (groups.length != 8) return null;

    BigInt ip = BigInt.zero;
    for (int i = 0; i < 8; i++) {
      final val = int.tryParse(groups[i], radix: 16);
      if (val == null || val < 0 || val > 0xFFFF) return null;
      ip = (ip << 16) | BigInt.from(val);
    }

    final BigInt mask = prefix == 0
        ? BigInt.zero
        : ((BigInt.one << 128) - (BigInt.one << (128 - prefix)));
    final start = ip & mask;
    final end = start + (BigInt.one << (128 - prefix)) - BigInt.one;

    return Ipv6Range(start, end);
  }

  static bool familiesOverlap(String? family1, String? family2) {
    final f1 = family1?.trim().toLowerCase() ?? '';
    final f2 = family2?.trim().toLowerCase() ?? '';

    final isAny1 = f1.isEmpty || f1 == 'any' || f1 == 'all' || f1 == '*';
    final isAny2 = f2.isEmpty || f2 == 'any' || f2 == 'all' || f2 == '*';

    if (isAny1 || isAny2) {
      return true;
    }

    final isIp6_1 = f1 == 'ipv6' || f1 == 'ip6' || f1 == '6';
    final isIp6_2 = f2 == 'ipv6' || f2 == 'ip6' || f2 == '6';
    final isIp4_1 = f1 == 'ipv4' || f1 == 'ip4' || f1 == '4';
    final isIp4_2 = f2 == 'ipv4' || f2 == 'ip4' || f2 == '4';

    if (isIp4_1 && isIp4_2) return true;
    if (isIp6_1 && isIp6_2) return true;
    if ((isIp4_1 && isIp6_2) || (isIp6_1 && isIp4_2)) return false;

    return f1 == f2;
  }

  static bool cidrsOverlap(
    String? cidr1,
    String? cidr2, {
    String? family1,
    String? family2,
  }) {
    final c1 = cidr1?.trim() ?? '';
    final c2 = cidr2?.trim() ?? '';

    final isAny1 = c1.isEmpty || c1.toLowerCase() == 'any' || c1 == '*';
    final isAny2 = c2.isEmpty || c2.toLowerCase() == 'any' || c2 == '*';

    final f1 = family1?.trim().toLowerCase();
    final f2 = family2?.trim().toLowerCase();
    final isExplicitIp4_1 = f1 == 'ipv4' || f1 == 'ip4' || f1 == '4';
    final isExplicitIp6_1 = f1 == 'ipv6' || f1 == 'ip6' || f1 == '6';
    final isExplicitIp4_2 = f2 == 'ipv4' || f2 == 'ip4' || f2 == '4';
    final isExplicitIp6_2 = f2 == 'ipv6' || f2 == 'ip6' || f2 == '6';

    final isIp6_1 = c1.contains(':') || (isAny1 && isExplicitIp6_1);
    final isIp6_2 = c2.contains(':') || (isAny2 && isExplicitIp6_2);
    final isIp4_1 =
        (!c1.contains(':') && !isAny1) || (isAny1 && isExplicitIp4_1);
    final isIp4_2 =
        (!c2.contains(':') && !isAny2) || (isAny2 && isExplicitIp4_2);

    if ((isIp4_1 && isIp6_2) || (isIp6_1 && isIp4_2)) {
      return false;
    }

    if (!isAny1 && !isAny2 && c1.contains(':') != c2.contains(':')) {
      return false;
    }

    if (isIp6_1 || isIp6_2) {
      final r1 = parseIpv6Cidr(c1);
      final r2 = parseIpv6Cidr(c2);
      if (r1 == null || r2 == null) return false;
      return r1.overlaps(r2);
    }

    final r1 = parseIpv4Cidr(c1);
    final r2 = parseIpv4Cidr(c2);
    if (r1 == null || r2 == null) return false;
    return r1.overlaps(r2);
  }

  static PortForwardConflictResult checkPortForwardConflict(
    FirewallPortForwarding candidate,
    List<FirewallPortForwarding> existingRules,
  ) {
    for (final existing in existingRules) {
      if (candidate.sectionKey.isNotEmpty &&
          existing.sectionKey == candidate.sectionKey) {
        continue;
      }

      if (!existing.enabled) {
        continue;
      }

      if (candidate.srcZone.toLowerCase() != existing.srcZone.toLowerCase()) {
        continue;
      }

      final candDest = candidate.destZone.trim().toLowerCase();
      final existDest = existing.destZone.trim().toLowerCase();
      if (candDest.isNotEmpty &&
          existDest.isNotEmpty &&
          candDest != '*' &&
          existDest != '*' &&
          candDest != 'any' &&
          existDest != 'any' &&
          candDest != existDest) {
        continue;
      }

      if (!protocolsOverlap(candidate.proto, existing.proto)) {
        continue;
      }

      if (!familiesOverlap(candidate.family, existing.family)) {
        continue;
      }

      if (!portsOverlap(candidate.srcPort, existing.srcPort)) {
        continue;
      }

      if (!cidrsOverlap(
        candidate.srcIp,
        existing.srcIp,
        family1: candidate.family,
        family2: existing.family,
      )) {
        continue;
      }

      return PortForwardConflictResult.conflict(
        conflictingSectionKey: existing.sectionKey,
        reason:
            'External port ${candidate.srcPort} (${candidate.proto.toUpperCase()}) '
            'in zone "${candidate.srcZone}" conflicts with existing rule "${existing.name}".',
      );
    }

    return const PortForwardConflictResult.noConflict();
  }

  static ManagementPortSafetyResult checkManagementPortSafety(
    FirewallPortForwarding forward, {
    String? routerLanIp,
    Set<int>? customManagementPorts,
  }) {
    final ports = parsePortRanges(forward.destPort);
    final cleanDestIp = forward.destIp.trim().toLowerCase();

    final isTargetingRouter =
        cleanDestIp == 'any' ||
        cleanDestIp == '*' ||
        cleanDestIp == '127.0.0.1' ||
        cleanDestIp == 'localhost' ||
        (routerLanIp != null &&
            cleanDestIp == routerLanIp.toLowerCase().trim());

    final allMgmtPorts = <int, String>{
      ...routerManagementPorts,
      if (customManagementPorts != null)
        for (final p in customManagementPorts) p: 'Custom Management ($p)',
    };

    for (final interval in ports) {
      for (final mgmtPort in allMgmtPorts.keys) {
        if (interval[0] <= mgmtPort && mgmtPort <= interval[1]) {
          final service = allMgmtPorts[mgmtPort]!;
          if (isTargetingRouter) {
            return ManagementPortSafetyResult(
              isUnsafe: true,
              port: mgmtPort,
              serviceName: service,
              reason:
                  'Port forward targets internal router management service "$service" on port $mgmtPort.',
            );
          }
        }
      }
    }

    return const ManagementPortSafetyResult.safe();
  }

  static IncomingTrafficPreflightResult evaluateIncomingTrafficPreflight({
    required FirewallOverview overview,
    String? incomingPort,
    String? proto = 'any',
    String? srcIp,
    String? family = 'any',
    String? targetDeviceIp,
  }) {
    if (!overview.isAvailable) {
      return const IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.unableToDetermine,
        reason: 'Firewall configuration is unavailable.',
      );
    }

    final destZone = overview.primaryLanZoneName;
    if (destZone == null || destZone.isEmpty) {
      return const IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.unableToDetermine,
        reason:
            'Unable to identify internal destination zone from router firewall topology.',
      );
    }

    final wanZone = overview.zones.firstWhere(
      (z) => z.name.toLowerCase() == 'wan',
      orElse: () => const FirewallZone(
        name: '',
        input: '',
        output: '',
        forward: '',
        masquerade: false,
        networks: [],
      ),
    );
    if (wanZone.name.isEmpty) {
      return const IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.unableToDetermine,
        reason: 'Unable to identify WAN zone from router firewall topology.',
      );
    }

    for (final pf in overview.portForwards) {
      if (!pf.enabled) continue;
      if (pf.srcZone.toLowerCase() != 'wan') continue;

      final pfDest = pf.destZone.trim().toLowerCase();
      if (pfDest.isNotEmpty &&
          pfDest != '*' &&
          pfDest != 'any' &&
          pfDest != destZone.toLowerCase()) {
        continue;
      }

      if (!protocolsOverlap(proto, pf.proto)) continue;

      if (!familiesOverlap(family, pf.family)) continue;

      if (targetDeviceIp != null && targetDeviceIp.isNotEmpty) {
        final pfTarget = pf.destIp.trim().toLowerCase();
        if (pfTarget != 'any' &&
            pfTarget != '*' &&
            pfTarget != targetDeviceIp.trim().toLowerCase()) {
          continue;
        }
      }

      if (incomingPort != null &&
          incomingPort.trim().isNotEmpty &&
          incomingPort != 'any' &&
          incomingPort != '*') {
        if (!portsOverlap(incomingPort, pf.srcPort)) continue;
      }

      if (!cidrsOverlap(srcIp, pf.srcIp, family1: family, family2: pf.family)) {
        continue;
      }

      return IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.currentlyAllowed,
        conflictingRuleName: pf.name,
        conflictingSectionKey: pf.sectionKey,
        resolvedDestZone: destZone,
        reason:
            'This connection is currently permitted through your router by an active port forward ("${pf.name}").',
      );
    }

    for (final rule in overview.customRules) {
      if (!rule.enabled || rule.target.toUpperCase() != 'ACCEPT') continue;
      if (rule.srcZone.toLowerCase() != 'wan') continue;

      final ruleDest = rule.destZone.trim().toLowerCase();
      if (ruleDest.isNotEmpty &&
          ruleDest != '*' &&
          ruleDest != 'any' &&
          ruleDest != destZone.toLowerCase()) {
        continue;
      }

      if (!protocolsOverlap(proto, rule.proto)) continue;
      if (!familiesOverlap(family, rule.family)) continue;

      if (incomingPort != null &&
          incomingPort.trim().isNotEmpty &&
          incomingPort != 'any' &&
          incomingPort != '*') {
        if (rule.destPort != null &&
            rule.destPort!.isNotEmpty &&
            !portsOverlap(incomingPort, rule.destPort)) {
          continue;
        }
      }

      if (!cidrsOverlap(
        srcIp,
        rule.srcIp,
        family1: family,
        family2: rule.family,
      )) {
        continue;
      }

      return IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.currentlyAllowed,
        conflictingRuleName: rule.name,
        conflictingSectionKey: rule.sectionKey,
        resolvedDestZone: destZone,
        reason:
            'This connection is currently permitted through your router by an active rule ("${rule.name}").',
      );
    }

    final wanForward = wanZone.forward.toUpperCase();
    final defaultForward = overview.defaultPolicy.forward.toUpperCase();

    if (wanForward == 'REJECT' || wanForward == 'DROP') {
      return IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.alreadyBlocked,
        resolvedDestZone: destZone,
        reason:
            'This connection is already blocked by your router\'s default firewall protection.',
      );
    } else if (wanForward == 'ACCEPT') {
      return IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.currentlyAllowed,
        resolvedDestZone: destZone,
        reason: 'WAN zone default forwarding policy is set to ACCEPT.',
      );
    } else if (defaultForward == 'REJECT' || defaultForward == 'DROP') {
      return IncomingTrafficPreflightResult(
        status: IncomingTrafficPreflightStatus.alreadyBlocked,
        resolvedDestZone: destZone,
        reason:
            'This connection is already blocked by your router\'s default firewall protection.',
      );
    }

    return IncomingTrafficPreflightResult(
      status: IncomingTrafficPreflightStatus.unableToDetermine,
      resolvedDestZone: destZone,
      reason:
          'Could not safely determine effective firewall status for this connection.',
    );
  }

  static bool isValidIpv4(String input) {
    final clean = input.trim();
    if (clean.isEmpty || clean.contains('/')) return false;
    final octets = clean.split('.');
    if (octets.length != 4) return false;
    for (final o in octets) {
      final val = int.tryParse(o);
      if (val == null || val < 0 || val > 255) return false;
    }
    return true;
  }

  static bool isValidIpOrCidr(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return false;
    return parseIpv4Cidr(clean) != null || parseIpv6Cidr(clean) != null;
  }

  static NatReflectionCapabilityResult evaluateNatReflectionCapability({
    required FirewallOverview overview,
    required RouterCapabilities? capabilities,
    required NatReflectionRedirectContext redirectContext,
    FirewallTopologyFacts? topologyFacts,
  }) {
    if (capabilities != null && !capabilities.canModifyFirewall) {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unsupported,
        unsupportedReason: NatReflectionUnsupportedReason.readOnly,
        userFacingReason:
            'Read-only access: NAT reflection settings cannot be modified on this account.',
      );
    }

    final backend = capabilities?.firewallBackend ?? overview.backend;
    if (backend == FirewallBackend.none) {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unsupported,
        unsupportedReason: NatReflectionUnsupportedReason.noBackend,
        userFacingReason: 'Firewall engine is not available.',
      );
    }

    if (topologyFacts == null) {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason:
            'Network topology facts are unavailable to evaluate NAT reflection capability.',
      );
    }

    FirewallZone? wan4Zone;
    final wan4Net = topologyFacts.defaultIpv4RouteLogicalNetwork;
    if (wan4Net != null) {
      final matching = overview.zones
          .where((z) => z.networks.contains(wan4Net))
          .toList();
      if (matching.length == 1) {
        wan4Zone = matching.first;
      }
    }

    FirewallZone? wan6Zone;
    final wan6Net = topologyFacts.defaultIpv6RouteLogicalNetwork;
    if (wan6Net != null) {
      final matching = overview.zones
          .where((z) => z.networks.contains(wan6Net))
          .toList();
      if (matching.length == 1) {
        wan6Zone = matching.first;
      }
    }

    final fam = redirectContext.family.trim().toLowerCase();
    final isExplicitIp6 = fam == 'ipv6' || fam == 'ip6' || fam == '6';
    final isExplicitIp4 = fam == 'ipv4' || fam == 'ip4' || fam == '4';

    if (isExplicitIp6) {
      if (backend == FirewallBackend.fw3) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unsupported,
          unsupportedReason:
              NatReflectionUnsupportedReason.ipv6UnsupportedOnFw3,
          userFacingReason:
              'IPv6 NAT reflection is not supported on Firewall3 (iptables).',
        );
      }
      if (capabilities != null && !capabilities.supportsIpv6InternetFirewall) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'IPv6 Internet firewall isn\'t running on this router.',
        );
      }
      if (wan6Zone == null) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Authoritative IPv6 WAN zone could not be determined.',
        );
      }
      if (redirectContext.srcZone.toLowerCase() !=
          wan6Zone.name.toLowerCase()) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Source zone does not match authoritative IPv6 WAN zone.',
        );
      }
      if (!wan6Zone.masquerade6) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unsupported,
          unsupportedReason: NatReflectionUnsupportedReason.noMasqueradingWan,
          userFacingReason:
              'NAT reflection requires active IPv6 masquerading on the WAN zone (${redirectContext.srcZone}).',
        );
      }
      if (topologyFacts.externalIpv6AddressFact == null) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Authoritative external IPv6 address is missing or ambiguous.',
        );
      }
    } else if (isExplicitIp4) {
      if (wan4Zone == null) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Authoritative IPv4 WAN zone could not be determined.',
        );
      }
      if (redirectContext.srcZone.toLowerCase() !=
          wan4Zone.name.toLowerCase()) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Source zone does not match authoritative IPv4 WAN zone.',
        );
      }
      if (!wan4Zone.masquerade) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unsupported,
          unsupportedReason: NatReflectionUnsupportedReason.noMasqueradingWan,
          userFacingReason:
              'NAT reflection requires active masquerading on the WAN zone (${redirectContext.srcZone}).',
        );
      }
      if (topologyFacts.externalIpv4AddressFact == null) {
        return const NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Authoritative external IPv4 address is missing or ambiguous.',
        );
      }
    } else {
      final isDestIp6 =
          Ipv6AddressUtil.tryParse(redirectContext.destIp) != null;

      if (isDestIp6) {
        if (backend == FirewallBackend.fw3) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unsupported,
            unsupportedReason:
                NatReflectionUnsupportedReason.ipv6UnsupportedOnFw3,
            userFacingReason:
                'IPv6 NAT reflection is not supported on Firewall3 (iptables).',
          );
        }
        if (capabilities != null &&
            !capabilities.supportsIpv6InternetFirewall) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason:
                'IPv6 Internet firewall isn\'t running on this router.',
          );
        }
        if (wan6Zone == null ||
            redirectContext.srcZone.toLowerCase() !=
                wan6Zone.name.toLowerCase()) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason:
                'Authoritative IPv6 WAN zone could not be determined.',
          );
        }
        if (!wan6Zone.masquerade6) {
          return NatReflectionCapabilityResult(
            status: NatReflectionStatus.unsupported,
            unsupportedReason: NatReflectionUnsupportedReason.noMasqueradingWan,
            userFacingReason:
                'NAT reflection requires active IPv6 masquerading on the WAN zone (${redirectContext.srcZone}).',
          );
        }
        if (topologyFacts.externalIpv6AddressFact == null) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason: 'External IPv6 address is missing or ambiguous.',
          );
        }
      } else {
        if (wan4Zone == null ||
            redirectContext.srcZone.toLowerCase() !=
                wan4Zone.name.toLowerCase()) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason:
                'Authoritative IPv4 WAN zone could not be determined.',
          );
        }
        if (!wan4Zone.masquerade) {
          return NatReflectionCapabilityResult(
            status: NatReflectionStatus.unsupported,
            unsupportedReason: NatReflectionUnsupportedReason.noMasqueradingWan,
            userFacingReason:
                'NAT reflection requires active masquerading on the WAN zone (${redirectContext.srcZone}).',
          );
        }
        if (topologyFacts.externalIpv4AddressFact == null) {
          return const NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason: 'External IPv4 address is missing or ambiguous.',
          );
        }
      }
    }

    final destZoneName = redirectContext.destZone.trim().toLowerCase();
    final srcZoneName = redirectContext.srcZone.trim().toLowerCase();

    if (destZoneName == srcZoneName) {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unsupported,
        unsupportedReason: NatReflectionUnsupportedReason.incompatibleZones,
        userFacingReason:
            'NAT reflection requires an internal destination zone distinct from the external source zone.',
      );
    }

    final destZone = overview.zones.firstWhere(
      (z) => z.name.toLowerCase() == destZoneName,
      orElse: () => const FirewallZone(
        name: '',
        input: '',
        output: '',
        forward: '',
        masquerade: false,
        networks: [],
      ),
    );
    if (destZone.name.isEmpty) {
      return NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason:
            'Destination zone "${redirectContext.destZone}" not found.',
      );
    }

    final isDestExternal =
        (wan4Net != null && destZone.networks.contains(wan4Net)) ||
        (wan6Net != null && destZone.networks.contains(wan6Net)) ||
        destZone.masquerade ||
        destZone.masquerade6;
    if (isDestExternal) {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unsupported,
        unsupportedReason: NatReflectionUnsupportedReason.incompatibleZones,
        userFacingReason:
            'NAT reflection requires an internal destination zone distinct from the external source zone.',
      );
    }

    final hasHostFacing = destZone.networks.any(
      (net) => topologyFacts.logicalNetworkHasHostFacingDevice[net] == true,
    );
    if (!hasHostFacing) {
      return NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason:
            'Destination zone "${redirectContext.destZone}" does not bind an authoritative host-facing device.',
      );
    }

    final hasInternalSubnet = destZone.networks.any((net) {
      final ip4List = topologyFacts.logicalNetworkIpv4Addresses[net] ?? [];
      final hasIp4Internal = ip4List.any((f) => f.isSuitableInternal);
      final ip6List = topologyFacts.logicalNetworkIpv6Addresses[net] ?? [];
      final hasIp6Internal = ip6List.any(
        (f) => (f.isUla || f.isGlobalUnicast) && !f.isLinkLocal,
      );
      return hasIp4Internal || hasIp6Internal;
    });
    if (!hasInternalSubnet) {
      return NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason:
            'Destination zone "${redirectContext.destZone}" lacks positive local subnet facts.',
      );
    }

    final cleanDestIp = redirectContext.destIp.trim();
    if (cleanDestIp.isEmpty ||
        cleanDestIp.toLowerCase() == 'any' ||
        cleanDestIp == '*' ||
        cleanDestIp == '0.0.0.0' ||
        cleanDestIp == '::') {
      return const NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason: 'Destination IP must be a concrete unicast address.',
      );
    }

    bool destIpReachable = false;
    for (final net in destZone.networks) {
      final ip4List = topologyFacts.logicalNetworkIpv4Addresses[net] ?? [];
      for (final f in ip4List) {
        if (f.contains(cleanDestIp)) {
          destIpReachable = true;
          break;
        }
      }
      if (destIpReachable) break;

      final routedList = topologyFacts.logicalNetworkRoutedSubnets[net] ?? [];
      for (final cidr in routedList) {
        if (Ipv4CidrUtil.containsCidr(cidr, cleanDestIp)) {
          destIpReachable = true;
          break;
        }
      }
      if (destIpReachable) break;

      final ip6List = topologyFacts.logicalNetworkIpv6Addresses[net] ?? [];
      for (final f in ip6List) {
        if (f.contains(cleanDestIp)) {
          destIpReachable = true;
          break;
        }
      }
      if (destIpReachable) break;
    }

    if (!destIpReachable) {
      return NatReflectionCapabilityResult(
        status: NatReflectionStatus.unknown,
        userFacingReason:
            'Destination IP "$cleanDestIp" is not reachable within destination zone "${redirectContext.destZone}".',
      );
    }

    final effectiveReflectionZones =
        redirectContext.existingReflectionZones.isNotEmpty
        ? redirectContext.existingReflectionZones
        : [redirectContext.destZone];

    for (final rzName in effectiveReflectionZones) {
      final cleanRzName = rzName.trim().toLowerCase();
      final rzZone = overview.zones.firstWhere(
        (z) => z.name.toLowerCase() == cleanRzName,
        orElse: () => const FirewallZone(
          name: '',
          input: '',
          output: '',
          forward: '',
          masquerade: false,
          networks: [],
        ),
      );
      if (rzZone.name.isEmpty) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Reflection zone "$rzName" not found in firewall configuration.',
        );
      }

      final isRzExternal =
          (wan4Net != null && rzZone.networks.contains(wan4Net)) ||
          (wan6Net != null && rzZone.networks.contains(wan6Net)) ||
          rzZone.masquerade ||
          rzZone.masquerade6 ||
          cleanRzName == srcZoneName;
      if (isRzExternal) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unsupported,
          unsupportedReason: NatReflectionUnsupportedReason.incompatibleZones,
          userFacingReason:
              'Reflection zone "$rzName" cannot be an external or WAN zone.',
        );
      }

      final rzHostFacing = rzZone.networks.any(
        (net) => topologyFacts.logicalNetworkHasHostFacingDevice[net] == true,
      );
      if (!rzHostFacing) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Reflection zone "$rzName" does not bind an authoritative host-facing device.',
        );
      }

      final hasSnatAnchor = rzZone.networks.any((net) {
        final ip4List = topologyFacts.logicalNetworkIpv4Addresses[net] ?? [];
        final hasIp4 = ip4List.any((f) => f.isSuitableInternal);
        final ip6List = topologyFacts.logicalNetworkIpv6Addresses[net] ?? [];
        final hasIp6 = ip6List.any(
          (f) => (f.isUla || f.isGlobalUnicast) && !f.isLinkLocal,
        );
        return hasIp4 || hasIp6;
      });
      if (!hasSnatAnchor) {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason:
              'Reflection zone "$rzName" lacks an internal router IP to anchor hairpin SNAT.',
        );
      }

      if (cleanRzName != destZoneName) {
        final hasExplicitFwd = overview.forwardings.any(
          (f) =>
              f.srcZone.toLowerCase() == cleanRzName &&
              f.destZone.toLowerCase() == destZoneName,
        );
        final hasPermissiveFwdPolicy = rzZone.forward.toUpperCase() == 'ACCEPT';

        if (!hasExplicitFwd && !hasPermissiveFwdPolicy) {
          return NatReflectionCapabilityResult(
            status: NatReflectionStatus.unknown,
            userFacingReason:
                'Inter-zone reflection from "$rzName" to "${redirectContext.destZone}" is not permitted by forwarding policy.',
          );
        }
      }
    }

    final rsrc = redirectContext.existingReflectionSrc?.trim().toLowerCase();
    if (rsrc != null && rsrc.isNotEmpty) {
      if (rsrc != 'internal' && rsrc != 'external') {
        return NatReflectionCapabilityResult(
          status: NatReflectionStatus.unknown,
          userFacingReason: 'Unrecognized reflection_src value "$rsrc".',
        );
      }
    }

    return const NatReflectionCapabilityResult(
      status: NatReflectionStatus.supported,
      userFacingReason:
          'NAT reflection is fully supported for this port forward.',
    );
  }
}

class Ipv4CidrUtil {
  static int? ipToInt(String ip) {
    final clean = ip.trim();
    final octets = clean.split('.');
    if (octets.length != 4) return null;
    int res = 0;
    for (int i = 0; i < 4; i++) {
      final o = int.tryParse(octets[i]);
      if (o == null || o < 0 || o > 255) return null;
      res = (res << 8) | o;
    }
    return res & 0xFFFFFFFF;
  }

  static int prefixToMask(int prefixLength) {
    if (prefixLength <= 0) return 0;
    if (prefixLength >= 32) return 0xFFFFFFFF;
    return ((0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF);
  }

  static bool containsIp(
    String networkIp,
    String candidateIp,
    int prefixLength,
  ) {
    final netInt = ipToInt(networkIp);
    final candInt = ipToInt(candidateIp);
    if (netInt == null || candInt == null) return false;
    final mask = prefixToMask(prefixLength);
    return (netInt & mask) == (candInt & mask);
  }

  static bool containsCidr(String cidr, String targetIpOrCidr) {
    final parts = cidr.trim().split('/');
    if (parts.length != 2) return false;
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return false;

    if (targetIpOrCidr.contains('/')) {
      final childParts = targetIpOrCidr.trim().split('/');
      if (childParts.length != 2) return false;
      final childPrefix = int.tryParse(childParts[1]);
      if (childPrefix == null || childPrefix < 0 || childPrefix > 32) {
        return false;
      }
      if (prefix > childPrefix) return false;
      return containsIp(parts[0], childParts[0], prefix);
    }

    return containsIp(parts[0], targetIpOrCidr, prefix);
  }
}

class Ipv4AddressFact {
  final String address;
  final int prefixLength;
  final String subnetCidr;
  final bool isLoopback;
  final bool isLinkLocal;
  final bool isBroadcast;
  final bool isPrivateRfc1918;
  final bool isCgnatRfc6598;
  final bool isPublicRoutable;

  const Ipv4AddressFact({
    required this.address,
    required this.prefixLength,
    required this.subnetCidr,
    required this.isLoopback,
    required this.isLinkLocal,
    required this.isBroadcast,
    required this.isPrivateRfc1918,
    required this.isCgnatRfc6598,
    required this.isPublicRoutable,
  });

  bool get isSuitableWan => !isLoopback && !isLinkLocal && !isBroadcast;
  bool get isSuitableInternal =>
      (isPrivateRfc1918 || isCgnatRfc6598 || isPublicRoutable) &&
      !isLoopback &&
      !isLinkLocal &&
      !isBroadcast;

  bool contains(String targetIp) =>
      Ipv4CidrUtil.containsIp(address, targetIp, prefixLength);
}

class Ipv6AddressUtil {
  static List<int>? tryParse(String addr) {
    try {
      final clean = addr.trim().split('%').first;
      return Uri.parseIPv6Address(clean);
    } catch (_) {
      return null;
    }
  }

  static bool isLinkLocal(List<int> bytes) {
    if (bytes.length != 16) return false;
    return bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80;
  }

  static bool isLoopback(List<int> bytes) {
    if (bytes.length != 16) return false;
    for (int i = 0; i < 15; i++) {
      if (bytes[i] != 0) return false;
    }
    return bytes[15] == 1;
  }

  static bool isUnspecified(List<int> bytes) {
    if (bytes.length != 16) return false;
    for (int i = 0; i < 16; i++) {
      if (bytes[i] != 0) return false;
    }
    return true;
  }

  static bool isMulticast(List<int> bytes) {
    if (bytes.length != 16) return false;
    return bytes[0] == 0xFF;
  }

  static bool isUla(List<int> bytes) {
    if (bytes.length != 16) return false;
    return (bytes[0] & 0xFE) == 0xFC;
  }

  static bool isGlobalUnicast(List<int> bytes) {
    if (bytes.length != 16) return false;
    if (isLinkLocal(bytes) ||
        isLoopback(bytes) ||
        isMulticast(bytes) ||
        isUnspecified(bytes) ||
        isUla(bytes)) {
      return false;
    }
    return (bytes[0] & 0xE0) == 0x20;
  }

  static bool containsIp(
    List<int> networkBytes,
    List<int> candidateBytes,
    int prefixLength,
  ) {
    if (networkBytes.length != 16 || candidateBytes.length != 16) return false;
    if (prefixLength <= 0) return true;
    if (prefixLength > 128) prefixLength = 128;

    final fullBytes = prefixLength ~/ 8;
    for (int i = 0; i < fullBytes; i++) {
      if (networkBytes[i] != candidateBytes[i]) return false;
    }

    final remainingBits = prefixLength % 8;
    if (remainingBits > 0) {
      final mask = (0xFF << (8 - remainingBits)) & 0xFF;
      if ((networkBytes[fullBytes] & mask) !=
          (candidateBytes[fullBytes] & mask)) {
        return false;
      }
    }
    return true;
  }
}

class Ipv6AddressFact {
  final String address;
  final int prefixLength;
  final List<int> rawBytes;
  final bool isLinkLocal;
  final bool isGlobalUnicast;
  final bool isUla;
  final int? preferredLifetime;
  final int? validLifetime;

  const Ipv6AddressFact({
    required this.address,
    required this.prefixLength,
    required this.rawBytes,
    required this.isLinkLocal,
    required this.isGlobalUnicast,
    required this.isUla,
    this.preferredLifetime,
    this.validLifetime,
  });

  static Ipv6AddressFact? tryParse({
    required String address,
    required int prefixLength,
    int? preferredLifetime,
    int? validLifetime,
  }) {
    final bytes = Ipv6AddressUtil.tryParse(address);
    if (bytes == null) return null;
    return Ipv6AddressFact(
      address: address,
      prefixLength: prefixLength,
      rawBytes: bytes,
      isLinkLocal: Ipv6AddressUtil.isLinkLocal(bytes),
      isGlobalUnicast: Ipv6AddressUtil.isGlobalUnicast(bytes),
      isUla: Ipv6AddressUtil.isUla(bytes),
      preferredLifetime: preferredLifetime,
      validLifetime: validLifetime,
    );
  }

  bool contains(String targetIp) {
    final targetBytes = Ipv6AddressUtil.tryParse(targetIp);
    if (targetBytes == null) return false;
    return Ipv6AddressUtil.containsIp(rawBytes, targetBytes, prefixLength);
  }
}

class FirewallTopologyFacts {
  final String? defaultIpv4RouteLogicalNetwork;
  final String? defaultIpv4Gateway;
  final String? defaultIpv6RouteLogicalNetwork;
  final String? defaultIpv6Gateway;
  final Ipv4AddressFact? externalIpv4AddressFact;
  final Ipv6AddressFact? externalIpv6AddressFact;
  final Map<String, List<Ipv4AddressFact>> logicalNetworkIpv4Addresses;
  final Map<String, List<Ipv6AddressFact>> logicalNetworkIpv6Addresses;
  final Map<String, List<String>> logicalNetworkRoutedSubnets;
  final Map<String, bool> logicalNetworkHasHostFacingDevice;

  const FirewallTopologyFacts({
    this.defaultIpv4RouteLogicalNetwork,
    this.defaultIpv4Gateway,
    this.defaultIpv6RouteLogicalNetwork,
    this.defaultIpv6Gateway,
    this.externalIpv4AddressFact,
    this.externalIpv6AddressFact,
    this.logicalNetworkIpv4Addresses = const {},
    this.logicalNetworkIpv6Addresses = const {},
    this.logicalNetworkRoutedSubnets = const {},
    this.logicalNetworkHasHostFacingDevice = const {},
  });

  bool hasHostFacingDevice(String network) =>
      logicalNetworkHasHostFacingDevice[network] == true;

  Set<String> get hostFacingLogicalNetworks => logicalNetworkHasHostFacingDevice
      .entries
      .where((e) => e.value)
      .map((e) => e.key)
      .toSet();

  factory FirewallTopologyFacts.fromNetworkDump(
    Map<String, dynamic>? dumpData, {
    Map<String, dynamic>? networkDevices,
  }) {
    if (dumpData == null) return const FirewallTopologyFacts();

    final List<Map<String, dynamic>> ipv4DefaultCandidates = [];
    final List<Map<String, dynamic>> ipv6DefaultCandidates = [];
    final ip4FactsByNet = <String, List<Ipv4AddressFact>>{};
    final ip6FactsByNet = <String, List<Ipv6AddressFact>>{};
    final routedSubnetsByNet = <String, List<String>>{};
    final hostFacingByNet = <String, bool>{};

    final ifaceList = dumpData['interface'];
    if (ifaceList is List) {
      for (final raw in ifaceList) {
        if (raw is! Map<String, dynamic>) continue;
        final netName = raw['interface']?.toString();
        if (netName == null || netName.isEmpty) continue;

        final routeList = raw['route'];
        if (routeList is List) {
          for (final r in routeList) {
            if (r is! Map) continue;
            final target = r['target']?.toString();
            final mask = r['mask'];
            final nexthop = r['nexthop']?.toString();
            final metric = (r['metric'] is int)
                ? r['metric'] as int
                : int.tryParse(r['metric']?.toString() ?? '') ?? 0;

            if (target == '0.0.0.0/0' ||
                (target == '0.0.0.0' && (mask == 0 || mask == '0'))) {
              ipv4DefaultCandidates.add({
                'network': netName,
                'gateway': nexthop,
                'metric': metric,
              });
            } else if (target == '::/0' ||
                (target == '::' && (mask == 0 || mask == '0'))) {
              ipv6DefaultCandidates.add({
                'network': netName,
                'gateway': nexthop,
                'metric': metric,
              });
            } else if (target != null && target.isNotEmpty) {
              final cidr = (mask != null && !target.contains('/'))
                  ? '$target/$mask'
                  : target;
              routedSubnetsByNet.putIfAbsent(netName, () => []).add(cidr);
            }
          }
        }

        final ip4List = raw['ipv4-address'];
        if (ip4List is List && ip4List.isNotEmpty) {
          final facts = <Ipv4AddressFact>[];
          for (final entry in ip4List) {
            if (entry is! Map) continue;
            final addr = entry['address']?.toString();
            if (addr == null || addr.isEmpty) continue;
            final pfx = (entry['mask'] is int)
                ? entry['mask'] as int
                : int.tryParse(entry['mask']?.toString() ?? '') ?? 24;
            final cidr = '$addr/$pfx';

            final isLoop = addr.startsWith('127.');
            final isLl = addr.startsWith('169.254.');
            final isBc = addr == '255.255.255.255' || addr == '0.0.0.0';
            final isPriv =
                addr.startsWith('10.') ||
                addr.startsWith('192.168.') ||
                RegExp(r'^172\.(1[6-9]|2[0-9]|3[0-1])\.').hasMatch(addr);
            final isCg = RegExp(
              r'^100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.',
            ).hasMatch(addr);

            facts.add(
              Ipv4AddressFact(
                address: addr,
                prefixLength: pfx,
                subnetCidr: cidr,
                isLoopback: isLoop,
                isLinkLocal: isLl,
                isBroadcast: isBc,
                isPrivateRfc1918: isPriv,
                isCgnatRfc6598: isCg,
                isPublicRoutable: !isLoop && !isLl && !isBc && !isPriv && !isCg,
              ),
            );
          }
          if (facts.isNotEmpty) {
            ip4FactsByNet[netName] = facts;
          }
        }

        final ip6List = raw['ipv6-address'];
        if (ip6List is List && ip6List.isNotEmpty) {
          final facts = <Ipv6AddressFact>[];
          for (final entry in ip6List) {
            if (entry is! Map) continue;
            final addr = entry['address']?.toString();
            if (addr == null || addr.isEmpty) continue;
            final pfx = (entry['mask'] is int)
                ? entry['mask'] as int
                : int.tryParse(entry['mask']?.toString() ?? '') ?? 64;
            final pref = (entry['preferred'] is int)
                ? entry['preferred'] as int
                : int.tryParse(entry['preferred']?.toString() ?? '');
            final val = (entry['valid'] is int)
                ? entry['valid'] as int
                : int.tryParse(entry['valid']?.toString() ?? '');

            final fact = Ipv6AddressFact.tryParse(
              address: addr,
              prefixLength: pfx,
              preferredLifetime: pref,
              validLifetime: val,
            );
            if (fact != null) {
              facts.add(fact);
            }
          }
          if (facts.isNotEmpty) {
            ip6FactsByNet[netName] = facts;
          }
        }
      }
    }

    String? defIpv4Net;
    String? defIpv4Gw;
    if (ipv4DefaultCandidates.isNotEmpty) {
      ipv4DefaultCandidates.sort(
        (a, b) => (a['metric'] as int).compareTo(b['metric'] as int),
      );
      final lowestMetric = ipv4DefaultCandidates[0]['metric'] as int;
      final tied = ipv4DefaultCandidates
          .where((c) => c['metric'] == lowestMetric)
          .toList();

      if (tied.length == 1) {
        defIpv4Net = tied[0]['network'] as String?;
        defIpv4Gw = tied[0]['gateway'] as String?;
      } else {
        final firstNet = tied[0]['network'] as String?;
        final firstGw = tied[0]['gateway'] as String?;
        final allSameNet = tied.every((c) => c['network'] == firstNet);
        final allSameGw = tied.every((c) => c['gateway'] == firstGw);
        if (allSameNet && allSameGw) {
          defIpv4Net = firstNet;
          defIpv4Gw = firstGw;
        } else {
          defIpv4Net = null;
          defIpv4Gw = null;
        }
      }
    }

    String? defIpv6Net;
    String? defIpv6Gw;
    if (ipv6DefaultCandidates.isNotEmpty) {
      ipv6DefaultCandidates.sort(
        (a, b) => (a['metric'] as int).compareTo(b['metric'] as int),
      );
      final lowestMetric = ipv6DefaultCandidates[0]['metric'] as int;
      final tied = ipv6DefaultCandidates
          .where((c) => c['metric'] == lowestMetric)
          .toList();

      if (tied.length == 1) {
        defIpv6Net = tied[0]['network'] as String?;
        defIpv6Gw = tied[0]['gateway'] as String?;
      } else {
        final firstNet = tied[0]['network'] as String?;
        final firstGw = tied[0]['gateway'] as String?;
        final allSameNet = tied.every((c) => c['network'] == firstNet);
        final allSameGw = tied.every((c) => c['gateway'] == firstGw);
        if (allSameNet && allSameGw) {
          defIpv6Net = firstNet;
          defIpv6Gw = firstGw;
        } else {
          defIpv6Net = null;
          defIpv6Gw = null;
        }
      }
    }

    Ipv4AddressFact? extIp4Fact;
    if (defIpv4Net != null && ip4FactsByNet.containsKey(defIpv4Net)) {
      final candidates = ip4FactsByNet[defIpv4Net]!
          .where((f) => f.isSuitableWan)
          .toList();
      if (candidates.length == 1) {
        extIp4Fact = candidates.first;
      } else if (candidates.length > 1) {
        final matchingGwSubnet = candidates.where((c) {
          if (defIpv4Gw == null) return false;
          return Ipv4CidrUtil.containsIp(c.address, defIpv4Gw, c.prefixLength);
        }).toList();
        if (matchingGwSubnet.length == 1) {
          extIp4Fact = matchingGwSubnet.first;
        } else {
          extIp4Fact = null;
        }
      }
    }

    Ipv6AddressFact? extIp6Fact;
    if (defIpv6Net != null && ip6FactsByNet.containsKey(defIpv6Net)) {
      final candidates = ip6FactsByNet[defIpv6Net]!
          .where(
            (f) =>
                f.isGlobalUnicast &&
                !f.isLinkLocal &&
                (f.validLifetime == null || f.validLifetime! > 0),
          )
          .toList();
      if (candidates.length == 1) {
        extIp6Fact = candidates.first;
      } else if (candidates.length > 1) {
        final gwBytes = defIpv6Gw != null
            ? Ipv6AddressUtil.tryParse(defIpv6Gw)
            : null;
        final matchingGw =
            (gwBytes != null && Ipv6AddressUtil.isGlobalUnicast(gwBytes))
            ? candidates
                  .where(
                    (c) => Ipv6AddressUtil.containsIp(
                      c.rawBytes,
                      gwBytes,
                      c.prefixLength,
                    ),
                  )
                  .toList()
            : <Ipv6AddressFact>[];

        if (matchingGw.length == 1) {
          extIp6Fact = matchingGw.first;
        } else {
          final pool = matchingGw.length > 1 ? matchingGw : candidates;
          final withLifetime = pool
              .where((c) => c.preferredLifetime != null)
              .toList();
          if (withLifetime.length == pool.length) {
            withLifetime.sort(
              (a, b) => b.preferredLifetime!.compareTo(a.preferredLifetime!),
            );
            final highest = withLifetime.first.preferredLifetime!;
            final tied = withLifetime
                .where((c) => c.preferredLifetime == highest)
                .toList();
            if (tied.length == 1) {
              extIp6Fact = tied.first;
            } else {
              extIp6Fact = null;
            }
          } else {
            extIp6Fact = null;
          }
        }
      }
    }

    final wanDevices = <String>{};
    if (ifaceList is List) {
      for (final raw in ifaceList) {
        if (raw is! Map) continue;
        final netName = raw['interface']?.toString();
        if (netName == defIpv4Net || netName == defIpv6Net) {
          final d = raw['device']?.toString();
          if (d != null && d.isNotEmpty) wanDevices.add(d);
          final l3 = raw['l3_device']?.toString();
          if (l3 != null && l3.isNotEmpty) wanDevices.add(l3);
        }
      }
    }

    if (ifaceList is List) {
      for (final raw in ifaceList) {
        if (raw is! Map) continue;
        final netName = raw['interface']?.toString();
        if (netName == null || netName.isEmpty) continue;

        if (netName == defIpv4Net || netName == defIpv6Net) {
          hostFacingByNet[netName] = false;
          continue;
        }

        final devName =
            raw['device']?.toString() ?? raw['l3_device']?.toString();
        if (devName == null ||
            devName.isEmpty ||
            wanDevices.contains(devName)) {
          hostFacingByNet[netName] = false;
          continue;
        }

        bool isHostFacing = false;
        if (networkDevices != null && networkDevices.containsKey(devName)) {
          final dInfo = networkDevices[devName];
          if (dInfo is Map) {
            final dtype = dInfo['type']?.toString().toLowerCase();

            final isTunnel =
                dtype == 'tunnel' ||
                dtype == 'wireguard' ||
                dtype == 'gre' ||
                dtype == 'veth' ||
                dtype == 'dummy';

            if (!isTunnel) {
              if (dtype == 'bridge') {
                final members =
                    dInfo['bridge_members'] ??
                    dInfo['bridge-members'] ??
                    dInfo['ports'];
                final mList = (members is List)
                    ? members.map((e) => e.toString()).toList()
                    : <String>[];
                if (mList.isNotEmpty &&
                    !mList.any((m) => wanDevices.contains(m))) {
                  bool hasPositiveMember = false;
                  for (final m in mList) {
                    if (networkDevices.containsKey(m)) {
                      final mInfo = networkDevices[m];
                      if (mInfo is Map) {
                        final mType = mInfo['type']?.toString().toLowerCase();
                        if (mType == 'wireless') {
                          hasPositiveMember = true;
                          break;
                        } else if (mType == 'network device' ||
                            mType == 'ethernet') {
                          hasPositiveMember = true;
                          break;
                        }
                      }
                    }
                  }
                  isHostFacing = hasPositiveMember;
                }
              } else if (dtype == 'wireless') {
                isHostFacing = true;
              } else if (dtype == 'network device' || dtype == 'ethernet') {
                final hasIp4Internal =
                    ip4FactsByNet.containsKey(netName) &&
                    ip4FactsByNet[netName]!.any((f) => f.isSuitableInternal);
                final hasIp6Internal =
                    ip6FactsByNet.containsKey(netName) &&
                    ip6FactsByNet[netName]!.any(
                      (f) => (f.isUla || f.isGlobalUnicast) && !f.isLinkLocal,
                    );
                isHostFacing = hasIp4Internal || hasIp6Internal;
              }
            }
          }
        } else {
          isHostFacing = false;
        }

        hostFacingByNet[netName] = isHostFacing;
      }
    }

    return FirewallTopologyFacts(
      defaultIpv4RouteLogicalNetwork: defIpv4Net,
      defaultIpv4Gateway: defIpv4Gw,
      defaultIpv6RouteLogicalNetwork: defIpv6Net,
      defaultIpv6Gateway: defIpv6Gw,
      externalIpv4AddressFact: extIp4Fact,
      externalIpv6AddressFact: extIp6Fact,
      logicalNetworkIpv4Addresses: ip4FactsByNet,
      logicalNetworkIpv6Addresses: ip6FactsByNet,
      logicalNetworkRoutedSubnets: routedSubnetsByNet,
      logicalNetworkHasHostFacingDevice: hostFacingByNet,
    );
  }
}

enum NatReflectionStatus { supported, unsupported, unknown }

enum NatReflectionUnsupportedReason {
  readOnly,
  noMasqueradingWan,
  incompatibleZones,
  noInternalLanZone,
  noBackend,
  ipv6UnsupportedOnFw3,
}

class NatReflectionCapabilityResult {
  final NatReflectionStatus status;
  final NatReflectionUnsupportedReason? unsupportedReason;
  final String userFacingReason;

  const NatReflectionCapabilityResult({
    required this.status,
    this.unsupportedReason,
    required this.userFacingReason,
  });

  bool get isSupported => status == NatReflectionStatus.supported;
}

class NatReflectionRedirectContext {
  final String srcZone;
  final String destZone;
  final String destIp;
  final String family;
  final String? existingReflection;
  final String? existingReflectionSrc;
  final List<String> existingReflectionZones;

  const NatReflectionRedirectContext({
    required this.srcZone,
    required this.destZone,
    required this.destIp,
    this.family = 'any',
    this.existingReflection,
    this.existingReflectionSrc,
    this.existingReflectionZones = const [],
  });

  factory NatReflectionRedirectContext.fromDraft({
    required String srcZone,
    required String destZone,
    required String destIp,
    String family = 'any',
  }) {
    return NatReflectionRedirectContext(
      srcZone: srcZone,
      destZone: destZone,
      destIp: destIp,
      family: family,
    );
  }

  factory NatReflectionRedirectContext.fromPortForward(
    FirewallPortForwarding forward,
  ) {
    final rawRz = forward.rawUciValues['reflection_zone'];
    final List<String> rzList = [];
    if (rawRz is List) {
      rzList.addAll(rawRz.map((e) => e.toString()));
    } else if (rawRz is String && rawRz.trim().isNotEmpty) {
      rzList.addAll(rawRz.trim().split(RegExp(r'\s+')));
    }

    return NatReflectionRedirectContext(
      srcZone: forward.srcZone,
      destZone: forward.destZone,
      destIp: forward.destIp,
      family: forward.family,
      existingReflection: forward.rawUciValues['reflection']?.toString(),
      existingReflectionSrc: forward.rawUciValues['reflection_src']?.toString(),
      existingReflectionZones: rzList,
    );
  }
}
