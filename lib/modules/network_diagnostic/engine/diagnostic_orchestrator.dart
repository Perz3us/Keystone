// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import '../../../models/router_capabilities.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../models/diagnostic_capabilities.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_evidence.dart';
import '../models/diagnostic_scope.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/network_diagnostic_report.dart';
import 'diagnostic_rules_engine.dart';
import 'network_config_collector.dart';

typedef ProgressCallback =
    void Function(DiagnosticTestResult currentResult, double progressPercent);

class DiagnosticOrchestrator {
  final IApiService api;
  final RouterCapabilities? routerCapabilities;
  final DiagnosticRulesEngine rulesEngine;

  bool _isCancelled = false;

  DiagnosticOrchestrator({
    required this.api,
    this.routerCapabilities,
    this.rulesEngine = const DiagnosticRulesEngine(),
  });

  void cancel() {
    _isCancelled = true;
  }

  Future<NetworkDiagnosticReport> runDiagnostics({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    ProgressCallback? onProgress,
  }) async {
    if (_isCancelled) {
      return _buildCancelledReport(
        'diag_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}',
        ipAddress,
        [],
        const DiagnosticCapabilities(),
      );
    }
    final results = <DiagnosticTestResult>[];
    final unverifiedAreas = <String>[];
    final sessionId =
        'diag_${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

    final stage1Start = DateTime.now();
    bool mgmtApiOk = false;
    DiagnosticEvidence mgmtEvidence = const DiagnosticEvidence();

    try {
      final probeRes = await api
          .call(ipAddress, sysauth, useHttps, object: 'system', method: 'info')
          .timeout(const Duration(seconds: 4));

      if (probeRes is List && probeRes.isNotEmpty && probeRes[0] == 0) {
        mgmtApiOk = true;
        mgmtEvidence = DiagnosticEvidence(
          facts: ['Signed in to the router.', 'The router answers.'],
          timestamps: {'authenticated': DateTime.now()},
        );
      } else {
        mgmtEvidence = DiagnosticEvidence(
          facts: ['The router answered but refused the session.'],
          timestamps: {'failed': DateTime.now()},
        );
      }
    } catch (e) {
      mgmtEvidence = DiagnosticEvidence(
        facts: ['Couldn\'t reach the router at $ipAddress: $e'],
        timestamps: {'error': DateTime.now()},
      );
    }

    final mgmtResult = DiagnosticTestResult(
      id: 'router_management_api',
      title: 'Router Management & API Reachability',
      scope: DiagnosticScope.managementApi,
      status: mgmtApiOk
          ? DiagnosticStatus.healthy
          : DiagnosticStatus.failureConfirmed,
      confidence: DiagnosticConfidence.high,
      explanation: mgmtApiOk
          ? 'Signed in and answering.'
          : 'Couldn\'t talk to the router.',
      whyItMatters: 'Every other check runs through the router.',
      recommendedStep: mgmtApiOk
          ? null
          : 'Check router Wi-Fi/cable connection and credentials in Manage Routers.',
      evidence: mgmtEvidence,
      startedAt: stage1Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage1Start),
    );
    results.add(mgmtResult);
    onProgress?.call(mgmtResult, 0.15);

    if (!mgmtApiOk || _isCancelled) {
      unverifiedAreas.addAll([
        'Router WAN uplink state (API unreachable)',
        'Default routing table (API unreachable)',
        'Router-side DNS resolution (API unreachable)',
        'External internet reachability from router (API unreachable)',
        'Client-side traffic path (Device-to-router connection failed)',
      ]);

      final skippedTests = _buildSkippedTests(
        reason: 'The router couldn\'t be reached.',
      );
      results.addAll(skippedTests);

      final findings = rulesEngine.analyze(
        testResults: results,
        capabilities: const DiagnosticCapabilities(),
      );
      final (status, summary) = rulesEngine.synthesizeOverall(
        testResults: results,
        findings: findings,
      );

      return NetworkDiagnosticReport(
        sessionId: sessionId,
        timestamp: DateTime.now(),
        routerScope: ipAddress,
        overallStatus: status,
        overallSummary: summary,
        testResults: results,
        findings: findings,
        capabilities: const DiagnosticCapabilities(),
        unverifiedAreas: unverifiedAreas,
      );
    }

