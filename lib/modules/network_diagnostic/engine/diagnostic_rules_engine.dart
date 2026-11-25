// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/diagnostic_capabilities.dart';
import '../models/diagnostic_confidence.dart';
import '../models/diagnostic_scope.dart';
import '../models/diagnostic_status.dart';
import '../models/diagnostic_test_result.dart';
import '../models/root_cause_finding.dart';

class DiagnosticRulesEngine {
  const DiagnosticRulesEngine();

  List<RootCauseFinding> analyze({
    required List<DiagnosticTestResult> testResults,
    required DiagnosticCapabilities capabilities,
  }) {
    final findings = <RootCauseFinding>[];

    final map = {for (final t in testResults) t.id: t};

    final mgmtApi = map['router_management_api'];
    final uplink = map['wan_interface_state'];
    final gateway = map['gateway_reachability'];
    final defaultRoute = map['default_route_verification'];
    final dns = map['dns_resolution'];
    final ipv4Ext = map['ipv4_external_reachability'];
    final ipv6Ext = map['ipv6_external_reachability'];
    final mtu = map['path_mtu_check'];
    final forwarding = map['client_forwarding_policy'];

    if (mgmtApi != null &&
        mgmtApi.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        const RootCauseFinding(
          id: 'router_api_unreachable',
          title: 'Router Management API Unreachable',
          description:
              'Keystone can\'t talk to the router. It may be off, restarting, or on a different network. The other checks couldn\'t run.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: ['The router didn\'t answer.'],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Check that this phone is on the router\'s Wi-Fi.',
            'Check that the router IP address and credentials are correct in Manage Routers.',
            'Check that the router is on.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.managementApi,
        ),
      );
      return findings;
    }

    if (uplink != null && uplink.status == DiagnosticStatus.failureConfirmed) {
      final isPppoe = capabilities.wanProtocol == 'pppoe';
      final isDhcp = capabilities.wanProtocol == 'dhcp';

      if (isPppoe) {
        findings.add(
          RootCauseFinding(
            id: 'uplink_pppoe_disconnected',
            title: 'PPPoE Uplink Disconnected',
            description:
                'The active WAN interface (${capabilities.activeWanInterface ?? 'pppoe-wan'}) is configured for PPPoE, but it hasn\'t connected. The username or password may be wrong, the modem may not be in bridge mode, or your provider may be down.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Check the PPPoE username and password.',
              'Check that the modem is in bridge mode and connected.',
              'Ask your provider if the line is working.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      } else if (isDhcp) {
        findings.add(
          RootCauseFinding(
            id: 'uplink_dhcp_no_lease',
            title: 'No WAN DHCP Lease Acquired',
            description:
                'The active WAN interface (${capabilities.activeWanInterface ?? 'wan'}) is set to DHCP, but nothing gave it an address. Check the cable and the modem.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Check the Ethernet cable between the router\'s WAN port and the upstream modem/ONT.',
              'Turn the modem off and on, then wait 2 minutes.',
              'Ask your provider if it needs a VLAN or a certain MAC address.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      } else {
        findings.add(
          RootCauseFinding(
            id: 'uplink_interface_down',
            title: 'WAN Uplink Interface Down',
            description:
                'The router\'s primary WAN uplink interface (${capabilities.activeWanInterface ?? 'wan'}) reports down or disconnected. No alternate active uplink was detected.',
            status: DiagnosticStatus.failureConfirmed,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: uplink.evidence.facts,
            contradictoryEvidence: [],
            recommendedSteps: [
              'Check the physical network cable connected to the WAN port.',
              'Check that the modem is on.',
              'Review interface configuration under Interfaces.',
            ],
            actionType: FindingActionType.userIntervention,
            primaryScope: DiagnosticScope.routerUplink,
          ),
        );
      }
    }

    if (defaultRoute != null &&
        defaultRoute.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        RootCauseFinding(
          id: 'missing_default_route',
          title: 'Missing Default Kernel Route',
          description:
              'No active default gateway route (0.0.0.0/0) was found, so the router doesn\'t know where to send internet traffic.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: defaultRoute.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'Check that the WAN interface has a gateway.',
            'With several WANs or policy routing, check the metrics and rules.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.routing,
        ),
      );
    }

    final isIpv4Online =
        ipv4Ext != null && ipv4Ext.status == DiagnosticStatus.healthy;
    final isDnsFailing =
        dns != null &&
        (dns.status == DiagnosticStatus.failureConfirmed ||
            dns.status == DiagnosticStatus.degraded);

    if (isIpv4Online && isDnsFailing) {
      findings.add(
        RootCauseFinding(
          id: 'dns_resolution_failure_direct_ip_working',
          title: 'DNS Resolution Failure (Direct Internet IP is Working)',
          description:
              'The router can reach external internet IP addresses directly (e.g. 1.1.1.1, 8.8.8.8), but names don\'t resolve. Websites won\'t open by name.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            ...dns.evidence.facts,
            'Direct ICMP echo to external public IPs succeeded.',
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Check configured DNS upstream resolvers in DHCP & DNS settings.',
            'If you set your own DNS servers, check that they answer.',
            'If you use AdGuard Home or NextDNS, check that it\'s running.',
            'Clear the name cache and try again.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.dns,
        ),
      );
    }

    final isIpv4IcmpDown =
        ipv4Ext != null &&
        (ipv4Ext.status == DiagnosticStatus.degraded ||
            ipv4Ext.status == DiagnosticStatus.failureConfirmed);
    final isDnsWorking = dns != null && dns.status == DiagnosticStatus.healthy;

    if (isIpv4IcmpDown && isDnsWorking) {
      findings.add(
        RootCauseFinding(
          id: 'icmp_blocked_dns_operational',
          title: 'Internet Works (Pings Are Blocked)',
          description:
              'Names resolve but pings get no answer. Many providers block pings. Your internet works.',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [...dns.evidence.facts, 'DNS lookups worked.'],
          contradictoryEvidence: [...ipv4Ext.evidence.facts],
          recommendedSteps: [
            'Nothing to do. Blocked pings don\'t affect websites or apps.',
          ],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.ipv4,
        ),
      );
    }

    final isGatewayUnreachable =
        gateway != null &&
        (gateway.status == DiagnosticStatus.degraded ||
            gateway.status == DiagnosticStatus.failureConfirmed ||
            gateway.status == DiagnosticStatus.suspected);

    if (isGatewayUnreachable && (isIpv4Online || isDnsWorking)) {
      findings.add(
        RootCauseFinding(
          id: 'gateway_icmp_suppressed_external_ok',
          title: 'Gateway Ping Unresponsive (External Internet Working)',
          description:
              'Your provider\'s gateway ignores pings, but the router can reach the internet.',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            'External internet destinations responded normally.',
          ],
          contradictoryEvidence: [...gateway.evidence.facts],
          recommendedSteps: ['Nothing to do. Many providers do this.'],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.addressing,
        ),
      );
    }

    final isGatewayDown =
        gateway != null && gateway.status == DiagnosticStatus.failureConfirmed;
    final isAllExternalDown =
        ipv4Ext != null &&
        ipv4Ext.status == DiagnosticStatus.failureConfirmed &&
        !isDnsWorking;

    if (uplink != null &&
        uplink.status == DiagnosticStatus.healthy &&
        isAllExternalDown) {
      final confidence = isGatewayDown
          ? DiagnosticConfidence.high
          : DiagnosticConfidence.moderate;

      findings.add(
        RootCauseFinding(
          id: 'upstream_isp_outage',
          title: 'Upstream Internet Outage / Unreachable',
          description:
              'The router\'s WAN interface is connected with an assigned IP address, but no external destinations (Cloudflare, Google, Quad9, root DNS) could be reached. The problem is probably at your provider.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: confidence,
          supportingEvidence: [
            'The WAN is up and has an address.',
            if (gateway != null) ...gateway.evidence.facts,
            ...ipv4Ext.evidence.facts,
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Restart the modem.',
            'Check if your provider has an outage.',
            'Check that your account is paid and active.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.ipv4,
        ),
      );
    }

    if (capabilities.isIpv6Configured &&
        ipv6Ext != null &&
        (ipv6Ext.status == DiagnosticStatus.failureConfirmed ||
            ipv6Ext.status == DiagnosticStatus.degraded) &&
        isIpv4Online) {
      findings.add(
        RootCauseFinding(
          id: 'ipv6_degraded_ipv4_healthy',
          title: 'IPv6 Isn\'t Working (IPv4 Is Fine)',
          description:
              'IPv4 works but IPv6 doesn\'t. Devices may be slow to connect while they try IPv6 first.',
          status: DiagnosticStatus.degraded,
          confidence: DiagnosticConfidence.moderate,
          supportingEvidence: [
            'IPv4 reachability passed all checks.',
            ...ipv6Ext.evidence.facts,
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'Check IPv6 prefix delegation and router advertisements under Interfaces.',
            'Ask your provider if it supports IPv6.',
            'If it doesn\'t, turn IPv6 off on the WAN.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.ipv6,
        ),
      );
    }

    if (!capabilities.isIpv6Configured &&
        (ipv6Ext == null ||
            ipv6Ext.status == DiagnosticStatus.notApplicable ||
            ipv6Ext.status == DiagnosticStatus.healthy)) {
      if (isIpv4Online) {
        findings.add(
          const RootCauseFinding(
            id: 'ipv6_not_configured',
            title: 'IPv4-Only Network (IPv6 Not Configured)',
            description: 'This network only uses IPv4. That\'s normal.',
            status: DiagnosticStatus.healthy,
            confidence: DiagnosticConfidence.high,
            supportingEvidence: [
              'No global unicast IPv6 address found on active interfaces.',
            ],
            contradictoryEvidence: [],
            recommendedSteps: [],
            actionType: FindingActionType.informational,
            primaryScope: DiagnosticScope.ipv6,
          ),
        );
      }
    }

    if (isIpv4Online &&
        forwarding != null &&
        forwarding.status == DiagnosticStatus.failureConfirmed) {
      findings.add(
        RootCauseFinding(
          id: 'client_forwarding_firewall_blocked',
          title: 'Router Has Internet, but LAN Client Forwarding is Blocked',
          description:
              'The router has internet, but the firewall stops your devices from using it.',
          status: DiagnosticStatus.failureConfirmed,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: forwarding.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'In Firewall, allow forwarding from the "lan" zone to the "wan" zone.',
            'Turn on masquerading for the WAN zone.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.clientForwarding,
        ),
      );
    }

    if (isIpv4Online &&
        (forwarding == null || forwarding.status == DiagnosticStatus.healthy) &&
        findings.where((f) => f.status.isProblem).isEmpty) {
      findings.add(
        const RootCauseFinding(
          id: 'router_healthy_client_unverified',
          title: 'The Router Has Internet',
          description:
              'The router has internet. If one device doesn\'t, the problem is on that device, like a weak Wi-Fi signal or a wrong fixed address.',
          status: DiagnosticStatus.healthy,
          confidence: DiagnosticConfidence.high,
          supportingEvidence: [
            'All the router\'s checks passed.',
            'The firewall lets devices out.',
          ],
          contradictoryEvidence: [],
          recommendedSteps: [
            'If one device has trouble, check its address and DNS settings.',
            'Check its Wi-Fi signal.',
          ],
          actionType: FindingActionType.informational,
          primaryScope: DiagnosticScope.clientForwarding,
        ),
      );
    }

    if (mtu != null && mtu.status == DiagnosticStatus.degraded) {
      findings.add(
        RootCauseFinding(
          id: 'path_mtu_fragmentation_issue',
          title: 'Large Packets Don\'t Get Through',
          description:
              'Large packets get lost on the way. Pages may load slowly and VPNs may stall.',
          status: DiagnosticStatus.degraded,
          confidence: DiagnosticConfidence.moderate,
          supportingEvidence: mtu.evidence.facts,
          contradictoryEvidence: [],
          recommendedSteps: [
            'Enable MSS clamping in Firewall settings (iptables/nftables mssfix).',
            'If using PPPoE, set the MTU to 1492.',
          ],
          actionType: FindingActionType.userIntervention,
          primaryScope: DiagnosticScope.pathMtu,
        ),
      );
    }

    return findings;
  }

  (DiagnosticStatus, String) synthesizeOverall({
    required List<DiagnosticTestResult> testResults,
    required List<RootCauseFinding> findings,
  }) {
    if (testResults.isEmpty) {
      return (
        DiagnosticStatus.notTested,
        'Nothing checked yet. Tap "Run Diagnostics" to start.',
      );
    }

    final mgmtApi = testResults.firstWhere(
      (t) => t.id == 'router_management_api',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.managementApi,
        status: DiagnosticStatus.notTested,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );
    if (mgmtApi.status == DiagnosticStatus.failureConfirmed) {
      return (DiagnosticStatus.failureConfirmed, 'Can\'t talk to the router.');
    }

    final criticalProblems = findings.where(
      (f) => f.status == DiagnosticStatus.failureConfirmed,
    );
    if (criticalProblems.isNotEmpty) {
      final top = criticalProblems.first;
      return (DiagnosticStatus.failureConfirmed, top.title);
    }

    final degradedProblems = findings.where(
      (f) =>
          f.status == DiagnosticStatus.degraded ||
          f.status == DiagnosticStatus.suspected,
    );
    if (degradedProblems.isNotEmpty) {
      final top = degradedProblems.first;
      return (top.status, top.title);
    }

    final ipv4 = testResults.firstWhere(
      (t) => t.id == 'ipv4_external_reachability',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.ipv4,
        status: DiagnosticStatus.inconclusive,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );
    final dns = testResults.firstWhere(
      (t) => t.id == 'dns_resolution',
      orElse: () => DiagnosticTestResult(
        id: '',
        title: '',
        scope: DiagnosticScope.dns,
        status: DiagnosticStatus.inconclusive,
        confidence: DiagnosticConfidence.low,
        explanation: '',
        whyItMatters: '',
        startedAt: DateTime.now(),
      ),
    );

    if (ipv4.status == DiagnosticStatus.healthy &&
        dns.status == DiagnosticStatus.healthy) {
      return (DiagnosticStatus.healthy, 'The internet works.');
    }

    if (testResults.any((t) => t.status == DiagnosticStatus.failureConfirmed)) {
      return (DiagnosticStatus.failureConfirmed, 'At least one check failed.');
    }
    if (testResults.any((t) => t.status == DiagnosticStatus.degraded)) {
      return (DiagnosticStatus.degraded, 'The internet partly works.');
    }

    return (
      DiagnosticStatus.inconclusive,
      'The checks didn\'t give a clear answer. See each one below.',
    );
  }
}
