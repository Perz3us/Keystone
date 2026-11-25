// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum DnsProtocol { udpPort53, tcpPort53, doh, routerNslookup }

extension DnsProtocolX on DnsProtocol {
  String get label {
    switch (this) {
      case DnsProtocol.udpPort53:
        return 'UDP Port 53';
      case DnsProtocol.tcpPort53:
        return 'TCP Port 53';
      case DnsProtocol.doh:
        return 'DNS-over-HTTPS (DoH)';
      case DnsProtocol.routerNslookup:
        return 'Router nslookup RPC';
    }
  }
}

enum DnsVantagePoint { clientDevice, router }

extension DnsVantagePointX on DnsVantagePoint {
  String get label {
    switch (this) {
      case DnsVantagePoint.clientDevice:
        return 'Client Device';
      case DnsVantagePoint.router:
        return 'Router';
    }
  }
}

enum DnsBenchmarkStatus {
  untested,

  testing,

  success,

  partial,

  timeout,

  refused,

  unreachable,

  serverError,

  unsupported,

  configRequired,
}

extension DnsBenchmarkStatusX on DnsBenchmarkStatus {
  bool get hasValidLatency =>
      this == DnsBenchmarkStatus.success || this == DnsBenchmarkStatus.partial;

  bool get isRunning => this == DnsBenchmarkStatus.testing;

  String get label {
    switch (this) {
      case DnsBenchmarkStatus.untested:
        return 'Untested';
      case DnsBenchmarkStatus.testing:
        return 'Testing...';
      case DnsBenchmarkStatus.success:
        return 'Success';
      case DnsBenchmarkStatus.partial:
        return 'Partial';
      case DnsBenchmarkStatus.timeout:
        return 'Timeout';
      case DnsBenchmarkStatus.refused:
        return 'Refused';
      case DnsBenchmarkStatus.unreachable:
        return 'Unreachable';
      case DnsBenchmarkStatus.serverError:
        return 'Server Error';
      case DnsBenchmarkStatus.unsupported:
        return 'Unsupported';
      case DnsBenchmarkStatus.configRequired:
        return 'Config Required';
    }
  }
}

@immutable
class RouterDnsConfig {
  final bool isLocalForwarder;

  final String localEndpoint;

  final List<String> upstreamServers;

  final String? wanInterface;

  final bool isVerified;

  final String details;

  const RouterDnsConfig({
    required this.isLocalForwarder,
    required this.localEndpoint,
    required this.upstreamServers,
    this.wanInterface,
    this.isVerified = false,
    required this.details,
  });

  factory RouterDnsConfig.unknown() {
    return const RouterDnsConfig(
      isLocalForwarder: false,
      localEndpoint: 'Unknown',
      upstreamServers: [],
      isVerified: false,
      details: 'Current router DNS resolver configuration is unknown.',
    );
  }
}

@immutable
class DnsProviderMetadata {
  final String id;

  final String name;

  final String primaryServer;

  final String? secondaryServer;

  final String? ipv6Server;

  final String? dohUrl;

  final bool isRouterDns;

  final bool isCustomConfigRequired;

  final String description;

  final List<String> features;

  const DnsProviderMetadata({
    required this.id,
    required this.name,
    required this.primaryServer,
    this.secondaryServer,
    this.ipv6Server,
    this.dohUrl,
    this.isRouterDns = false,
    this.isCustomConfigRequired = false,
    required this.description,
    this.features = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'primaryServer': primaryServer,
    'secondaryServer': secondaryServer,
    'ipv6Server': ipv6Server,
    'dohUrl': dohUrl,
    'isRouterDns': isRouterDns,
    'isCustomConfigRequired': isCustomConfigRequired,
    'description': description,
    'features': features,
  };
}

@immutable
class DnsBenchmarkResult {
  final DnsProviderMetadata provider;
  final DnsBenchmarkStatus status;
  final double? medianLatencyMs;
  final double? minLatencyMs;
  final double? maxLatencyMs;
  final double? avgLatencyMs;
  final List<double> samples;
  final int totalQueries;
  final int successfulQueries;
  final int failedQueries;
  final String testedEndpoint;
  final DnsProtocol protocol;
  final DnsVantagePoint vantagePoint;
  final String? errorMessage;
  final DateTime? timestamp;
  final RouterDnsConfig? routerDnsConfig;

