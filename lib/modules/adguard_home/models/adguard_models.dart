// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum AdGuardProtectionState {
  enabled,

  paused,

  disabled;

  static AdGuardProtectionState resolve(
    Map<String, dynamic> json, {
    DateTime? now,
  }) {
    final bool isEnabled = json['protection_enabled'] == true;
    if (isEnabled) {
      return AdGuardProtectionState.enabled;
    }

    final dynamic rawDuration = json['protection_disabled_duration'];
    if (rawDuration != null && rawDuration is num) {
      final int durationMs = rawDuration.toInt();
      if (durationMs > 0) {
        return AdGuardProtectionState.paused;
      }
      return AdGuardProtectionState.disabled;
    }

    final dynamic rawUntil = json['protection_disabled_until'];
    if (rawUntil != null) {
      final untilDate = parseTimestamp(rawUntil);
      if (untilDate != null) {
        final currentTime = now ?? DateTime.now();
        if (untilDate.isAfter(currentTime)) {
          return AdGuardProtectionState.paused;
        }
      }
    }

    return AdGuardProtectionState.disabled;
  }

  static DateTime? parseTimestamp(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final int val = raw.toInt();
      if (val <= 0) return null;
      if (val > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(val, isUtc: true);
      }
      if (val > 100000000) {
        return DateTime.fromMillisecondsSinceEpoch(val * 1000, isUtc: true);
      }
      return null;
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      final asNum = num.tryParse(trimmed);
      if (asNum != null) {
        return parseTimestamp(asNum);
      }
      return DateTime.tryParse(trimmed);
    }
    return null;
  }
}

enum AdGuardConnectionStatus {
  initial,

  discovering,

  authenticated,

  authRequired,

  apiUnreachable,

  invalidEndpoint,

  degraded,

  error,
}

@immutable
class AdGuardStatus {
  final String version;
  final bool running;
  final AdGuardProtectionState protectionState;
  final int pauseDurationMs;
  final List<String> dnsAddresses;
  final int dnsPort;
  final int httpPort;
  final int? startTimeMs;

  const AdGuardStatus({
    required this.version,
    required this.running,
    required this.protectionState,
    this.pauseDurationMs = 0,
    required this.dnsAddresses,
    required this.dnsPort,
    required this.httpPort,
    this.startTimeMs,
  });

  static bool isValidStatusPayload(Map<String, dynamic>? json) {
    if (json == null) return false;

    int indicatorCount = 0;
    if (json.containsKey('protection_enabled') &&
        json['protection_enabled'] is bool) {
      indicatorCount++;
    }
    if (json.containsKey('dns_port') && json['dns_port'] is num) {
      indicatorCount++;
    }
    if (json.containsKey('dns_addresses') && json['dns_addresses'] is List) {
      indicatorCount++;
    }
    if (json.containsKey('running') && json['running'] is bool) {
      indicatorCount++;
    }
    if (json.containsKey('http_port') && json['http_port'] is num) {
      indicatorCount++;
    }
    if (json.containsKey('version') && json['version'] is String) {
      final v = json['version'] as String;
      if (v.isNotEmpty &&
          (v.startsWith('v') || RegExp(r'\d+\.\d+').hasMatch(v))) {
        indicatorCount++;
      }
    }

    return indicatorCount >= 2;
  }

  factory AdGuardStatus.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    int pauseDuration = 0;
    final rawDuration = json['protection_disabled_duration'];
    if (rawDuration != null && rawDuration is num) {
      final d = rawDuration.toInt();
      pauseDuration = d > 0 ? d : 0;
    } else if (json['protection_disabled_until'] != null) {
      final untilDate = AdGuardProtectionState.parseTimestamp(
        json['protection_disabled_until'],
      );
      if (untilDate != null) {
        final diff = untilDate.difference(now ?? DateTime.now()).inMilliseconds;
        pauseDuration = diff > 0 ? diff : 0;
      }
    }

    final addressesRaw = json['dns_addresses'];
    final addresses = <String>[];
    if (addressesRaw is List) {
      for (final a in addressesRaw) {
        if (a != null) addresses.add(a.toString());
      }
    }

    return AdGuardStatus(
      version: json['version']?.toString() ?? 'Unknown',
      running: json['running'] == true,
      protectionState: AdGuardProtectionState.resolve(json, now: now),
      pauseDurationMs: pauseDuration,
      dnsAddresses: List.unmodifiable(addresses),
      dnsPort: (json['dns_port'] as num?)?.toInt() ?? 53,
      httpPort: (json['http_port'] as num?)?.toInt() ?? 3000,
      startTimeMs: (json['start_time'] as num?)?.toInt(),
    );
  }
}

@immutable
class AdGuardTopItem {
  final String identifier;
  final int count;

  const AdGuardTopItem({required this.identifier, required this.count});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardTopItem &&
          runtimeType == other.runtimeType &&
          identifier == other.identifier &&
          count == other.count;

  @override
  int get hashCode => identifier.hashCode ^ count.hashCode;

