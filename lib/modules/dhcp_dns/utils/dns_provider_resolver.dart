// SPDX-License-Identifier: GPL-3.0-or-later

class DnsResolutionResult {
  final String providerName;

  final String displayLabel;

  final String protocol;

  final String? endpoint;

  final String? bootstrapDns;

  final String? socketAddress;

  final String summary;

  const DnsResolutionResult({
    required this.providerName,
    required this.displayLabel,
    required this.protocol,
    this.endpoint,
    this.bootstrapDns,
    this.socketAddress,
    required this.summary,
  });

  @override
  String toString() => summary;
}

class DnsProviderResolver {
  const DnsProviderResolver._();

  static (String providerName, String protocol) identifyProvider(
    String target,
  ) {
    final lower = target.toLowerCase().trim();

    if (lower.contains('quad9') ||
        lower.contains('9.9.9.') ||
        lower.contains('149.112.112.') ||
        lower.contains('2620:fe:')) {
      final proto = lower.startsWith('https')
          ? 'DoH'
          : (lower.startsWith('tls') ? 'DoT' : 'DNS');
      return ('Quad9', proto);
    }

    if (lower.contains('cloudflare') ||
        lower.contains('one.one.one.one') ||
        lower.contains('1.1.1.1') ||
        lower.contains('1.0.0.1') ||
        lower.contains('1.1.1.2') ||
        lower.contains('1.0.0.2') ||
        lower.contains('1.1.1.3') ||
        lower.contains('1.0.0.3') ||
        lower.contains('2606:4700:')) {
      final proto = lower.startsWith('https')
          ? 'DoH'
          : (lower.startsWith('tls') ? 'DoT' : 'DNS');
      return ('Cloudflare', proto);
    }

    if (lower.contains('dns.google') ||
        lower.contains('8.8.8.8') ||
        lower.contains('8.8.4.4') ||
        lower.contains('2001:4860:4860:')) {
      final proto = lower.startsWith('https')
          ? 'DoH'
          : (lower.startsWith('tls') ? 'DoT' : 'DNS');
      return ('Google DNS', proto);
    }

    if (lower.contains('adguard') ||
        lower.contains('94.140.14.') ||
        lower.contains('94.140.15.') ||
        lower.contains('2a10:50c0:')) {
      final proto = lower.startsWith('https')
          ? 'DoH'
          : (lower.startsWith('tls') ? 'DoT' : 'DNS');
      return ('AdGuard DNS', proto);
    }

    if (lower.contains('opendns') ||
        lower.contains('208.67.222.') ||
        lower.contains('208.67.220.')) {
      final proto = lower.startsWith('https')
          ? 'DoH'
          : (lower.startsWith('tls') ? 'DoT' : 'DNS');
      return ('OpenDNS', proto);
    }

    if (lower.contains('nextdns')) {
      return ('NextDNS', 'DoH');
    }

    if (lower.contains('cleanbrowsing') ||
        lower.contains('185.228.168.') ||
        lower.contains('185.228.169.')) {
      final proto = lower.startsWith('https') ? 'DoH' : 'DNS';
      return ('CleanBrowsing', proto);
    }

    if (lower.contains('controld') ||
        lower.contains('76.76.2.') ||
        lower.contains('76.76.10.')) {
      final proto = lower.startsWith('https') ? 'DoH' : 'DNS';
      return ('Control D', proto);
    }

    if (lower.contains('mullvad') || lower.contains('194.242.2.')) {
      final proto = lower.startsWith('https') ? 'DoH' : 'DNS';
      return ('Mullvad DNS', proto);
    }

    if (lower.startsWith('https://')) {
      try {
        final uri = Uri.parse(target.trim());
        final host = uri.host;
        if (host.isNotEmpty) {
          return (host, 'DoH');
        }
      } catch (_) {}
      return ('Custom DoH', 'DoH');
    }

    if (lower.startsWith('tls://')) {
      try {
        final uri = Uri.parse(target.trim());
        final host = uri.host;
        if (host.isNotEmpty) {
          return (host, 'DoT');
        }
      } catch (_) {}
      return ('Custom DoT', 'DoT');
    }

    return (target, 'DNS');
  }

