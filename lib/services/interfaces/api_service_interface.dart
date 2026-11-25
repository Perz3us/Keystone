// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/internet_reachability.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/traceroute_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/dns_lookup_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/routing_neighbor_info.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dnsmasq_service_result.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

enum AuthStatus { success, invalidCredentials, unreachable, unknownError }

class AuthResult {
  final AuthStatus status;
  final String? token;
  final bool actualUseHttps;
  final String? errorMessage;

  const AuthResult({
    required this.status,
    this.token,
    this.actualUseHttps = false,
    this.errorMessage,
  });

  factory AuthResult.success(String token, {bool actualUseHttps = false}) =>
      AuthResult(
        status: AuthStatus.success,
        token: token,
        actualUseHttps: actualUseHttps,
      );

  factory AuthResult.invalidCredentials([String? message]) => AuthResult(
    status: AuthStatus.invalidCredentials,
    errorMessage: message ?? 'Invalid username or password',
  );

  factory AuthResult.unreachable([String? message]) => AuthResult(
    status: AuthStatus.unreachable,
    errorMessage:
        message ??
        'Router unreachable. Check network connection and IP address.',
  );

  factory AuthResult.unknownError(String message) =>
      AuthResult(status: AuthStatus.unknownError, errorMessage: message);

  bool get isSuccess => status == AuthStatus.success;
}

class SetPasswordRpcResponse {
  final bool isSuccess;
  final bool isRejected;
  final bool isNetworkError;
  final String? message;

  const SetPasswordRpcResponse.success()
    : isSuccess = true,
      isRejected = false,
      isNetworkError = false,
      message = null;

  const SetPasswordRpcResponse.rejected([this.message])
    : isSuccess = false,
      isRejected = true,
      isNetworkError = false;

  const SetPasswordRpcResponse.networkError([this.message])
    : isSuccess = false,
      isRejected = false,
      isNetworkError = true;
}