  @override
  String toString() => '$identifier: $count';
}

enum AdGuardStatsPeriod {
  all,
  hours24,
  days7,
  days30;

  Duration? get duration {
    switch (this) {
      case AdGuardStatsPeriod.all:
        return null;
      case AdGuardStatsPeriod.hours24:
        return const Duration(hours: 24);
      case AdGuardStatsPeriod.days7:
        return const Duration(days: 7);
      case AdGuardStatsPeriod.days30:
        return const Duration(days: 30);
    }
  }
}

@immutable
class AdGuardStats {
  final int numDnsQueries;

  final int numBlockedFiltering;

  final int numReplacedSafebrowsing;

  final int numReplacedSafesearch;

  final int numReplacedParental;

  final double avgProcessingTime;

  final List<AdGuardTopItem> topQueriedDomains;

  final List<AdGuardTopItem> topBlockedDomains;

  final List<AdGuardTopItem> topClients;

  final List<int> dnsQueriesTrend;

  final List<int> blockedFilteringTrend;

  final String timeUnits;

  final double blockRatePercentage;

  const AdGuardStats({
    required this.numDnsQueries,
    required this.numBlockedFiltering,
    required this.numReplacedSafebrowsing,
    required this.numReplacedSafesearch,
    required this.numReplacedParental,
    required this.avgProcessingTime,
    required this.topQueriedDomains,
    required this.topBlockedDomains,
    required this.topClients,
    required this.dnsQueriesTrend,
    required this.blockedFilteringTrend,
    this.timeUnits = 'hours',
    required this.blockRatePercentage,
  });

  static double calculateBlockRate(int totalQueries, int blockedQueries) {
    if (totalQueries <= 0 || blockedQueries <= 0) return 0.0;
    if (blockedQueries >= totalQueries) return 100.0;
    final rate = (blockedQueries / totalQueries) * 100.0;
    return rate.clamp(0.0, 100.0);
  }

  static List<AdGuardTopItem> parseTopList(dynamic rawList) {
    if (rawList is! List) return const [];
    final items = <AdGuardTopItem>[];

    for (final entry in rawList) {
      if (entry is Map) {
        String? key;
        int count = 0;

        if (entry.containsKey('domain')) {
          key = entry['domain']?.toString();
        } else if (entry.containsKey('host')) {
          key = entry['host']?.toString();
        } else if (entry.containsKey('ip')) {
          key = entry['ip']?.toString();
        } else if (entry.containsKey('IP')) {
          key = entry['IP']?.toString();
        } else if (entry.containsKey('name')) {
          key = entry['name']?.toString();
        }

        if (entry.containsKey('count') && entry['count'] is num) {
          count = (entry['count'] as num).toInt();
        }

        if (key == null || key.isEmpty) {
          if (entry.isNotEmpty) {
            final firstKey = entry.keys.first.toString();
            final firstVal = entry[firstKey];
            if (firstVal is num) {
              key = firstKey;
              count = firstVal.toInt();
            }
          }
        }

        if (key != null && key.isNotEmpty) {
          items.add(AdGuardTopItem(identifier: key, count: count));
        }
      }
    }

    return List.unmodifiable(items);
  }

  factory AdGuardStats.fromJson(Map<String, dynamic> json) {
    final totalQueries = (json['num_dns_queries'] as num?)?.toInt() ?? 0;
    final blocked = (json['num_blocked_filtering'] as num?)?.toInt() ?? 0;
    final safeBrowsing =
        (json['num_replaced_safebrowsing'] as num?)?.toInt() ?? 0;
    final safeSearch = (json['num_replaced_safesearch'] as num?)?.toInt() ?? 0;
    final parental = (json['num_replaced_parental'] as num?)?.toInt() ?? 0;
    final latency = (json['avg_processing_time'] as num?)?.toDouble() ?? 0.0;

    List<int> parseTrend(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<num>().map((n) => n.toInt()).toList();
    }

    return AdGuardStats(
      numDnsQueries: totalQueries,
      numBlockedFiltering: blocked,
      numReplacedSafebrowsing: safeBrowsing,
      numReplacedSafesearch: safeSearch,
      numReplacedParental: parental,
      avgProcessingTime: latency,
      topQueriedDomains: parseTopList(json['top_queried_domains']),
      topBlockedDomains: parseTopList(json['top_blocked_domains']),
      topClients: parseTopList(json['top_clients']),
      dnsQueriesTrend: List.unmodifiable(parseTrend(json['dns_queries'])),
      blockedFilteringTrend: List.unmodifiable(
        parseTrend(json['blocked_filtering']),
      ),
      timeUnits: json['time_units']?.toString() ?? 'hours',
      blockRatePercentage: calculateBlockRate(totalQueries, blocked),
    );
  }
}

@immutable
class AdGuardFilterList {
  final int id;
  final String name;
  final String url;
  final int rulesCount;
  final bool enabled;
  final String? lastUpdated;
  final bool whitelist;