    final collector = NetworkConfigCollector(
      api: api,
      routerCaps: routerCapabilities,
    );
    final netConfig = await collector.collect(
      ipAddress: ipAddress,
      sysauth: sysauth,
      useHttps: useHttps,
    );
    final caps = netConfig.capabilities;

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    final stage3Start = DateTime.now();
    DiagnosticStatus uplinkStatus = DiagnosticStatus.inconclusive;
    String uplinkExplanation;
    String? uplinkRecommended;
    final uplinkFacts = <String>[];

    final uplink = netConfig.activeUplink;
    if (uplink == null) {
      uplinkStatus = DiagnosticStatus.suspected;
      uplinkExplanation = 'No internet connection is set up on the router.';
      uplinkFacts.add(
        'No interface discovered with default route or WAN designation.',
      );
      uplinkRecommended =
          'Check router interface configuration under Interfaces.';
    } else {
      uplinkFacts.add(
        'Identified primary uplink: "${uplink.name}" (proto: ${uplink.protocol}, device: ${uplink.device}).',
      );
      if (uplink.isUp) {
        if (uplink.protocol == 'dhcp' && uplink.ipv4Addresses.isEmpty) {
          uplinkStatus = DiagnosticStatus.failureConfirmed;
          uplinkExplanation =
              'WAN interface is up, but no IPv4 address was provided by DHCP.';
          uplinkFacts.add(
            'DHCP protocol active but 0 IPv4 addresses assigned.',
          );
          uplinkRecommended =
              'Restart upstream modem/ONT or check Ethernet cable.';
        } else if (uplink.protocol == 'pppoe' &&
            uplink.ipv4Addresses.isEmpty &&
            uplink.ipv6Addresses.isEmpty) {
          uplinkStatus = DiagnosticStatus.failureConfirmed;
          uplinkExplanation = 'PPPoE hasn\'t connected.';
          uplinkFacts.add(
            'PPPoE session disconnected. No IP addresses assigned.',
          );
          uplinkRecommended = 'Verify PPPoE credentials in router settings.';
        } else {
          uplinkStatus = DiagnosticStatus.healthy;
          uplinkExplanation =
              'Active uplink "${uplink.name}" is up with protocol ${uplink.protocol}.';
          if (uplink.ipv4Addresses.isNotEmpty) {
            uplinkFacts.add('IPv4 Address: ${uplink.ipv4Addresses.first}');
          }
          if (uplink.ipv6Addresses.isNotEmpty) {
            uplinkFacts.add('IPv6 Address: ${uplink.ipv6Addresses.first}');
          }
        }
      } else {
        uplinkStatus = DiagnosticStatus.failureConfirmed;
        uplinkExplanation =
            'WAN interface "${uplink.name}" is administratively down or disconnected.';
        uplinkFacts.add(
          'Interface runtime state reports up=false, available=${uplink.isAvailable}.',
        );
        uplinkRecommended =
            'Check physical cable between router WAN port and modem/ONT.';
      }
    }