abstract class IApiService {
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<String> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  });
  Future<dynamic> callSimple(
    String object,
    String method,
    Map<String, dynamic> params,
  );
  Future<bool> reboot(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<Map<String, dynamic>?> fetchWireGuardPeers({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAssociatedStations();
  Future<List<String>> fetchAssociatedStationsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interface,
    BuildContext? context,
  });
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<dynamic> uciSet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    required String section,
    required Map<String, String> values,
    BuildContext? context,
  });
  Future<List<String>> fetchNetworkInterfaces({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });
  Future<dynamic> uciCommit(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });
  Future<dynamic> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  });
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  });
  Future<bool> uciConfirm(String ipAddress, String sysauth, bool useHttps);
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  });
  Future<dynamic> systemExec(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    BuildContext? context,
  });
  bool execSucceeded(dynamic res);
  Future<bool> disconnectWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  });
  Future<bool> setSsidEnabled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String ifaceSection,
    required bool enabled,
    BuildContext? context,
  });
  Future<bool> toggleWirelessRadio(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required bool enabled,
    BuildContext? context,
  });
  Future<bool> updateWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  });
  Future<bool> revertWirelessInterfaceConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  });
  Future<bool> updateWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> values,
    List<String>? deleteOptions,
    BuildContext? context,
  });
  Future<bool> revertWirelessRadioConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    required Map<String, String> priorValues,
    BuildContext? context,
  });
  Future<bool> addWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    Map<String, String>? extraOptions,
    BuildContext? context,
  });
  Future<bool> deleteWirelessInterface(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  });
  Future<bool> updateInterfaceDhcpConfig(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String interface,
    required Map<String, dynamic> values,
    BuildContext? context,
  });
  Future<bool> provisionGuestNetwork(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  });
  Future<bool> setWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  });
  Future<bool> confirmWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> revertWifiAccessControl(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required Map<String, List<String>> maclistByIface,
    required Map<String, String> macfilterByIface,
    BuildContext? context,
  });
  Future<bool> autoFixPermissions(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> manageServiceAction(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String serviceName,
    required String action,
    BuildContext? context,
  });
  Future<bool> pauseClientInternet(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required bool pause,
    BuildContext? context,
  });
  Future<bool> addFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  });
  Future<bool> updateFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallPortForwarding portForward,
    BuildContext? context,
  });
  Future<bool> deleteFirewallPortForward(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  });
  Future<bool> addFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  });
  Future<bool> updateFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required FirewallCustomRule rule,
    BuildContext? context,
  });
  Future<bool> deleteFirewallCustomRule(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionKey,
    BuildContext? context,
  });
  Future<bool> reorderFirewallCustomRules(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String targetSectionKey,
    required String siblingSectionKey,
    required List<String> expectedRuleOrder,
    BuildContext? context,
  });
  Future<bool> applyPerDeviceNetworkAccessPolicy(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    BuildContext? context,
  });
  Future<bool> applyClientSpeedLimits(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<ClientSpeedLimit> limits,
    required RouterCapabilities capabilities,
    BuildContext? context,
  });
  Future<Set<int>> discoverManagementPorts(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> banWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  });
  Future<bool> unbanWirelessClient(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  });
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> addStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  });
  Future<bool> deleteStaticLease(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  });
  Future<bool> refreshClientConnection(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String macAddress,
    BuildContext? context,
  });
  Future<int> deleteUnusedDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> macsToFlush,
    BuildContext? context,
  });
  Future<Map<String, String?>> fetchPublicIps(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> forceRefreshDhcpLeases(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> saveCronJobs(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required List<String> cronLines,
    BuildContext? context,
  });
  Future<bool> saveDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  });
  Future<bool> deleteDdnsInstance(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String instanceName,
    BuildContext? context,
  });
  Future<DdnsValidationResult> testDdnsConfiguration(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required DdnsInstance instance,
    BuildContext? context,
  });
  Future<bool> toggleGlobalDdns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  });
  Future<bool> saveSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required SqmQueue queue,
    BuildContext? context,
  });
  Future<bool> deleteSqmQueue(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String sectionName,
    BuildContext? context,
  });
  Future<bool> toggleSqmService(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required bool enable,
    BuildContext? context,
  });

  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });

  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  });

  Future<int> migrateAnonymousWirelessSections(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> applyParentalProfileDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  });

  Future<List<ParentalProfile>?> fetchParentalProfiles(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> saveParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required ParentalProfile profile,
    BuildContext? context,
  });

  Future<bool> deleteParentalProfile(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String profileId,
    BuildContext? context,
  });

  Future<bool> installNativeTemperatureHandler(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<PingResult> executePing(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int count = 3,
    int timeoutSec = 2,
    bool isIpv6 = false,
    BuildContext? context,
  });

  Future<TracerouteResult> executeTraceroute(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String target,
    int maxHops = 15,
    int timeoutSec = 1,
    bool isIpv6 = false,
    BuildContext? context,
  });

  Future<DnsLookupResult> executeDnsLookup(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String host,
    String? server,
    BuildContext? context,
  });

  Future<InternetReachability> testInternetReachability(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<List<RouteEntry>> fetchRoutingTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<List<NeighborEntry>> fetchNeighborTable(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<ConntrackInfo?> fetchConntrackInfo(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<DiagnosticReport> generateFullDiagnosticReport(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<FlushDnsResult> flushDns(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<DnsmasqServiceResult> reloadDnsmasq(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<LogFetchResult> fetchSyslog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  });

  Future<LogFetchResult> fetchKernelLog(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    int lines = 200,
    BuildContext? context,
  });

  Future<String?> execDirectCgi(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String command,
    List<String>? params,
    int stderr = 0,
    BuildContext? context,
  });

  Future<List<RealtimeTrafficPoint>> fetchRealtimeStats(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String mode,
    String? device,
    BuildContext? context,
  });

  Future<bool> checkNlbwmonInstalled(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<NlbwmonReport?> fetchNlbwmonData(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String groupBy = 'mac',
    String? period,
    BuildContext? context,
  });

  Future<List<String>> fetchNlbwmonPeriods(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> setRouterHostname(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String newHostname, {
    BuildContext? context,
  });

  Future<List<String>> getDnsmasqBlockedDomains(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    BuildContext? context,
  });

  Future<bool> addDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  });

  Future<bool> removeDnsmasqBlockedDomain(
    String ipAddress,
    String sysauth,
    bool useHttps,
    String domain, {
    BuildContext? context,
  });
}