  const AdGuardFilterList({
    required this.id,
    required this.name,
    this.url = '',
    required this.rulesCount,
    required this.enabled,
    this.lastUpdated,
    this.whitelist = false,
  });

  factory AdGuardFilterList.fromJson(
    Map<String, dynamic> json, {
    bool whitelist = false,
  }) {
    return AdGuardFilterList(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString() ?? 'Unnamed Filter',
      url: json['url']?.toString() ?? '',
      rulesCount: (json['rules_count'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] == true,
      lastUpdated: json['last_updated']?.toString(),
      whitelist: (json['whitelist'] as bool?) ?? whitelist,
    );
  }

  AdGuardFilterList copyWith({
    int? id,
    String? name,
    String? url,
    int? rulesCount,
    bool? enabled,
    String? lastUpdated,
    bool? whitelist,
  }) {
    return AdGuardFilterList(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      rulesCount: rulesCount ?? this.rulesCount,
      enabled: enabled ?? this.enabled,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      whitelist: whitelist ?? this.whitelist,
    );
  }
}

@immutable
class AdGuardFilteringStatus {
  final bool enabled;
  final int interval;
  final List<AdGuardFilterList> filterLists;
  final List<AdGuardFilterList> whitelistFilters;
  final List<String> userRules;
  final int totalRulesCount;

  const AdGuardFilteringStatus({
    required this.enabled,
    this.interval = 24,
    required this.filterLists,
    this.whitelistFilters = const [],
    required this.userRules,
    required this.totalRulesCount,
  });

  factory AdGuardFilteringStatus.fromJson(Map<String, dynamic> json) {
    final filtersRaw = json['filters'];
    final filters = <AdGuardFilterList>[];
    int calculatedTotalRules = 0;

    if (filtersRaw is List) {
      for (final f in filtersRaw) {
        if (f is Map<String, dynamic>) {
          final filter = AdGuardFilterList.fromJson(f, whitelist: false);
          filters.add(filter);
          if (filter.enabled) {
            calculatedTotalRules += filter.rulesCount;
          }
        }
      }
    }

    final whitelistRaw = json['whitelist_filters'];
    final whitelists = <AdGuardFilterList>[];
    if (whitelistRaw is List) {
      for (final f in whitelistRaw) {
        if (f is Map<String, dynamic>) {
          final filter = AdGuardFilterList.fromJson(f, whitelist: true);
          whitelists.add(filter);
          if (filter.enabled) {
            calculatedTotalRules += filter.rulesCount;
          }
        }
      }
    }

    final userRulesRaw = json['user_rules'];
    final rules = <String>[];
    if (userRulesRaw is List) {
      for (final r in userRulesRaw) {
        if (r != null && r.toString().isNotEmpty) {
          rules.add(r.toString());
        }
      }
    }
    calculatedTotalRules += rules.length;

    return AdGuardFilteringStatus(
      enabled: json['enabled'] == true,
      interval: (json['interval'] as num?)?.toInt() ?? 24,
      filterLists: List.unmodifiable(filters),
      whitelistFilters: List.unmodifiable(whitelists),
      userRules: List.unmodifiable(rules),
      totalRulesCount: calculatedTotalRules,
    );
  }

  AdGuardFilteringStatus copyWith({
    bool? enabled,
    int? interval,
    List<AdGuardFilterList>? filterLists,
    List<AdGuardFilterList>? whitelistFilters,
    List<String>? userRules,
    int? totalRulesCount,
  }) {
    return AdGuardFilteringStatus(
      enabled: enabled ?? this.enabled,
      interval: interval ?? this.interval,
      filterLists: filterLists ?? this.filterLists,
      whitelistFilters: whitelistFilters ?? this.whitelistFilters,
      userRules: userRules ?? this.userRules,
      totalRulesCount: totalRulesCount ?? this.totalRulesCount,
    );
  }
}

@immutable
class AdGuardProcessTelemetry {
  final String pid;
  final double cpuPercent;
  final int vszKb;
  final double vszMb;
  final double memPercent;
  final double? estimatedRamMb;

  const AdGuardProcessTelemetry({
    required this.pid,
    required this.cpuPercent,
    required this.vszKb,
    required this.vszMb,
    required this.memPercent,
    this.estimatedRamMb,
  });

  factory AdGuardProcessTelemetry.fromLuciProcess(
    Map<String, dynamic> json, {
    int? totalSystemRamBytes,
  }) {
    final pid = json['PID']?.toString() ?? '';

    double parsePercent(dynamic val) {
      if (val == null) return 0.0;
      final str = val.toString().replaceAll('%', '').trim();
      return double.tryParse(str) ?? 0.0;
    }

    final cpu = parsePercent(json['%CPU']);
    final mem = parsePercent(json['%MEM']);
    final vszRaw = json['VSZ'];
    final vszKb = vszRaw is num
        ? vszRaw.toInt()
        : (int.tryParse(vszRaw?.toString() ?? '') ?? 0);
    final vszMb = vszKb / 1024.0;

    double? estRamMb;
    if (totalSystemRamBytes != null && totalSystemRamBytes > 0 && mem > 0) {
      final totalMb = totalSystemRamBytes / (1024.0 * 1024.0);
      estRamMb = (mem / 100.0) * totalMb;
    }

    return AdGuardProcessTelemetry(
      pid: pid,
      cpuPercent: cpu,
      vszKb: vszKb,
      vszMb: vszMb,
      memPercent: mem,
      estimatedRamMb: estRamMb,
    );
  }
}

enum AdGuardTopologyMode {
  adguardPrimary,

