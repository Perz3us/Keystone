// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math';

enum ClientCategoryFilter { all, wired, wireless, banned, dumbAp }

enum ConnectionType { wired, wireless, unknown }

enum NeighborReachability { reachable, stale, failed, unknown }

class Client {
  final String ipAddress;
  final String macAddress;
  final String hostname;
  final String? hostId;
  final int? leaseTime;
  final String? vendor;
  final String? dnsName;
  final String? clientId;
  final int? activeTime;
  final int? expiresAt;
  final ConnectionType connectionType;
  final List<String>? ipv6Addresses;
  final String? ssid;
  final String? wirelessIface;
  final bool isConnected;
  final NeighborReachability neighState;
  final String? staticLeaseName;
  final bool isStaticLease;
  final String? staticLeaseTime;
  final bool isDumbApClient;
  final String? apName;
  final int? rxBytes;
  final int? txBytes;
  final int? rxPackets;
  final int? txPackets;
  final num? rxRate;
  final num? txRate;
  final int? signalDbm;
  final int? noiseDbm;
  final int? throughput;
  final double? rxSpeed;
  final double? txSpeed;
  final int? connectedTime;

  Client({
    required this.ipAddress,
    required this.macAddress,
    required this.hostname,
    this.hostId,
    this.leaseTime,
    this.vendor,
    this.dnsName,
    this.clientId,
    this.activeTime,
    this.expiresAt,
    this.connectionType = ConnectionType.unknown,
    this.ipv6Addresses,
    this.ssid,
    this.wirelessIface,
    this.isConnected = true,
    this.neighState = NeighborReachability.unknown,
    this.staticLeaseName,
    this.isStaticLease = false,
    this.staticLeaseTime,
    this.isDumbApClient = false,
    this.apName,
    this.rxBytes,
    this.txBytes,
    this.rxPackets,
    this.txPackets,
    this.rxRate,
    this.txRate,
    this.signalDbm,
    this.noiseDbm,
    this.throughput,
    this.rxSpeed,
    this.txSpeed,
    this.connectedTime,
  });

  static ConnectionType _determineConnectionType(Map<String, dynamic> lease) {
    if (lease['signal'] != null ||
        lease['noise'] != null ||
        lease['ssid'] != null) {
      return ConnectionType.wireless;
    }

    final hostname = (lease['hostname'] ?? lease['name'] ?? '')
        .toString()
        .toLowerCase();
    final vendor = (lease['vendor'] ?? '').toString().toLowerCase();
    if (hostname.contains('iphone') ||
        hostname.contains('ipad') ||
        hostname.contains('galaxy') ||
        hostname.contains('android') ||
        hostname.contains('pixel') ||
        hostname.contains('phone') ||
        hostname.contains('tab') ||
        hostname.contains('mobile') ||
        hostname.contains('macbook') ||
        hostname.contains('firestick') ||
        hostname.contains('chromecast') ||
        hostname.contains('roku') ||
        hostname.contains('echo') ||
        hostname.contains('alexa') ||
        vendor.contains('apple') ||
        vendor.contains('samsung') ||
        vendor.contains('xiaomi') ||
        vendor.contains('oneplus') ||
        vendor.contains('oppo') ||
        vendor.contains('vivo') ||
        vendor.contains('realme') ||
        vendor.contains('huawei')) {
      return ConnectionType.wireless;
    }

    final ifname = (lease['ifname'] ?? lease['device'] ?? '')
        .toString()
        .toLowerCase();
    if (ifname.startsWith('wlan') ||
        ifname.startsWith('phy') ||
        ifname.startsWith('ra') ||
        ifname.startsWith('wifi') ||
        ifname.startsWith('ath')) {
      return ConnectionType.wireless;
    }

    if (ifname.startsWith('eth') || ifname.startsWith('lan1')) {
      return ConnectionType.wired;
    }

    return ConnectionType.unknown;
  }

  factory Client.fromLease(Map<String, dynamic> lease) {
    String? toStringValue(dynamic value) {
      return value?.toString();
    }

    int? toIntValue(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is double) return value.toInt();
      return null;
    }

    final expires = toIntValue(lease['expires']);
    final activetime = toIntValue(lease['activetime']);

    final remainingLeaseTime = expires;