  static bool isLoopback(String server) {
    final lower = server.toLowerCase().trim();
    return lower.startsWith('127.') ||
        lower.startsWith('localhost') ||
        lower.startsWith('::1') ||
        lower.startsWith('0.0.0.0');
  }

  static String? extractPort(String server) {
    final s = server.trim();
    if (s.contains('#')) {
      return s.split('#').last.trim();
    }
    if (s.contains(':')) {
      return s.split(':').last.trim();
    }
    return null;
  }

  static DnsResolutionResult? resolve({
    required List<String> upstreamServers,
    Map<String, dynamic>? httpsDnsProxyData,
    Map<String, dynamic>? stubbyData,
    Map<String, dynamic>? smartdnsData,
    Map<String, dynamic>? nextdnsData,
    Map<String, dynamic>? cloudflaredData,
    Map<String, dynamic>? rawDnsmasq,
    Map<String, dynamic>? interfaceDump,
  }) {
    for (final server in upstreamServers) {
      final trimmed = server.trim();
      if (isLoopback(trimmed)) {
        final port = extractPort(trimmed) ?? '5053';

        if (httpsDnsProxyData != null) {
          final res = _resolveHttpsDnsProxy(httpsDnsProxyData, port, trimmed);
          if (res != null) return res;
        }

        if (stubbyData != null) {
          final res = _resolveStubby(stubbyData, port, trimmed);
          if (res != null) return res;
        }

        if (smartdnsData != null) {
          final res = _resolveSmartdns(smartdnsData, port, trimmed);
          if (res != null) return res;
        }

        if (nextdnsData != null && _isNextdnsActive(nextdnsData)) {
          return DnsResolutionResult(
            providerName: 'NextDNS',
            displayLabel: 'NextDNS',
            protocol: 'DoH/DoT',
            socketAddress: trimmed,
            summary: 'NextDNS via $trimmed',
          );
        }

        if (cloudflaredData != null && _isCloudflaredActive(cloudflaredData)) {
          return DnsResolutionResult(
            providerName: 'Cloudflare',
            displayLabel: 'Cloudflare (DoH)',
            protocol: 'DoH',
            socketAddress: trimmed,
            summary: 'Cloudflare (DoH) via $trimmed',
          );
        }

        if (rawDnsmasq != null && rawDnsmasq['doh_backup_server'] != null) {
          final backup = rawDnsmasq['doh_backup_server'];
          final backupStr = backup is List
              ? backup.join(' ')
              : backup.toString();
          final (prov, _) = identifyProvider(backupStr);
          if (prov != backupStr) {
            return DnsResolutionResult(
              providerName: prov,
              displayLabel: '$prov (DoH)',
              protocol: 'DoH',
              socketAddress: trimmed,
              summary: '$prov (DoH) via $trimmed',
            );
          }
        }
      }
    }

    for (final server in upstreamServers) {
      final trimmed = server.trim();
      if (!isLoopback(trimmed) &&
          trimmed.isNotEmpty &&
          trimmed != 'ISP Default') {
        final (provider, protocol) = identifyProvider(trimmed);
        if (provider != trimmed) {
          final display = protocol == 'DNS'
              ? '$provider ($trimmed)'
              : '$provider ($protocol)';
          return DnsResolutionResult(
            providerName: provider,
            displayLabel: display,
            protocol: protocol,
            socketAddress: trimmed,
            summary: '$provider ($trimmed)',
          );
        }
      }
    }

    if (interfaceDump != null && interfaceDump['interface'] is List) {
      final ifaces = interfaceDump['interface'] as List;
      for (final iface in ifaces) {
        if (iface is Map) {
          final ifName = iface['interface']?.toString().toLowerCase() ?? '';
          if (ifName.contains('wan')) {
            final dnsServers = iface['dns-server'];
            if (dnsServers is List && dnsServers.isNotEmpty) {
              final firstDns = dnsServers.first.toString().trim();
              if (firstDns.isNotEmpty) {
                final (provider, _) = identifyProvider(firstDns);
                if (provider != firstDns) {
                  return DnsResolutionResult(
                    providerName: provider,
                    displayLabel: '$provider (WAN)',
                    protocol: 'DNS',
                    socketAddress: firstDns,
                    summary: '$provider via WAN ($firstDns)',
                  );
                }
              }
            }
          }
        }
      }
    }

    return null;
  }