  dnsmasqForwarder,

  firewallRedirect,

  standalone,

  stopped,

  unknown,
}

enum AdGuardDnsRoutingStatus {
  apiReachableOnly,

  serviceRunningOnly,

  routerForwardingUnverified,

  routerForwardingVerified,

  clientUsageVerified,

  externalStandalone,

  misconfiguredOrUnavailable,

  unknown,
}

enum Ipv6DnsStatus {
  noBypassDetected,

  externalAdvertisementBypass,

  unsupportedIpv6Listener,

  unableToVerify,
}

@immutable
class AdGuardDnsTopology {
  final AdGuardTopologyMode mode;
  final AdGuardDnsRoutingStatus routingStatus;
  final int adguardDnsPort;
  final int dnsmasqPort;
  final List<String> forwarders;
  final bool hasFirewallRedirect;
  final bool isIpv6Supported;
  final Ipv6DnsStatus ipv6Status;
  final String? ipv6Evidence;
  final String statusEvidence;
  final String description;
  final bool isClientUsageVerified;
  final int clientQueriesObserved;
  final String? misconfigurationReason;

  const AdGuardDnsTopology({
    required this.mode,
    this.routingStatus = AdGuardDnsRoutingStatus.unknown,
    required this.adguardDnsPort,
    required this.dnsmasqPort,
    required this.forwarders,
    required this.hasFirewallRedirect,
    required this.isIpv6Supported,
    this.ipv6Status = Ipv6DnsStatus.unableToVerify,
    this.ipv6Evidence,
    this.statusEvidence = '',
    required this.description,
    this.isClientUsageVerified = false,
    this.clientQueriesObserved = 0,
    this.misconfigurationReason,
  });