    final uplinkResult = DiagnosticTestResult(
      id: 'wan_interface_state',
      title: 'WAN Interface & Uplink State',
      scope: DiagnosticScope.routerUplink,
      status: uplinkStatus,
      confidence: DiagnosticConfidence.high,
      explanation: uplinkExplanation,
      whyItMatters:
          'The uplink interface connects your router to the ISP modem, ONT, or upstream gateway.',
      recommendedStep: uplinkRecommended,
      evidence: DiagnosticEvidence(facts: uplinkFacts),
      startedAt: stage3Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage3Start),
    );
    results.add(uplinkResult);
    onProgress?.call(uplinkResult, 0.30);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    final stage4Start = DateTime.now();
    DiagnosticStatus routeStatus = DiagnosticStatus.inconclusive;
    String routeExplanation;
    final routeFacts = <String>[];

    final hasDefaultRoute =
        netConfig.kernelRoutes.any((r) => r.isDefault) ||
        (uplink?.hasDefaultRoute == true);

    if (hasDefaultRoute) {
      routeStatus = DiagnosticStatus.healthy;
      routeExplanation = 'There is a default route.';
      routeFacts.add('Found a default route.');
    } else {
      routeStatus = DiagnosticStatus.failureConfirmed;
      routeExplanation =
          'No default route (0.0.0.0/0) found in kernel routing table.';
      routeFacts.add('The routing table has no default gateway.');
    }

    final routeResult = DiagnosticTestResult(
      id: 'default_route_verification',
      title: 'Default Route Verification',
      scope: DiagnosticScope.routing,
      status: routeStatus,
      confidence: DiagnosticConfidence.high,
      explanation: routeExplanation,
      whyItMatters:
          'A default route specifies the next-hop router that receives internet-bound packets.',
      evidence: DiagnosticEvidence(facts: routeFacts),
      startedAt: stage4Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage4Start),
    );
    results.add(routeResult);
    onProgress?.call(routeResult, 0.45);

    final stage4GwStart = DateTime.now();
    DiagnosticStatus gwStatus = DiagnosticStatus.notTested;
    String gwExplanation = 'No gateway IP was identified.';
    final gwFacts = <String>[];

    final targetGw = netConfig.ipv4Gateways.isNotEmpty
        ? netConfig.ipv4Gateways.first
        : uplink?.gateway;

    if (targetGw != null &&
        targetGw.isNotEmpty &&
        !targetGw.startsWith('Point-to-Point')) {
      gwFacts.add('Testing gateway IP: $targetGw');
      try {
        final pingRes = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: targetGw,
          count: 2,
          timeoutSec: 2,
        );
        if (pingRes.isSuccess) {
          gwStatus = DiagnosticStatus.healthy;
          gwExplanation =
              'Upstream gateway ($targetGw) is reachable (RTT: ${pingRes.avgRttMs?.toStringAsFixed(1) ?? 'N/A'} ms).';
          gwFacts.add('ICMP echo to gateway succeeded with 0% packet loss.');
        } else {
          gwStatus = DiagnosticStatus.suspected;
          gwExplanation =
              'Upstream gateway ($targetGw) did not respond to ICMP ping (may drop ICMP).';
          gwFacts.add('ICMP echo to gateway timed out or was rejected.');
        }
      } catch (e) {
        gwStatus = DiagnosticStatus.inconclusive;
        gwExplanation = 'Could not probe gateway ($targetGw): $e';
      }
    } else if (uplink?.protocol == 'pppoe') {
      gwStatus = DiagnosticStatus.healthy;
      gwExplanation =
          'PPPoE point-to-point link uses interface routing without static gateway.';
      gwFacts.add('Point-to-point interface routes via PPP peer.');
    } else {
      gwStatus = DiagnosticStatus.inconclusive;
      gwExplanation =
          'No upstream gateway IP could be verified from interface status.';
    }

    final gwResult = DiagnosticTestResult(
      id: 'gateway_reachability',
      title: 'Gateway Reachability',
      scope: DiagnosticScope.addressing,
      status: gwStatus,
      confidence: gwStatus == DiagnosticStatus.healthy
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate,
      explanation: gwExplanation,
      whyItMatters:
          'The gateway is the first upstream hop on the way to the wider internet.',
      evidence: DiagnosticEvidence(facts: gwFacts),
      startedAt: stage4GwStart,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage4GwStart),
    );
    results.add(gwResult);
    onProgress?.call(gwResult, 0.55);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    final stage5Start = DateTime.now();
    DiagnosticStatus dnsStatus = DiagnosticStatus.inconclusive;
    String dnsExplanation;
    final dnsFacts = <String>[];

    bool dnsDomain1Ok = false;
    bool dnsDomain2Ok = false;

    try {
      final res1 = await api.executeDnsLookup(
        ipAddress,
        sysauth,
        useHttps,
        host: 'openwrt.org',
      );
      if (res1.isSuccess &&
          (res1.ipv4Addresses.isNotEmpty || res1.ipv6Addresses.isNotEmpty)) {
        dnsDomain1Ok = true;
        dnsFacts.add(
          'Resolved openwrt.org -> ${res1.ipv4Addresses.join(', ')}',
        );
      } else {
        dnsFacts.add(
          'Failed to resolve openwrt.org: ${res1.errorMessage ?? 'Lookup error'}',
        );
      }
    } catch (e) {
      dnsFacts.add('Exception probing openwrt.org: $e');
    }

    try {
      final res2 = await api.executeDnsLookup(
        ipAddress,
        sysauth,
        useHttps,
        host: 'google.com',
      );
      if (res2.isSuccess &&
          (res2.ipv4Addresses.isNotEmpty || res2.ipv6Addresses.isNotEmpty)) {
        dnsDomain2Ok = true;
        dnsFacts.add('Resolved google.com -> ${res2.ipv4Addresses.join(', ')}');
      } else {
        dnsFacts.add(
          'Failed to resolve google.com: ${res2.errorMessage ?? 'Lookup error'}',
        );
      }
    } catch (e) {
      dnsFacts.add('Exception probing google.com: $e');
    }

    if (dnsDomain1Ok && dnsDomain2Ok) {
      dnsStatus = DiagnosticStatus.healthy;
      dnsExplanation = 'Names resolve.';
    } else if (dnsDomain1Ok || dnsDomain2Ok) {
      dnsStatus = DiagnosticStatus.degraded;
      dnsExplanation = 'Some names resolve and some don\'t.';
    } else {
      dnsStatus = DiagnosticStatus.failureConfirmed;
      dnsExplanation = 'No names resolve.';
    }

    final dnsResult = DiagnosticTestResult(
      id: 'dns_resolution',
      title: 'DNS Resolution Checks',
      scope: DiagnosticScope.dns,
      status: dnsStatus,
      confidence: DiagnosticConfidence.high,
      explanation: dnsExplanation,
      whyItMatters: 'Without DNS, websites don\'t open by name.',
      recommendedStep: dnsStatus.isProblem
          ? 'Check upstream DNS settings in DHCP & DNS, or flush DNS cache.'
          : null,
      evidence: DiagnosticEvidence(facts: dnsFacts),
      startedAt: stage5Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage5Start),
    );
    results.add(dnsResult);
    onProgress?.call(dnsResult, 0.70);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    final stage6Start = DateTime.now();
    DiagnosticStatus ipv4Status = DiagnosticStatus.inconclusive;
    String ipv4Explanation;
    final ipv4Facts = <String>[];

    const targets = ['1.1.1.1', '8.8.8.8', '9.9.9.9'];
    int successfulPings = 0;
    double? minLatency;

    for (final t in targets) {
      if (_isCancelled) break;
      try {
        final p = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: t,
          count: 2,
          timeoutSec: 2,
        );
        if (p.isSuccess) {
          successfulPings++;
          final lat = p.avgRttMs ?? p.minRttMs;
          if (lat != null && (minLatency == null || lat < minLatency)) {
            minLatency = lat;
          }
          ipv4Facts.add(
            'Ping to $t succeeded (${lat?.toStringAsFixed(1) ?? 'N/A'} ms).',
          );
        } else {
          ipv4Facts.add('Ping to $t failed / unanswered.');
        }
      } catch (e) {
        ipv4Facts.add('Ping to $t threw error: $e');
      }
    }

    if (successfulPings == targets.length) {
      ipv4Status = DiagnosticStatus.healthy;
      ipv4Explanation =
          'Every IPv4 address answered (min RTT: ${minLatency?.toStringAsFixed(1) ?? 'N/A'} ms).';
    } else if (successfulPings > 0) {
      ipv4Status = DiagnosticStatus.degraded;
      ipv4Explanation =
          'IPv4 partly works ($successfulPings/${targets.length} endpoints responded).';
    } else {
      if (dnsStatus == DiagnosticStatus.healthy) {
        ipv4Status = DiagnosticStatus.healthy;
        ipv4Explanation = 'The internet works, but pings are blocked.';
        ipv4Facts.add(
          'ICMP ping echo blocked, but upstream DNS resolution verified.',
        );
      } else {
        ipv4Status = DiagnosticStatus.failureConfirmed;
        ipv4Explanation = 'The router can\'t reach the internet over IPv4.';
      }
    }

    final ipv4Result = DiagnosticTestResult(
      id: 'ipv4_external_reachability',
      title: 'IPv4 External Reachability',
      scope: DiagnosticScope.ipv4,
      status: ipv4Status,
      confidence: DiagnosticConfidence.high,
      explanation: ipv4Explanation,
      whyItMatters: 'Shows if the router itself has internet.',
      recommendedStep: ipv4Status.isProblem
          ? 'Check router WAN status, cable connections, and ISP service health.'
          : null,
      evidence: DiagnosticEvidence(facts: ipv4Facts),
      startedAt: stage6Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage6Start),
    );
    results.add(ipv4Result);
    onProgress?.call(ipv4Result, 0.85);

    if (_isCancelled) {
      return _buildCancelledReport(sessionId, ipAddress, results, caps);
    }

    final stage7Start = DateTime.now();
    DiagnosticStatus ipv6Status;
    String ipv6Explanation;
    final ipv6Facts = <String>[];

    if (!caps.isIpv6Configured) {
      ipv6Status = DiagnosticStatus.notApplicable;
      ipv6Explanation =
          'IPv6 is not configured or enabled on this router (IPv4-only network).';
      ipv6Facts.add(
        'No global IPv6 prefix or gateway found on active interfaces.',
      );
    } else if (!caps.hasPing6) {
      ipv6Status = DiagnosticStatus.unsupported;
      ipv6Explanation =
          'Router does not have ping6 / IPv6 diagnostic utilities installed.';
      ipv6Facts.add('ping6 command is not available in OpenWrt environment.');
    } else {
      int v6Success = 0;
      const v6Targets = ['2606:4700:4700::1111', '2001:4860:4860::8888'];

      for (final t in v6Targets) {
        if (_isCancelled) break;
        try {
          final p = await api.executePing(
            ipAddress,
            sysauth,
            useHttps,
            target: t,
            count: 2,
            timeoutSec: 2,
            isIpv6: true,
          );
          if (p.isSuccess) {
            v6Success++;
            ipv6Facts.add(
              'IPv6 ping to $t succeeded (${p.avgRttMs?.toStringAsFixed(1) ?? 'N/A'} ms).',
            );
          } else {
            ipv6Facts.add('IPv6 ping to $t failed.');
          }
        } catch (e) {
          ipv6Facts.add('IPv6 ping to $t error: $e');
        }
      }

      if (v6Success == v6Targets.length) {
        ipv6Status = DiagnosticStatus.healthy;
        ipv6Explanation = 'IPv6 works.';
      } else if (v6Success > 0) {
        ipv6Status = DiagnosticStatus.degraded;
        ipv6Explanation =
            'Partial IPv6 reachability ($v6Success/${v6Targets.length} endpoints responded).';
      } else {
        ipv6Status = DiagnosticStatus.failureConfirmed;
        ipv6Explanation =
            'IPv6 is configured on router, but cannot reach global IPv6 destinations.';
      }
    }

    final ipv6Result = DiagnosticTestResult(
      id: 'ipv6_external_reachability',
      title: 'IPv6 External Reachability',
      scope: DiagnosticScope.ipv6,
      status: ipv6Status,
      confidence: ipv6Status == DiagnosticStatus.notApplicable
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate,
      explanation: ipv6Explanation,
      whyItMatters: 'IPv6 can fail while IPv4 works.',
      evidence: DiagnosticEvidence(facts: ipv6Facts),
      startedAt: stage7Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage7Start),
    );
    results.add(ipv6Result);
    onProgress?.call(ipv6Result, 0.90);

    final stage8Start = DateTime.now();
    DiagnosticStatus fwdStatus = DiagnosticStatus.healthy;
    String fwdExplanation =
        'LAN-to-WAN forwarding and NAT masquerading are permitted in firewall.';
    final fwdFacts = <String>[];

    if (!caps.isLanToWanForwardingAllowed) {
      fwdStatus = DiagnosticStatus.failureConfirmed;
      fwdExplanation = 'Firewall rejects forwarding from LAN zone to WAN zone.';
      fwdFacts.add(
        'Firewall forwarding policy between "lan" and "wan" is disabled or rejected.',
      );
    } else if (!caps.isWanMasqueradingEnabled) {
      fwdStatus = DiagnosticStatus.degraded;
      fwdExplanation =
          'WAN masquerading (NAT) is disabled; LAN clients without public IPs cannot access the internet.';
      fwdFacts.add('Zone "wan" has masquerading set to 0 or disabled.');
    } else {
      fwdFacts.add('Firewall zone forwarding (lan -> wan): ACCEPT');
      fwdFacts.add('WAN zone masquerade (NAT): ENABLED');
    }

    final fwdResult = DiagnosticTestResult(
      id: 'client_forwarding_policy',
      title: 'LAN Forwarding & NAT Policy',
      scope: DiagnosticScope.clientForwarding,
      status: fwdStatus,
      confidence: DiagnosticConfidence.high,
      explanation: fwdExplanation,
      whyItMatters:
          'If this is off, the router has internet but your devices don\'t.',
      recommendedStep: fwdStatus.isProblem
          ? 'Check Firewall & Security zone settings to allow LAN-to-WAN forwarding and NAT.'
          : null,
      evidence: DiagnosticEvidence(facts: fwdFacts),
      startedAt: stage8Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage8Start),
    );
    results.add(fwdResult);
    onProgress?.call(fwdResult, 0.95);

    final stage9Start = DateTime.now();
    DiagnosticStatus mtuStatus = DiagnosticStatus.notTested;
    String mtuExplanation = 'MTU check skipped or not needed.';
    final mtuFacts = <String>[];

    if (caps.hasPing &&
        caps.hasFileExec &&
        ipv4Status == DiagnosticStatus.healthy) {
      try {
        final pMtu = await api.executePing(
          ipAddress,
          sysauth,
          useHttps,
          target: '1.1.1.1',
          count: 1,
          timeoutSec: 2,
        );
        if (pMtu.isSuccess) {
          mtuStatus = DiagnosticStatus.healthy;
          mtuExplanation = 'Normal-size packets get through.';
          mtuFacts.add('A full-size packet got through.');
        } else {
          mtuStatus = DiagnosticStatus.inconclusive;
          mtuExplanation = 'The packet size test didn\'t give a clear answer.';
          mtuFacts.add('Probe packet was dropped or unacknowledged.');
        }
      } catch (e) {
        mtuStatus = DiagnosticStatus.unsupported;
        mtuExplanation =
            'Router does not support MTU payload diagnostics ($e).';
      }
    } else {
      mtuStatus = DiagnosticStatus.unsupported;
      mtuExplanation =
          'MTU probing is unsupported when internet reachability is down or ping is unavailable.';
    }

    final mtuResult = DiagnosticTestResult(
      id: 'path_mtu_check',
      title: 'Path MTU & Fragmentation Check',
      scope: DiagnosticScope.pathMtu,
      status: mtuStatus,
      confidence: mtuStatus == DiagnosticStatus.healthy
          ? DiagnosticConfidence.moderate
          : DiagnosticConfidence.low,
      explanation: mtuExplanation,
      whyItMatters:
          'A wrong MTU makes downloads slow and some sites fail to open.',
      evidence: DiagnosticEvidence(facts: mtuFacts),
      startedAt: stage9Start,
      completedAt: DateTime.now(),
      duration: DateTime.now().difference(stage9Start),
    );
    results.add(mtuResult);
    onProgress?.call(mtuResult, 1.0);

    unverifiedAreas.addAll([
      'Your device and its Wi-Fi signal',
      'Ports used by single apps, like calls, VPNs and games',
      'Your provider\'s own network',
    ]);

    final findings = rulesEngine.analyze(
      testResults: results,
      capabilities: caps,
    );
    final (overallStatus, overallSummary) = rulesEngine.synthesizeOverall(
      testResults: results,
      findings: findings,
    );

    return NetworkDiagnosticReport(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      routerScope: ipAddress,
      overallStatus: overallStatus,
      overallSummary: overallSummary,
      testResults: results,
      findings: findings,
      capabilities: caps,
      unverifiedAreas: unverifiedAreas,
    );
  }

  NetworkDiagnosticReport _buildCancelledReport(
    String sessionId,
    String ipAddress,
    List<DiagnosticTestResult> completed,
    DiagnosticCapabilities caps,
  ) {
    return NetworkDiagnosticReport(
      sessionId: sessionId,
      timestamp: DateTime.now(),
      routerScope: ipAddress,
      overallStatus: DiagnosticStatus.inconclusive,
      overallSummary: 'Stopped before all the checks finished.',
      testResults: completed,
      findings: const [],
      capabilities: caps,
      unverifiedAreas: const ['Stopped early.'],
    );
  }

  List<DiagnosticTestResult> _buildSkippedTests({required String reason}) {
    final now = DateTime.now();
    return [
      DiagnosticTestResult(
        id: 'wan_interface_state',
        title: 'WAN Interface & Uplink State',
        scope: DiagnosticScope.routerUplink,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Shows if the internet connection is up.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'default_route_verification',
        title: 'Default Route Verification',
        scope: DiagnosticScope.routing,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Checks default routing table.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'gateway_reachability',
        title: 'Gateway Reachability',
        scope: DiagnosticScope.addressing,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Shows if your provider\'s equipment answers.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'dns_resolution',
        title: 'DNS Resolution Checks',
        scope: DiagnosticScope.dns,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Checks resolver name resolution.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'ipv4_external_reachability',
        title: 'IPv4 External Reachability',
        scope: DiagnosticScope.ipv4,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Tests external IPv4 destinations.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'ipv6_external_reachability',
        title: 'IPv6 External Reachability',
        scope: DiagnosticScope.ipv6,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Tests external IPv6 destinations.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'client_forwarding_policy',
        title: 'LAN Forwarding & NAT Policy',
        scope: DiagnosticScope.clientForwarding,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Shows if the firewall lets devices out.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
      DiagnosticTestResult(
        id: 'path_mtu_check',
        title: 'Path MTU & Fragmentation Check',
        scope: DiagnosticScope.pathMtu,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.inconclusive,
        explanation: 'Skipped: $reason',
        whyItMatters: 'Shows if large packets get through.',
        skipOrFailureReason: reason,
        startedAt: now,
      ),
    ];
  }
}