  const DnsBenchmarkResult({
    required this.provider,
    this.status = DnsBenchmarkStatus.untested,
    this.medianLatencyMs,
    this.minLatencyMs,
    this.maxLatencyMs,
    this.avgLatencyMs,
    this.samples = const [],
    this.totalQueries = 0,
    this.successfulQueries = 0,
    this.failedQueries = 0,
    required this.testedEndpoint,
    this.protocol = DnsProtocol.udpPort53,
    this.vantagePoint = DnsVantagePoint.clientDevice,
    this.errorMessage,
    this.timestamp,
    this.routerDnsConfig,
  });

  DnsBenchmarkResult copyWith({
    DnsBenchmarkStatus? status,
    double? medianLatencyMs,
    double? minLatencyMs,
    double? maxLatencyMs,
    double? avgLatencyMs,
    List<double>? samples,
    int? totalQueries,
    int? successfulQueries,
    int? failedQueries,
    String? testedEndpoint,
    DnsProtocol? protocol,
    DnsVantagePoint? vantagePoint,
    String? errorMessage,
    DateTime? timestamp,
    RouterDnsConfig? routerDnsConfig,
  }) {
    return DnsBenchmarkResult(
      provider: provider,
      status: status ?? this.status,
      medianLatencyMs: medianLatencyMs ?? this.medianLatencyMs,
      minLatencyMs: minLatencyMs ?? this.minLatencyMs,
      maxLatencyMs: maxLatencyMs ?? this.maxLatencyMs,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      samples: samples ?? this.samples,
      totalQueries: totalQueries ?? this.totalQueries,
      successfulQueries: successfulQueries ?? this.successfulQueries,
      failedQueries: failedQueries ?? this.failedQueries,
      testedEndpoint: testedEndpoint ?? this.testedEndpoint,
      protocol: protocol ?? this.protocol,
      vantagePoint: vantagePoint ?? this.vantagePoint,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
      routerDnsConfig: routerDnsConfig ?? this.routerDnsConfig,
    );
  }

  static List<DnsBenchmarkResult> sortAlphabetical(
    List<DnsBenchmarkResult> list,
  ) {
    final copy = List<DnsBenchmarkResult>.from(list);
    copy.sort(
      (a, b) => a.provider.name.toLowerCase().compareTo(
        b.provider.name.toLowerCase(),
      ),
    );
    return copy;
  }

  static List<DnsBenchmarkResult> sortByAscendingLatency(
    List<DnsBenchmarkResult> list,
  ) {
    final copy = List<DnsBenchmarkResult>.from(list);
    copy.sort((a, b) {
      final aHasValid = a.status.hasValidLatency && a.medianLatencyMs != null;
      final bHasValid = b.status.hasValidLatency && b.medianLatencyMs != null;

      if (aHasValid && bHasValid) {
        final diff = a.medianLatencyMs!.compareTo(b.medianLatencyMs!);
        if (diff != 0) return diff;
        return a.provider.name.toLowerCase().compareTo(
          b.provider.name.toLowerCase(),
        );
      }

      if (aHasValid && !bHasValid) return -1;
      if (!aHasValid && bHasValid) return 1;

      final statusDiff = a.status.index.compareTo(b.status.index);
      if (statusDiff != 0) return statusDiff;
      return a.provider.name.toLowerCase().compareTo(
        b.provider.name.toLowerCase(),
      );
    });
    return copy;
  }
}