  static AdGuardDnsTopology infer({
    required int? adguardDnsPort,
    required int? dnsmasqPort,
    required List<String> dnsmasqServers,
    required bool hasDnatRedirect,
    required List<String> adguardDnsAddresses,
    required bool isDnsRunning,
    bool isApiReachable = true,
    AdGuardInstanceType instanceType = AdGuardInstanceType.localRouter,
    String? targetHost,
    List<AdGuardTopItem> topClients = const [],
    int totalQueries = 0,
    List<String> odhcpdIpv6Dns = const [],
    bool? raDnsEnabled,
    bool isIndeterminateIpv6 = false,
    List<String> adguardUpstreams = const [],
    String? routerIp,
    bool loopDetected = false,
    String? loopReason,
    bool portConflict = false,
    String? portConflictReason,
  }) {
    final aghPort = adguardDnsPort ?? 53;
    final dmPort = dnsmasqPort ?? 53;

    final hasIpv6 = adguardDnsAddresses.any(
      (addr) => addr.contains(':') || addr == '::' || addr.startsWith('['),
    );

    final hasLocalForwarder = dnsmasqServers.any((s) {
      final trimmed = s.trim();
      return trimmed.contains('127.0.0.1#$aghPort') ||
          trimmed.contains('::1#$aghPort') ||
          trimmed.contains('#$aghPort') ||
          (aghPort == 53 && (trimmed == '127.0.0.1' || trimmed == '::1'));
    });

    final hasExternalForwarder =
        (instanceType.isExternal &&
            targetHost != null &&
            targetHost.trim().isNotEmpty)
        ? dnsmasqServers.any((s) {
            final trimmed = s.trim();
            final hostNorm = targetHost.trim();
            return trimmed == hostNorm ||
                trimmed == '$hostNorm#$aghPort' ||
                trimmed.startsWith('$hostNorm#') ||
                trimmed.startsWith('$hostNorm:');
          })
        : false;

    final hasForwarder = instanceType.isExternal
        ? hasExternalForwarder
        : hasLocalForwarder;

    AdGuardTopologyMode inferredMode;
    String modeDescription;

    if (!isApiReachable) {
      if (hasForwarder) {
        inferredMode = AdGuardTopologyMode.dnsmasqForwarder;
        modeDescription = instanceType.isExternal
            ? 'dnsmasq is configured to forward queries to external AdGuard ($targetHost), but AdGuard API is unreachable.'
            : 'dnsmasq is configured to forward queries to AdGuard on port $aghPort, but AdGuard API is unreachable.';
      } else {
        inferredMode = AdGuardTopologyMode.unknown;
        modeDescription =
            'AdGuard API is unreachable; DNS routing topology cannot be verified.';
      }
    } else if (!isDnsRunning) {
      inferredMode = AdGuardTopologyMode.stopped;
      modeDescription = 'AdGuard Home DNS engine is stopped.';
    } else if (aghPort == 53 && dmPort != 53 && !instanceType.isExternal) {
      inferredMode = AdGuardTopologyMode.adguardPrimary;
      modeDescription =
          'AdGuard Home is primary DNS on port 53 (dnsmasq relocated to port $dmPort).';
    } else if (dmPort == 53 && hasForwarder) {
      inferredMode = AdGuardTopologyMode.dnsmasqForwarder;
      modeDescription = instanceType.isExternal
          ? 'dnsmasq handles port 53 and forwards queries to external AdGuard Home ($targetHost) on port $aghPort.'
          : 'dnsmasq handles port 53 and forwards queries to AdGuard Home on port $aghPort.';
    } else if (hasDnatRedirect && !instanceType.isExternal) {
      inferredMode = AdGuardTopologyMode.firewallRedirect;
      modeDescription =
          'Firewall DNAT intercepts port 53 and redirects to AdGuard Home on port $aghPort.';
    } else if (instanceType.isExternal && !hasForwarder) {
      inferredMode = AdGuardTopologyMode.standalone;
      modeDescription =
          'External standalone AdGuard Home instance ($targetHost): router does not forward queries to it.';
    } else if (aghPort != 53 &&
        dmPort == 53 &&
        !hasForwarder &&
        !hasDnatRedirect) {
      inferredMode = AdGuardTopologyMode.standalone;
      modeDescription =
          'AdGuard Home running on port $aghPort without detected router DNS routing.';
    } else {
      inferredMode = AdGuardTopologyMode.unknown;
      modeDescription = 'DNS routing topology could not be inferred.';
    }

    AdGuardDnsRoutingStatus resolvedStatus;
    String evidence;
    bool isClientVerified = false;
    int observedClientQueries = 0;
    String? misconfigReason;

    if (portConflict) {
      resolvedStatus = AdGuardDnsRoutingStatus.misconfiguredOrUnavailable;
      misconfigReason =
          portConflictReason ??
          'Port conflict detected: both AdGuard and dnsmasq are configured on port $aghPort.';
      evidence = misconfigReason;
    } else if (loopDetected) {
      resolvedStatus = AdGuardDnsRoutingStatus.misconfiguredOrUnavailable;
      misconfigReason =
          loopReason ??
          'Forwarding loop detected: AdGuard upstream forwards queries back to router resolver.';
      evidence = misconfigReason;
    } else if (!isApiReachable) {
      resolvedStatus = AdGuardDnsRoutingStatus.unknown;
      evidence = hasForwarder
          ? 'Router is configured to forward DNS to AdGuard in UCI, but AdGuard API is unreachable; live query flow cannot be verified.'
          : 'AdGuard API is unreachable; routing status cannot be verified.';
    } else if (hasForwarder && !isDnsRunning) {
      resolvedStatus = AdGuardDnsRoutingStatus.misconfiguredOrUnavailable;
      misconfigReason =
          'Router is configured to forward DNS to AdGuard, but the AdGuard DNS engine is stopped.';
      evidence = misconfigReason;
    } else if (!isDnsRunning) {
      resolvedStatus = AdGuardDnsRoutingStatus.apiReachableOnly;
      evidence = 'AdGuard answered, but the DNS engine is inactive.';
    } else if (hasForwarder ||
        inferredMode == AdGuardTopologyMode.adguardPrimary ||
        inferredMode == AdGuardTopologyMode.firewallRedirect) {
      final routerAddresses = <String>{
        '127.0.0.1',
        'localhost',
        '::1',
        if (routerIp != null && routerIp.trim().isNotEmpty) routerIp.trim(),
      };

      int distinctClientCount = 0;
      int clientQueryCount = 0;
      int routerQueryCount = 0;

      for (final client in topClients) {
        final id = client.identifier.trim();
        if (routerAddresses.contains(id)) {
          routerQueryCount += client.count;
        } else {
          distinctClientCount++;
          clientQueryCount += client.count;
        }
      }

      if (distinctClientCount > 0 && clientQueryCount > 0) {
        resolvedStatus = AdGuardDnsRoutingStatus.clientUsageVerified;
        isClientVerified = true;
        observedClientQueries = clientQueryCount;
        evidence =
            'Verified: $clientQueryCount queries observed from $distinctClientCount client device(s) in AdGuard telemetry. Note: Encrypted DNS (DoH/DoT) or static client settings may still bypass filtering.';
      } else if (routerQueryCount > 0 || totalQueries > 0) {
        resolvedStatus = AdGuardDnsRoutingStatus.routerForwardingVerified;
        isClientVerified = false;
        observedClientQueries = 0;
        final count = routerQueryCount > 0 ? routerQueryCount : totalQueries;
        evidence =
            'Router forwards queries to AdGuard ($count queries observed originating from router/loopback). Individual client IPs are not distinguishable via dnsmasq.';
      } else {
        resolvedStatus = AdGuardDnsRoutingStatus.routerForwardingUnverified;
        isClientVerified = false;
        observedClientQueries = 0;
        evidence =
            'Router is configured to forward DNS to AdGuard in UCI, but no queries have been observed in AdGuard telemetry yet.';
      }
    } else {
      if (instanceType.isExternal) {
        resolvedStatus = AdGuardDnsRoutingStatus.externalStandalone;
        evidence =
            'External AdGuard instance is running, but router dnsmasq does not forward queries to ${targetHost ?? 'host'}:$aghPort.';
      } else {
        resolvedStatus = AdGuardDnsRoutingStatus.serviceRunningOnly;
        evidence =
            'AdGuard service is running on port $aghPort, but router dnsmasq is not configured to forward DNS queries to it.';
      }
    }

    Ipv6DnsStatus resolvedIpv6Status;
    String? resolvedIpv6Evidence;

    if (isIndeterminateIpv6) {
      resolvedIpv6Status = Ipv6DnsStatus.unableToVerify;
      resolvedIpv6Evidence =
          'Unable to verify: Router DHCP / odhcpd UCI configuration was inconclusive or unavailable.';
    } else if (odhcpdIpv6Dns.isNotEmpty) {
      final externalIpv6 = odhcpdIpv6Dns.where((addr) {
        final clean = addr.trim();
        return !adguardDnsAddresses.contains(clean) &&
            clean != '::1' &&
            clean != '::';
      }).toList();

      if (externalIpv6.isNotEmpty) {
        resolvedIpv6Status = Ipv6DnsStatus.externalAdvertisementBypass;
        resolvedIpv6Evidence =
            'Router DHCP advertises external IPv6 DNS (${externalIpv6.join(', ')}). Clients may query these directly, bypassing AdGuard.';
      } else {
        resolvedIpv6Status = Ipv6DnsStatus.noBypassDetected;
        resolvedIpv6Evidence =
            'Router advertises AdGuard IPv6 listener address (${odhcpdIpv6Dns.join(', ')}).';
      }
    } else if (raDnsEnabled == false) {
      resolvedIpv6Status = Ipv6DnsStatus.noBypassDetected;
      resolvedIpv6Evidence =
          'Router Advertisement RDNSS is explicitly disabled (ra_dns = 0).';
    } else {
      if (!hasIpv6) {
        resolvedIpv6Status = Ipv6DnsStatus.unsupportedIpv6Listener;
        resolvedIpv6Evidence =
            'Router odhcpd advertises IPv6 DNS via RDNSS, but AdGuard has no configured IPv6 listener.';
      } else {
        resolvedIpv6Status = Ipv6DnsStatus.unableToVerify;
        resolvedIpv6Evidence =
            'Unable to verify: Router uses default odhcpd RDNSS; dynamic upstream ISP delegation cannot be confirmed from static UCI alone.';
      }
    }

    return AdGuardDnsTopology(
      mode: inferredMode,
      routingStatus: resolvedStatus,
      adguardDnsPort: aghPort,
      dnsmasqPort: dmPort,
      forwarders: List.unmodifiable(dnsmasqServers),
      hasFirewallRedirect: hasDnatRedirect,
      isIpv6Supported: hasIpv6,
      ipv6Status: resolvedIpv6Status,
      ipv6Evidence: resolvedIpv6Evidence,
      statusEvidence: evidence,
      description: modeDescription,
      isClientUsageVerified: isClientVerified,
      clientQueriesObserved: observedClientQueries,
      misconfigurationReason: misconfigReason,
    );
  }
}

@immutable
class AdGuardDnsPreflightResult {
  final bool canProceed;
  final String targetHost;
  final int targetPort;
  final String targetForwarder;
  final List<String> currentServers;
  final bool isAlreadyConfigured;
  final bool isExternal;
  final bool isHostname;
  final bool loopDetected;
  final String? loopReason;
  final bool portConflict;
  final String? portConflictReason;
  final List<String> warnings;