    int? expiresAtTimestamp;
    if (expires != null && expires > 0) {
      expiresAtTimestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000) + expires;
    }

    List<String>? ipv6Addresses;
    if (lease['ipv6addrs'] != null && lease['ipv6addrs'] is List) {
      ipv6Addresses = (lease['ipv6addrs'] as List)
          .map((e) => e.toString())
          .toList();
    } else if (lease['ipv6addr'] != null) {
      final v6 = lease['ipv6addr'];
      if (v6 is String) {
        ipv6Addresses = v6
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (v6 is List) {
        ipv6Addresses = v6.map((e) => e.toString()).toList();
      }
    }

    final rawName =
        toStringValue(lease['hostname']) ??
        toStringValue(lease['name']) ??
        toStringValue(lease['dnsname']);
    final parsedHostname =
        (rawName != null && rawName.trim().isNotEmpty && rawName.trim() != '*')
        ? rawName.trim()
        : 'Unknown';

    return Client(
      ipAddress: toStringValue(lease['ipaddr']) ?? 'N/A',
      macAddress: toStringValue(lease['macaddr']) ?? 'N/A',
      hostname: parsedHostname,
      hostId: toStringValue(lease['hostid']),
      leaseTime: remainingLeaseTime,
      vendor: toStringValue(lease['vendor']),
      dnsName: toStringValue(lease['dnsname']),
      clientId: toStringValue(lease['clientid']),
      activeTime: activetime,
      expiresAt: expiresAtTimestamp,
      connectionType: _determineConnectionType(lease),
      ipv6Addresses: ipv6Addresses,
      staticLeaseName: toStringValue(lease['staticLeaseName']),
      isStaticLease: lease['isStaticLease'] == true,
      staticLeaseTime: toStringValue(
        lease['staticLeaseTime'] ?? lease['leasetime'],
      ),
    );
  }

  factory Client.fromWirelessStation(
    String macAddress, {
    String? ssid,
    String? wirelessIface,
    bool isDumbApClient = false,
    String? apName,
    int? rxBytes,
    int? txBytes,
    int? rxPackets,
    int? txPackets,
    num? rxRate,
    num? txRate,
    int? signalDbm,
    int? noiseDbm,
    int? throughput,
    double? rxSpeed,
    double? txSpeed,
    int? connectedTime,
  }) {
    return Client(
      ipAddress: 'N/A',
      macAddress: macAddress,
      hostname: 'Unknown',
      connectionType: ConnectionType.wireless,
      neighState: NeighborReachability.reachable,
      ssid: ssid,
      wirelessIface: wirelessIface,
      isDumbApClient: isDumbApClient,
      apName: apName,
      rxBytes: rxBytes,
      txBytes: txBytes,
      rxPackets: rxPackets,
      txPackets: txPackets,
      rxRate: rxRate,
      txRate: txRate,
      signalDbm: signalDbm,
      noiseDbm: noiseDbm,
      throughput: throughput,
      rxSpeed: rxSpeed,
      txSpeed: txSpeed,
      connectedTime: connectedTime,
    );
  }

  String get formattedLeaseTime {
    if (isStatic) {
      final lt = staticLeaseTime?.trim();
      if (lt != null &&
          lt.isNotEmpty &&
          lt.toLowerCase() != 'infinite' &&
          lt.toLowerCase() != '0') {
        return 'Static ($lt)';
      }
      return 'Static (Permanent)';
    }
    if (leaseTime == null) return 'No active lease';
    if (leaseTime == 0) return 'Unlimited';
    if (leaseTime! < 0) return 'Expired';
    return Client.formatDuration(leaseTime!);
  }

  String get formattedActiveTime {
    if (activeTime == null) return 'N/A';
    return Client.formatDuration(activeTime!);
  }

  String get formattedExpiresAt {
    if (expiresAt == null || expiresAt == 0) return 'N/A';
    final date = DateTime.fromMillisecondsSinceEpoch(expiresAt! * 1000);
    return '${date.toLocal()}';
  }

  static String formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0m';

    final days = totalSeconds ~/ (24 * 3600);
    totalSeconds %= (24 * 3600);
    final hours = totalSeconds ~/ 3600;
    totalSeconds %= 3600;
    final minutes = totalSeconds ~/ 60;

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    if (minutes > 0 || parts.isEmpty) parts.add('${minutes}m');

    return parts.join(' ');
  }

  late final String normalizedMac = macAddress.toUpperCase().replaceAll(
    '-',
    ':',
  );

  late final String displayName = _computeDisplayName();

  String _computeDisplayName() {
    final normMac = normalizedMac
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');
    String norm(String val) => val
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    if (staticLeaseName != null &&
        staticLeaseName!.trim().isNotEmpty &&
        staticLeaseName != 'Unknown' &&
        staticLeaseName != '*' &&
        norm(staticLeaseName!) != normMac) {
      return staticLeaseName!.trim();
    }
    if (hostname.isNotEmpty &&
        hostname != 'Unknown' &&
        hostname != '*' &&
        norm(hostname) != normMac) {
      return hostname;
    }
    if (dnsName != null &&
        dnsName!.isNotEmpty &&
        dnsName != 'Unknown' &&
        dnsName != '*' &&
        norm(dnsName!) != normMac) {
      return dnsName!;
    }
    return macAddress;
  }

  bool get isStatic =>
      isStaticLease ||
      (staticLeaseName != null && staticLeaseName!.trim().isNotEmpty);

  Client copyWith({
    String? ipAddress,
    String? macAddress,
    String? hostname,
    String? hostId,
    int? leaseTime,
    String? vendor,
    String? dnsName,
    String? clientId,
    int? activeTime,
    int? expiresAt,
    ConnectionType? connectionType,
    List<String>? ipv6Addresses,
    String? ssid,
    String? wirelessIface,
    bool? isConnected,
    NeighborReachability? neighState,
    String? staticLeaseName,
    bool? isStaticLease,
    String? staticLeaseTime,
    bool? isDumbApClient,
    String? apName,
    int? rxBytes,
    int? txBytes,
    int? rxPackets,
    int? txPackets,
    num? rxRate,
    num? txRate,
    int? signalDbm,
    int? noiseDbm,
    int? throughput,
    double? rxSpeed,
    double? txSpeed,
    int? connectedTime,
  }) {
    return Client(
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      hostname: hostname ?? this.hostname,
      hostId: hostId ?? this.hostId,
      leaseTime: leaseTime ?? this.leaseTime,
      vendor: vendor ?? this.vendor,
      dnsName: dnsName ?? this.dnsName,
      clientId: clientId ?? this.clientId,
      activeTime: activeTime ?? this.activeTime,
      expiresAt: expiresAt ?? this.expiresAt,
      connectionType: connectionType ?? this.connectionType,
      ipv6Addresses: ipv6Addresses ?? this.ipv6Addresses,
      ssid: ssid ?? this.ssid,
      wirelessIface: wirelessIface ?? this.wirelessIface,
      isConnected: isConnected ?? this.isConnected,
      neighState: neighState ?? this.neighState,
      staticLeaseName: staticLeaseName ?? this.staticLeaseName,
      isStaticLease: isStaticLease ?? this.isStaticLease,
      staticLeaseTime: staticLeaseTime ?? this.staticLeaseTime,
      isDumbApClient: isDumbApClient ?? this.isDumbApClient,
      apName: apName ?? this.apName,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
      rxPackets: rxPackets ?? this.rxPackets,
      txPackets: txPackets ?? this.txPackets,
      rxRate: rxRate ?? this.rxRate,
      txRate: txRate ?? this.txRate,
      signalDbm: signalDbm ?? this.signalDbm,
      noiseDbm: noiseDbm ?? this.noiseDbm,
      throughput: throughput ?? this.throughput,
      rxSpeed: rxSpeed ?? this.rxSpeed,
      txSpeed: txSpeed ?? this.txSpeed,
      connectedTime: connectedTime ?? this.connectedTime,
    );
  }

  bool get hasTrafficData =>
      rxBytes != null ||
      txBytes != null ||
      rxSpeed != null ||
      txSpeed != null ||
      rxRate != null ||
      txRate != null;

  String? get formattedDownloadSpeed =>
      txSpeed != null ? formatSpeed(txSpeed!, speedUnit: 'bytes') : null;

  String? get formattedUploadSpeed =>
      rxSpeed != null ? formatSpeed(rxSpeed!, speedUnit: 'bytes') : null;

  String? formattedDownloadSpeedWithUnit([String speedUnit = 'bits']) =>
      txSpeed != null ? formatSpeed(txSpeed!, speedUnit: speedUnit) : null;

  String? formattedUploadSpeedWithUnit([String speedUnit = 'bits']) =>
      rxSpeed != null ? formatSpeed(rxSpeed!, speedUnit: speedUnit) : null;

  String? get formattedTotalDownloaded =>
      txBytes != null ? formatBytes(txBytes!) : null;

  String? get formattedTotalUploaded =>
      rxBytes != null ? formatBytes(rxBytes!) : null;

  String? get formattedPhyRate {
    if (txRate == null && rxRate == null) return null;
    String formatMbit(num? val) {
      if (val == null) return '?';
      var numRate = val;
      if (numRate > 1000000) numRate = numRate / 100.0;
      final mbit = numRate > 1000 ? numRate / 1000.0 : numRate.toDouble();
      return mbit >= 100 ? mbit.toStringAsFixed(0) : mbit.toStringAsFixed(1);
    }

    if (txRate != null && rxRate != null) {
      return '↓ ${formatMbit(txRate)} Mbps • ↑ ${formatMbit(rxRate)} Mbps';
    } else if (txRate != null) {
      return '↓ ${formatMbit(txRate)} Mbps';
    } else {
      return '↑ ${formatMbit(rxRate)} Mbps';
    }
  }

  String? get signalQualityLabel {
    if (signalDbm == null) return null;
    if (signalDbm! >= -50) return 'Excellent';
    if (signalDbm! >= -65) return 'Good';
    if (signalDbm! >= -75) return 'Fair';
    return 'Weak';
  }

  String? get formattedSignalWithQuality {
    if (signalDbm == null) return null;
    final q = signalQualityLabel;
    return q != null ? '$signalDbm dBm ($q)' : '$signalDbm dBm';
  }

  String? get formattedConnectedTime {
    if (connectedTime != null && connectedTime! > 0) {
      return formatDuration(connectedTime!);
    }
    if (activeTime != null && activeTime! > 0) {
      return formatDuration(activeTime!);
    }
    return null;
  }

  static String formatBytes(num bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (log(bytes) / log(1024)).floor();
    if (i < 0) i = 0;
    if (i >= suffixes.length) i = suffixes.length - 1;
    if (i == 0) return '${bytes.toInt()} B';
    final numVal = bytes / pow(1024, i);
    return '${numVal.toStringAsFixed(numVal >= 100 ? 0 : 1)} ${suffixes[i]}';
  }

  static String formatSpeed(double bytesPerSec, {String speedUnit = 'bytes'}) {
    if (bytesPerSec.isNaN || bytesPerSec.isInfinite || bytesPerSec <= 0) {
      return speedUnit == 'bits' ? '0 bps' : '0 B/s';
    }
    if (speedUnit == 'bits') {
      final bitsPerSecond = bytesPerSec * 8;
      if (bitsPerSecond < 1000) {
        return '${bitsPerSecond.toStringAsFixed(0)} bps';
      }
      if (bitsPerSecond < 1000000) {
        final val = bitsPerSecond / 1000;
        final str = val >= 100
            ? val.toStringAsFixed(0)
            : val.toStringAsFixed(1);
        return '$str Kbps';
      }
      final val = bitsPerSecond / 1000000;
      final str = val >= 100 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
      return '$str Mbps';
    } else {
      if (bytesPerSec < 1024) {
        return '${bytesPerSec.toStringAsFixed(0)} B/s';
      }
      if (bytesPerSec < 1024 * 1024) {
        return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
      }
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  static List<Client> buildMergedClientList(
    List<Map<String, dynamic>> dhcpLeases,
    Set<String> wirelessMacs, {
    bool isDumbAp = false,
    String? apName,
  }) {
    String norm(String m) => m
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    final normalizedWireless = wirelessMacs.map(norm).toSet();

    final clients = <String, Client>{};
    for (final lease in dhcpLeases) {
      final client = Client.fromLease(lease);
      final macNorm = norm(client.macAddress);
      final isWireless = normalizedWireless.contains(macNorm);
      clients[macNorm] = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : ConnectionType.wired,
        isDumbApClient: isWireless && isDumbAp,
        apName: isWireless && isDumbAp ? apName : null,
      );
    }

    for (final mac in normalizedWireless) {
      if (!clients.containsKey(mac)) {
        clients[mac] = Client.fromWirelessStation(
          mac,
          isDumbApClient: isDumbAp,
          apName: apName,
        );
      }
    }

    final list = clients.values.toList();
    list.sort((a, b) {
      int typeOrder(ConnectionType t) {
        switch (t) {
          case ConnectionType.wireless:
            return 0;
          case ConnectionType.wired:
            return 1;
          default:
            return 2;
        }
      }

      final cmpType = typeOrder(
        a.connectionType,
      ).compareTo(typeOrder(b.connectionType));
      if (cmpType != 0) return cmpType;
      return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
    });
    return list;
  }
}