  static DnsResolutionResult? _resolveHttpsDnsProxy(
    Map<String, dynamic> data,
    String port,
    String socketAddress,
  ) {
    final values = (data['values'] is Map) ? data['values'] as Map : data;

    Map<String, dynamic>? matchingInstance;
    for (final entry in values.entries) {
      if (entry.value is Map) {
        final section = Map<String, dynamic>.from(entry.value as Map);
        final listenPort = section['listen_port']?.toString();
        if (listenPort == port) {
          matchingInstance = section;
          break;
        }
        if (section['resolver_url'] != null && matchingInstance == null) {
          matchingInstance = section;
        }
      }
    }

    if (matchingInstance != null) {
      final resolverUrl = matchingInstance['resolver_url']?.toString() ?? '';
      final bootstrapDns = matchingInstance['bootstrap_dns']?.toString();

      if (resolverUrl.isNotEmpty) {
        final (provider, _) = identifyProvider(resolverUrl);
        final display = '$provider (DoH)';
        return DnsResolutionResult(
          providerName: provider,
          displayLabel: display,
          protocol: 'DoH',
          endpoint: resolverUrl,
          bootstrapDns: bootstrapDns,
          socketAddress: socketAddress,
          summary: '$display via $socketAddress',
        );
      }
    }

    return null;
  }

  static DnsResolutionResult? _resolveStubby(
    Map<String, dynamic> data,
    String port,
    String socketAddress,
  ) {
    final values = (data['values'] is Map) ? data['values'] as Map : data;

    for (final entry in values.entries) {
      if (entry.value is Map) {
        final section = Map<String, dynamic>.from(entry.value as Map);
        final authName = section['tls_auth_name']?.toString() ?? '';
        final addrData = section['address_data']?.toString() ?? '';

        if (authName.isNotEmpty || addrData.isNotEmpty) {
          final target = authName.isNotEmpty ? authName : addrData;
          final (provider, _) = identifyProvider(target);
          final display = '$provider (DoT)';
          return DnsResolutionResult(
            providerName: provider,
            displayLabel: display,
            protocol: 'DoT',
            endpoint: authName.isNotEmpty ? authName : null,
            bootstrapDns: addrData.isNotEmpty ? addrData : null,
            socketAddress: socketAddress,
            summary: '$display via $socketAddress',
          );
        }
      }
    }

    return null;
  }

  static DnsResolutionResult? _resolveSmartdns(
    Map<String, dynamic> data,
    String port,
    String socketAddress,
  ) {
    final values = (data['values'] is Map) ? data['values'] as Map : data;

    for (final entry in values.entries) {
      if (entry.value is Map) {
        final section = Map<String, dynamic>.from(entry.value as Map);
        final servers = section['server'] ?? section['server-https'];
        if (servers != null) {
          final sStr = servers is List ? servers.join(' ') : servers.toString();
          final (provider, proto) = identifyProvider(sStr);
          if (provider != sStr) {
            final display = '$provider ($proto)';
            return DnsResolutionResult(
              providerName: provider,
              displayLabel: display,
              protocol: proto,
              socketAddress: socketAddress,
              summary: '$display via $socketAddress',
            );
          }
        }
      }
    }

    return null;
  }

  static bool _isNextdnsActive(Map<String, dynamic> data) {
    final values = (data['values'] is Map) ? data['values'] as Map : data;
    for (final entry in values.entries) {
      if (entry.value is Map) {
        final s = entry.value as Map;
        if (s['enabled'] == '1' || s['enabled'] == true) return true;
        if (s['profile'] != null && s['profile'].toString().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  static bool _isCloudflaredActive(Map<String, dynamic> data) {
    final values = (data['values'] is Map) ? data['values'] as Map : data;
    for (final entry in values.entries) {
      if (entry.value is Map) {
        final s = entry.value as Map;
        if (s['enabled'] == '1' || s['enabled'] == true) return true;
        if (s['tunnel_id'] != null && s['tunnel_id'].toString().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }
}