  const AdGuardDnsPreflightResult({
    required this.canProceed,
    required this.targetHost,
    required this.targetPort,
    required this.targetForwarder,
    required this.currentServers,
    this.isAlreadyConfigured = false,
    this.isExternal = false,
    this.isHostname = false,
    this.loopDetected = false,
    this.loopReason,
    this.portConflict = false,
    this.portConflictReason,
    this.warnings = const [],
  });
}

@immutable
class AdGuardDnsRevertPreflightResult {
  final bool canProceed;
  final String? targetRule;
  final String? targetForwarder;
  final List<String> currentServers;
  final List<String> remainingServers;
  final bool isMissing;
  final bool isAmbiguous;
  final String? failureReason;
  final List<String> warnings;

  const AdGuardDnsRevertPreflightResult({
    required this.canProceed,
    this.targetRule,
    String? targetForwarder,
    this.currentServers = const [],
    this.remainingServers = const [],
    this.isMissing = false,
    this.isAmbiguous = false,
    this.failureReason,
    this.warnings = const [],
  }) : targetForwarder = targetForwarder ?? targetRule;
}

enum AdGuardDnsConfigStatus { success, failed, rolledBack, ambiguous }

@immutable
class AdGuardDnsConfigResult {
  final AdGuardDnsConfigStatus status;
  final String message;
  final List<String> appliedServers;
  final bool wasRolledBack;

  const AdGuardDnsConfigResult({
    required this.status,
    required this.message,
    this.appliedServers = const [],
    this.wasRolledBack = false,
  });

  bool get isSuccess => status == AdGuardDnsConfigStatus.success;
  bool get isRolledBack => status == AdGuardDnsConfigStatus.rolledBack;
  bool get isAmbiguous => status == AdGuardDnsConfigStatus.ambiguous;
}

@immutable
class AdGuardCapabilities {
  final bool isInstalled;

  final bool isServiceManageable;

  final bool isApiReachable;

  final bool isApiAuthenticated;

  final bool isDnsOperational;

  final String? serviceName;

  final AdGuardDnsTopology topology;

  final int discoveredHttpPort;

  final int discoveredDnsPort;

  final String? version;

  final String? lastError;

  final bool? isServiceEnabled;

  const AdGuardCapabilities({
    required this.isInstalled,
    required this.isServiceManageable,
    required this.isApiReachable,
    required this.isApiAuthenticated,
    required this.isDnsOperational,
    this.serviceName,
    required this.topology,
    this.discoveredHttpPort = 3000,
    this.discoveredDnsPort = 53,
    this.version,
    this.lastError,
    this.isServiceEnabled,
  });

  static AdGuardCapabilities evaluate({
    required bool hasServiceInRcList,
    required bool hasInitScript,
    required String? resolvedServiceName,
    required bool hasRunningProcess,
    required bool isApiReachable,
    required bool isApiAuthenticated,
    required AdGuardStatus? status,
    required AdGuardDnsTopology topology,
    required int configuredHttpPort,
    String? error,
    bool? isServiceEnabled,
  }) {
    final isInstalled =
        (status != null) ||
        hasServiceInRcList ||
        hasInitScript ||
        hasRunningProcess;

    final isManageable = hasInitScript || hasServiceInRcList;

    final isDnsOp = status?.running ?? false;
    final httpPort = status?.httpPort ?? configuredHttpPort;
    final dnsPort = status?.dnsPort ?? 53;

    return AdGuardCapabilities(
      isInstalled: isInstalled,
      isServiceManageable: isManageable,
      isApiReachable: isApiReachable,
      isApiAuthenticated: isApiAuthenticated,
      isDnsOperational: isDnsOp,
      serviceName: resolvedServiceName,
      topology: topology,
      discoveredHttpPort: httpPort,
      discoveredDnsPort: dnsPort,
      version: status?.version,
      lastError: error,
      isServiceEnabled: isServiceEnabled,
    );
  }

  AdGuardCapabilities copyWith({
    bool? isInstalled,
    bool? isServiceManageable,
    bool? isApiReachable,
    bool? isApiAuthenticated,
    bool? isDnsOperational,
    String? serviceName,
    AdGuardDnsTopology? topology,
    int? discoveredHttpPort,
    int? discoveredDnsPort,
    String? version,
    String? lastError,
    bool? isServiceEnabled,
  }) {
    return AdGuardCapabilities(
      isInstalled: isInstalled ?? this.isInstalled,
      isServiceManageable: isServiceManageable ?? this.isServiceManageable,
      isApiReachable: isApiReachable ?? this.isApiReachable,
      isApiAuthenticated: isApiAuthenticated ?? this.isApiAuthenticated,
      isDnsOperational: isDnsOperational ?? this.isDnsOperational,
      serviceName: serviceName ?? this.serviceName,
      topology: topology ?? this.topology,
      discoveredHttpPort: discoveredHttpPort ?? this.discoveredHttpPort,
      discoveredDnsPort: discoveredDnsPort ?? this.discoveredDnsPort,
      version: version ?? this.version,
      lastError: lastError ?? this.lastError,
      isServiceEnabled: isServiceEnabled ?? this.isServiceEnabled,
    );
  }
}

@immutable
class AdGuardClient {
  final String name;
  final List<String> ids;
  final bool useGlobalSettings;
  final bool filteringEnabled;
  final bool parentalEnabled;
  final bool safebrowsingEnabled;
  final bool safesearchEnabled;
  final bool useGlobalBlockedServices;
  final List<String> blockedServices;
  final List<String> upstreams;
  final List<String> rules;
  final List<String> tags;

  const AdGuardClient({
    required this.name,
    required this.ids,
    this.useGlobalSettings = true,
    this.filteringEnabled = true,
    this.parentalEnabled = false,
    this.safebrowsingEnabled = false,
    this.safesearchEnabled = false,
    this.useGlobalBlockedServices = true,
    this.blockedServices = const [],
    this.upstreams = const [],
    this.rules = const [],
    this.tags = const [],
  });

  factory AdGuardClient.fromJson(Map<String, dynamic> json) {
    return AdGuardClient(
      name: json['name']?.toString() ?? '',
      ids:
          (json['ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      useGlobalSettings: json['use_global_settings'] != false,
      filteringEnabled: json['filtering_enabled'] != false,
      parentalEnabled: json['parental_enabled'] == true,
      safebrowsingEnabled: json['safebrowsing_enabled'] == true,
      safesearchEnabled: json['safesearch_enabled'] == true,
      useGlobalBlockedServices: json['use_global_blocked_services'] != false,
      blockedServices:
          (json['blocked_services'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      upstreams:
          (json['upstreams'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      rules:
          (json['rules'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      tags:
          (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'ids': ids,
    'use_global_settings': useGlobalSettings,
    'filtering_enabled': filteringEnabled,
    'parental_enabled': parentalEnabled,
    'safebrowsing_enabled': safebrowsingEnabled,
    'safesearch_enabled': safesearchEnabled,
    'use_global_blocked_services': useGlobalBlockedServices,
    'blocked_services': blockedServices,
    'upstreams': upstreams,
    'rules': rules,
    'tags': tags,
  };

  AdGuardClient copyWith({
    String? name,
    List<String>? ids,
    bool? useGlobalSettings,
    bool? filteringEnabled,
    bool? parentalEnabled,
    bool? safebrowsingEnabled,
    bool? safesearchEnabled,
    bool? useGlobalBlockedServices,
    List<String>? blockedServices,
    List<String>? upstreams,
    List<String>? rules,
    List<String>? tags,
  }) {
    return AdGuardClient(
      name: name ?? this.name,
      ids: ids ?? this.ids,
      useGlobalSettings: useGlobalSettings ?? this.useGlobalSettings,
      filteringEnabled: filteringEnabled ?? this.filteringEnabled,
      parentalEnabled: parentalEnabled ?? this.parentalEnabled,
      safebrowsingEnabled: safebrowsingEnabled ?? this.safebrowsingEnabled,
      safesearchEnabled: safesearchEnabled ?? this.safesearchEnabled,
      useGlobalBlockedServices:
          useGlobalBlockedServices ?? this.useGlobalBlockedServices,
      blockedServices: blockedServices ?? this.blockedServices,
      upstreams: upstreams ?? this.upstreams,
      rules: rules ?? this.rules,
      tags: tags ?? this.tags,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardClient &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          listEquals(ids, other.ids) &&
          listEquals(rules, other.rules);

  @override
  int get hashCode =>
      Object.hash(name, Object.hashAll(ids), Object.hashAll(rules));
}

enum AdGuardInstanceType {
  localRouter,

  externalHost;

  bool get isLocal => this == AdGuardInstanceType.localRouter;
  bool get isExternal => this == AdGuardInstanceType.externalHost;
}

@immutable
class AdGuardInstanceProfile {
  final String id;

  final String name;

  final AdGuardInstanceType type;

  final String host;

  final int port;

  final bool useHttps;

  final String? routerId;

  const AdGuardInstanceProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.host,
    this.port = 3000,
    this.useHttps = false,
    this.routerId,
  });

  factory AdGuardInstanceProfile.local({
    required String routerId,
    required String host,
    int port = 3000,
    bool useHttps = false,
    String? name,
  }) {
    return AdGuardInstanceProfile(
      id: 'local_$routerId',
      name: name ?? 'Router ($host)',
      type: AdGuardInstanceType.localRouter,
      host: host,
      port: port,
      useHttps: useHttps,
      routerId: routerId,
    );
  }

  factory AdGuardInstanceProfile.external({
    required String id,
    required String name,
    required String host,
    int port = 3000,
    bool useHttps = false,
  }) {
    return AdGuardInstanceProfile(
      id: id,
      name: name,
      type: AdGuardInstanceType.externalHost,
      host: host,
      port: port,
      useHttps: useHttps,
      routerId: null,
    );
  }

  factory AdGuardInstanceProfile.fromJson(Map<String, dynamic> json) {
    return AdGuardInstanceProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: json['type'] == 'externalHost'
          ? AdGuardInstanceType.externalHost
          : AdGuardInstanceType.localRouter,
      host: json['host']?.toString() ?? '',
      port: (json['port'] as num?)?.toInt() ?? 3000,
      useHttps: json['use_https'] == true,
      routerId: json['router_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'host': host,
    'port': port,
    'use_https': useHttps,
    if (routerId != null) 'router_id': routerId,
  };

  AdGuardInstanceProfile copyWith({
    String? id,
    String? name,
    AdGuardInstanceType? type,
    String? host,
    int? port,
    bool? useHttps,
    String? routerId,
  }) {
    return AdGuardInstanceProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      routerId: routerId ?? this.routerId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardInstanceProfile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          type == other.type &&
          host == other.host &&
          port == other.port &&
          useHttps == other.useHttps &&
          routerId == other.routerId;

  @override
  int get hashCode =>
      Object.hash(id, name, type, host, port, useHttps, routerId);
}
