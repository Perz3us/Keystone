// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/adguard_home/controllers/adguard_controller.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_api_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/models/adguard_models.dart';
import 'package:yet_another_luci_app/modules/adguard_home/services/adguard_api_service.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/configure_router_dns_dialog.dart';
import 'package:yet_another_luci_app/modules/adguard_home/widgets/revert_router_dns_dialog.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';

class OrchestrationTestMockAdGuardApiService implements IAdGuardApiService {
  @override
  final String routerId;

  @override
  String get instanceId => 'local_$routerId';

  @override
  Future<AdGuardConnectionStatus> testConnection({
    AdGuardCredentials? credentials,
  }) async => AdGuardConnectionStatus.authenticated;

  AdGuardStatus? status;
  AdGuardStats? stats;
  AdGuardFilteringStatus filtering = const AdGuardFilteringStatus(
    enabled: true,
    filterLists: [],
    userRules: [],
    totalRulesCount: 100,
  );
  List<String> upstreamDns;

  OrchestrationTestMockAdGuardApiService({
    required this.routerId,
    this.status,
    this.stats,
    this.upstreamDns = const ['1.1.1.1', '8.8.8.8'],
  });

  @override
  AdGuardCredentials? get activeCredentials => null;

  @override
  bool get isAuthenticated => true;

  @override
  bool get isAuthRequired => false;

  @override
  void setCredentials(AdGuardCredentials? credentials) {}

  AdGuardApiException? statusError;

  @override
  Future<AdGuardApiResult<AdGuardStatus>> getStatus({
    bool forceProbe = false,
    bool allowFallbackToRouterCredentials = false,
    AdGuardCredentials? routerCredentials,
  }) async {
    if (statusError != null) {
      return AdGuardApiResult.failure(statusError!);
    }
    if (status != null) {
      return AdGuardApiResult.success(status!);
    }
    return AdGuardApiResult.failure(
      const AdGuardApiException(
        type: AdGuardApiErrorType.unknown,
        message: 'Status unavailable',
      ),
    );
  }

  @override
  Future<AdGuardApiResult<AdGuardStats>> getStats({Duration? recent}) async {
    if (stats != null) {
      return AdGuardApiResult.success(stats!);
    }
    return AdGuardApiResult.success(
      const AdGuardStats(
        numDnsQueries: 0,
        numBlockedFiltering: 0,
        numReplacedSafebrowsing: 0,
        numReplacedSafesearch: 0,
        numReplacedParental: 0,
        avgProcessingTime: 0.0,
        topQueriedDomains: [],
        topBlockedDomains: [],
        topClients: [],
        dnsQueriesTrend: [],
        blockedFilteringTrend: [],
        blockRatePercentage: 0.0,
      ),
    );
  }

  @override
  Future<AdGuardApiResult<AdGuardFilteringStatus>> getFilteringStatus() async {
    return AdGuardApiResult.success(filtering);
  }

  @override
  Future<AdGuardApiResult<List<String>>> getUpstreamDns() async {
    return AdGuardApiResult.success(upstreamDns);
  }

  @override
  Future<AdGuardApiResult<List<AdGuardClient>>> getClients() async {
    return AdGuardApiResult.success(const []);
  }

  @override
  Future<AdGuardApiResult<bool>> addFilterList({
    required String name,
    required String url,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> setFilterList({
    required String url,
    required String name,
    required String newUrl,
    required bool enabled,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> removeFilterList({
    required String url,
    required bool whitelist,
  }) async => AdGuardApiResult.success(true);

  @override
  Future<AdGuardApiResult<bool>> refreshFilterLists({bool? whitelist}) async =>
      AdGuardApiResult.success(true);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OrchestrationTestMockAuthService implements IAuthService {
  @override
  String? sysauth = 'test_sysauth_token';

  @override
  String? ipAddress = '192.168.1.1';

  @override
  bool useHttps = false;

  @override
  bool isAuthenticated = true;

  @override
  int authEpoch = 1;

  @override
  int startPasswordTransition() => 2;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class OrchestrationTestCallRecord {
  final String object;
  final String method;
  final Map<String, dynamic>? params;

  OrchestrationTestCallRecord({
    required this.object,
    required this.method,
    this.params,
  });
}

class OrchestrationTestTrackingLuciApiService implements IApiService {
  final List<OrchestrationTestCallRecord> callLog = [];
  final List<String> uciApplyLog = [];
  final List<String> uciConfirmLog = [];
  final List<String> uciRevertLog = [];

  bool applyResult = true;
  bool confirmResult = true;
  bool revertResult = true;
  bool reachabilityResult = true;
  bool readbackContainsTarget = true;
  bool readbackReturnsTargetForRevert = false;
  dynamic dhcpGetResponse;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    callLog.add(
      OrchestrationTestCallRecord(
        object: object,
        method: method,
        params: params != null ? Map<String, dynamic>.from(params) : null,
      ),
    );

    if (object == 'system' && method == 'board') {
      if (!reachabilityResult) {
        throw Exception('Simulated router reachability timeout');
      }
      return {
        'result': [
          0,
          {'board_name': 'test-router'},
        ],
      };
    }

    if (object == 'uci' && method == 'get') {
      if (params?['config'] == 'dhcp') {
        final section = params?['section'];
        if (section != null) {
          if (readbackReturnsTargetForRevert) {
            return {
              'result': [
                0,
                {
                  'values': {
                    '.type': 'dnsmasq',
                    'server': ['127.0.0.1#53'],
                  },
                },
              ],
            };
          }
          if (!readbackContainsTarget) {
            return {
              'result': [
                0,
                {
                  'values': {
                    '.type': 'dnsmasq',
                    'server': ['8.8.8.8'],
                  },
                },
              ],
            };
          }
          final lastSet = callLog.reversed.firstWhere(
            (c) =>
                c.object == 'uci' &&
                c.method == 'set' &&
                c.params?['config'] == 'dhcp',
            orElse: () => OrchestrationTestCallRecord(object: '', method: ''),
          );
          if (lastSet.params?['values']?['server'] != null) {
            return {
              'result': [
                0,
                {
                  'values': {
                    '.type': 'dnsmasq',
                    'server': lastSet.params!['values']['server'],
                  },
                },
              ],
            };
          }
          return {
            'result': [
              0,
              {
                'values': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            ],
          };
        }
        if (dhcpGetResponse != null) {
          return dhcpGetResponse;
        }
        return {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['1.1.1.1'],
                },
              },
            },
          ],
        };
      }
    }

    if (object == 'uci' && method == 'set') {
      return {
        'result': [0],
      };
    }

    return {'result': []};
  }

  @override
  Future<bool> uciApply(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    bool rollback = true,
    int timeout = 30,
  }) async {
    uciApplyLog.add('uciApply(rollback: $rollback, timeout: $timeout)');
    return applyResult;
  }

  @override
  Future<bool> uciConfirm(
    String ipAddress,
    String sysauth,
    bool useHttps,
  ) async {
    uciConfirmLog.add('uciConfirm()');
    return confirmResult;
  }

  @override
  Future<bool> uciRevert(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String config,
    BuildContext? context,
  }) async {
    uciRevertLog.add('uciRevert(config: $config)');
    return revertResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdGuardController createController(
  ProviderContainer container,
  String routerId, {
  IAdGuardApiService? apiServiceOverride,
  IApiService? luciApiServiceOverride,
  IAuthService? authServiceOverride,
  RouterScopedOperationQueue? operationQueueOverride,
  AdGuardInstanceProfile? initialProfile,
}) {
  final controller = AdGuardController(
    container.read(adguardControllerProvider(routerId).notifier).ref,
    routerId,
    apiServiceOverride: apiServiceOverride,
    luciApiServiceOverride: luciApiServiceOverride,
    authServiceOverride: authServiceOverride,
    operationQueueOverride: operationQueueOverride,
    initialProfile: initialProfile,
  );
  controller.setPollingInterval(AdGuardPollingInterval.off);
  return controller;
}

Widget buildTestApp({required Widget child}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return null;
        });
  });

  group('AdGuardDnsRoutingStatus Inference', () {
    test(
      'unknown: returns unknown when topology data is absent or unverified',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: null,
          dnsmasqPort: 53,
          dnsmasqServers: const [],
          hasDnatRedirect: false,
          adguardDnsAddresses: const [],
          isDnsRunning: false,
          isApiReachable: false,
          routerIp: '192.168.1.1',
        );
        expect(topology.routingStatus, equals(AdGuardDnsRoutingStatus.unknown));
        expect(topology.isClientUsageVerified, isFalse);
      },
    );

    test(
      'apiReachableOnly: returns apiReachableOnly when service is not running and no forwarders',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 53,
          dnsmasqServers: const ['1.1.1.1'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: false,
          isApiReachable: true,
          routerIp: '192.168.1.1',
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.apiReachableOnly),
        );
        expect(topology.isClientUsageVerified, isFalse);
      },
    );

    test(
      'serviceRunningOnly: returns serviceRunningOnly when AGH is running but router does not forward and no clients query',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 5353,
          dnsmasqPort: 53,
          dnsmasqServers: const ['1.1.1.1', '8.8.8.8'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.serviceRunningOnly),
        );
        expect(topology.isClientUsageVerified, isFalse);
      },
    );

    test(
      'routerForwardingUnverified: returns routerForwardingUnverified when router forwards but 0 queries in stats',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          totalQueries: 0,
          topClients: const [],
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.routerForwardingUnverified),
        );
        expect(topology.isClientUsageVerified, isFalse);
      },
    );

    test(
      'routerForwardingVerified: returns routerForwardingVerified when router forwards and queries originate only from router/loopback',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          totalQueries: 250,
          topClients: const [
            AdGuardTopItem(identifier: '127.0.0.1', count: 200),
            AdGuardTopItem(identifier: '192.168.1.1', count: 50),
          ],
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.routerForwardingVerified),
        );
        expect(topology.isClientUsageVerified, isFalse);
        expect(topology.clientQueriesObserved, equals(0));
      },
    );

    test(
      'clientUsageVerified: returns clientUsageVerified when distinct client devices query AGH',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['192.168.1.1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          totalQueries: 500,
          topClients: const [
            AdGuardTopItem(identifier: '192.168.1.105', count: 300),
            AdGuardTopItem(identifier: '192.168.1.120', count: 200),
          ],
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.clientUsageVerified),
        );
        expect(topology.isClientUsageVerified, isTrue);
        expect(topology.clientQueriesObserved, equals(500));
      },
    );

    test(
      'externalStandalone: returns externalStandalone for external instances where router does not forward and clients query directly',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 53,
          dnsmasqServers: const ['1.1.1.1'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['192.168.1.50'],
          isDnsRunning: true,
          isApiReachable: true,
          instanceType: AdGuardInstanceType.externalHost,
          targetHost: '192.168.1.50',
          routerIp: '192.168.1.1',
          totalQueries: 120,
          topClients: const [
            AdGuardTopItem(identifier: '192.168.1.110', count: 120),
          ],
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.externalStandalone),
        );
        expect(topology.isClientUsageVerified, isFalse);
      },
    );

    test(
      'misconfiguredOrUnavailable: returns misconfiguredOrUnavailable on loop detection or port conflict',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 53,
          dnsmasqServers: const ['1.1.1.1'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: true,
          isApiReachable: true,
          instanceType: AdGuardInstanceType.localRouter,
          routerIp: '192.168.1.1',
          portConflict: true,
          portConflictReason:
              'Port conflict detected: both AdGuard and dnsmasq are configured on port 53.',
        );
        expect(
          topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.misconfiguredOrUnavailable),
        );
        expect(topology.misconfigurationReason, isNotNull);
        expect(topology.misconfigurationReason, contains('Port conflict'));
      },
    );

    test(
      'invalidates verified topology to unknown/unverified on subsequent API failure without clearing router forwarders',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'port': '53',
                  'server': ['127.0.0.1#5353'],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_stale_router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
          stats: const AdGuardStats(
            numDnsQueries: 25,
            numBlockedFiltering: 2,
            numReplacedSafebrowsing: 0,
            numReplacedSafesearch: 0,
            numReplacedParental: 0,
            avgProcessingTime: 0.5,
            topQueriedDomains: [],
            topBlockedDomains: [],
            topClients: [
              AdGuardTopItem(identifier: '192.168.1.105', count: 20),
            ],
            dnsQueriesTrend: [],
            blockedFilteringTrend: [],
            blockRatePercentage: 8.0,
          ),
        );

        final controller = createController(
          container,
          'test_stale_router',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh(forceTopologyProbe: true);
        expect(
          controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.authenticated),
        );
        expect(
          controller.state.topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.clientUsageVerified),
        );
        expect(controller.state.topology.isClientUsageVerified, isTrue);
        expect(controller.state.capabilities.isApiReachable, isTrue);
        expect(
          controller.state.topology.forwarders,
          equals(['127.0.0.1#5353']),
        );

        mockAdGuard.status = null;
        mockAdGuard.statusError = const AdGuardApiException(
          type: AdGuardApiErrorType.networkFailure,
          message: 'Connection refused',
        );

        await controller.refresh();

        expect(
          controller.state.connectionStatus,
          equals(AdGuardConnectionStatus.apiUnreachable),
        );
        expect(
          controller.state.topology.routingStatus,
          equals(AdGuardDnsRoutingStatus.unknown),
        );
        expect(controller.state.topology.isClientUsageVerified, isFalse);
        expect(controller.state.topology.clientQueriesObserved, equals(0));
        expect(controller.state.capabilities.isApiReachable, isFalse);

        expect(
          controller.state.topology.forwarders,
          equals(['127.0.0.1#5353']),
        );
        expect(
          controller.state.topology.statusEvidence,
          contains(
            'Router is configured to forward DNS to AdGuard in UCI, but AdGuard API is unreachable',
          ),
        );
        expect(
          controller.state.topology.statusEvidence,
          isNot(contains('DNS service stopped')),
        );
      },
    );
  });

  group('Ipv6DnsStatus Conservative Detection', () {
    test(
      'noBypassDetected: odhcpd advertises router IP or local AGH as DNS',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1', '::1', 'fd00::1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          odhcpdIpv6Dns: const ['fd00::1'],
          raDnsEnabled: true,
        );
        expect(topology.ipv6Status, equals(Ipv6DnsStatus.noBypassDetected));
      },
    );

    test(
      'externalAdvertisementBypass: odhcpd advertises upstream public IPv6 DNS',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1', '::1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          odhcpdIpv6Dns: const ['2001:4860:4860::8888'],
          raDnsEnabled: true,
        );
        expect(
          topology.ipv6Status,
          equals(Ipv6DnsStatus.externalAdvertisementBypass),
        );
        expect(topology.ipv6Evidence, contains('2001:4860:4860::8888'));
      },
    );

    test(
      'unsupportedIpv6Listener: AGH lacks IPv6 listener while router has IPv6 enabled',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          odhcpdIpv6Dns: const [],
          raDnsEnabled: true,
        );
        expect(
          topology.ipv6Status,
          equals(Ipv6DnsStatus.unsupportedIpv6Listener),
        );
      },
    );

    test(
      'unableToVerify: returns unableToVerify when odhcpd data is absent/unparseable',
      () {
        final topology = AdGuardDnsTopology.infer(
          adguardDnsPort: 53,
          dnsmasqPort: 5353,
          dnsmasqServers: const ['127.0.0.1#53'],
          hasDnatRedirect: false,
          adguardDnsAddresses: const ['127.0.0.1', '::1'],
          isDnsRunning: true,
          isApiReachable: true,
          routerIp: '192.168.1.1',
          odhcpdIpv6Dns: const [],
          raDnsEnabled: null,
          isIndeterminateIpv6: true,
        );
        expect(topology.ipv6Status, equals(Ipv6DnsStatus.unableToVerify));
      },
    );
  });

  group('Normalized Loop Detection', () {
    test('detects loop when upstream matches router IP directly', () {
      final res = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['192.168.1.1'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res.loopDetected, isTrue);
      expect(res.loopReason, contains('192.168.1.1'));
    });

    test('detects loop when upstream specifies port or protocol scheme', () {
      final res1 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['udp://192.168.1.1:53'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res1.loopDetected, isTrue);

      final res2 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['tcp://127.0.0.1:53'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res2.loopDetected, isTrue);
      expect(res2.isWarningOnly, isFalse);

      final res2Custom = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['tcp://127.0.0.1:5353'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res2Custom.loopDetected, isFalse);
      expect(res2Custom.isWarningOnly, isTrue);

      final res3 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['localhost'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res3.loopDetected, isTrue);

      final res4 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['[::1]:53'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res4.loopDetected, isTrue);
    });

    test(
      'detects mutual conditional-forwarding loop when AdGuard conditional upstream targets router resolver',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/lan/]192.168.1.1:53', '8.8.8.8'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isTrue);
        expect(res1.isWarningOnly, isFalse);
        expect(res1.loopReason, contains('circular forwarding loop'));
        expect(res1.loopReason, contains('lan'));

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['/lan/192.168.1.1', '8.8.8.8'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isTrue);
        expect(res2.isWarningOnly, isFalse);
        expect(res2.loopReason, contains('circular forwarding loop'));

        final res3 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['/lan/127.0.0.1#53'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res3.loopDetected, isTrue);
        expect(res3.isWarningOnly, isFalse);

        final res4 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/lan/][2001:db8::1]:53'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8::1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res4.loopDetected, isTrue);
        expect(res4.isWarningOnly, isFalse);
      },
    );

    test(
      'allows valid independent conditional forwarders and reverse-DNS forwarders',
      () {
        final res = AdGuardController.detectForwardingLoop(
          adguardUpstreams: [
            '[/corp/]10.0.0.2:53',
            '[/in-addr.arpa/]10.0.0.2:53',
            '/sub.domain.com/10.0.0.3#53',
            '8.8.8.8',
          ],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res.loopDetected, isFalse);
        expect(res.loopReason, isNull);
      },
    );

    test(
      'surfaces advisory warning when conditional upstream targets local resolver on custom port',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/lan/]127.0.0.1:5335'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isFalse);
        expect(res1.isWarningOnly, isTrue);
        expect(
          res1.loopReason,
          contains('targets a local service on port 5335'),
        );

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/lan/][2001:db8::1]:5335'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8::1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isFalse);
        expect(res2.isWarningOnly, isTrue);
        expect(
          res2.loopReason,
          contains('targets a local service on port 5335'),
        );
      },
    );

    test('ignores block-only conditional upstreams', () {
      final res = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['[/blocked/]', '[/ads/]#', '8.8.8.8'],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res.loopDetected, isFalse);
      expect(res.loopReason, isNull);
    });

    test(
      'surfaces advisory warning for malformed conditional upstream rules',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/broken/unclosed', '8.8.8.8'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isFalse);
        expect(res1.isWarningOnly, isTrue);
        expect(res1.loopReason, contains('malformed'));

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['/malformed_no_second_slash', '8.8.8.8'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isFalse);
        expect(res2.isWarningOnly, isTrue);
        expect(res2.loopReason, contains('malformed'));
      },
    );

    test(
      'advertising Google IPv6 DNS in odhcpd does not trigger a false loop, while router interface IPv6 does',
      () {
        final resClean = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['2001:4860:4860::8888'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8::1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(resClean.loopDetected, isFalse);

        final resLoop = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[2001:db8::1]:53'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8::1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(resLoop.loopDetected, isTrue);
        expect(resLoop.isWarningOnly, isFalse);
      },
    );

    test(
      'extractInterfaceDumpIpv6Addresses extracts addresses from ubus dump',
      () {
        final mockDump = {
          'result': [
            0,
            {
              'interface': [
                {
                  'interface': 'wan',
                  'ipv4-address': [
                    {'address': '100.64.0.123'},
                  ],
                  'ipv6-address': <Map<String, dynamic>>[],
                },
                {
                  'interface': 'wan6',
                  'ipv6-address': [
                    {'address': '2001:db8::1', 'mask': 64},
                    {'address': 'FE80::1', 'mask': 64},
                  ],
                },
              ],
            },
          ],
        };

        final addrs = AdGuardController.extractInterfaceDumpIpv6Addresses(
          mockDump,
        );
        expect(addrs, contains('2001:db8::1'));
        expect(addrs, contains('fe80::1'));
        expect(addrs.length, equals(2));

        expect(
          AdGuardController.extractInterfaceDumpIpv6Addresses(null),
          isEmpty,
        );
        expect(
          AdGuardController.extractInterfaceDumpIpv6Addresses({}),
          isEmpty,
        );
        expect(
          AdGuardController.extractInterfaceDumpIpv6Addresses({
            'result': [1],
          }),
          isEmpty,
        );
      },
    );

    test(
      'parseDnsmasqServerRule parses standard, conditional, local-only, and malformed rules',
      () {
        final standard = AdGuardController.parseDnsmasqServerRule('1.1.1.1');
        expect(standard.isConditional, isFalse);
        expect(standard.targetHost, equals('1.1.1.1'));
        expect(standard.targetPort, equals(53));
        expect(standard.isMalformed, isFalse);

        final customPort = AdGuardController.parseDnsmasqServerRule(
          '127.0.0.1#5353',
        );
        expect(customPort.targetHost, equals('127.0.0.1'));
        expect(customPort.targetPort, equals(5353));

        final bracketedIpv6 = AdGuardController.parseDnsmasqServerRule(
          '[2001:db8::1]#5353',
        );
        expect(bracketedIpv6.targetHost, equals('2001:db8::1'));
        expect(bracketedIpv6.targetPort, equals(5353));

        final cond = AdGuardController.parseDnsmasqServerRule(
          '/lan/127.0.0.1#5353',
        );
        expect(cond.isConditional, isTrue);
        expect(cond.domains, equals('lan'));
        expect(cond.targetHost, equals('127.0.0.1'));
        expect(cond.targetPort, equals(5353));

        final localOnly = AdGuardController.parseDnsmasqServerRule('/local/');
        expect(localOnly.isConditional, isTrue);
        expect(localOnly.domains, equals('local'));
        expect(localOnly.isLocalOnly, isTrue);
        expect(localOnly.targetHost, isNull);

        final revDns = AdGuardController.parseDnsmasqServerRule(
          '/1.168.192.in-addr.arpa/10.0.0.2#53',
        );
        expect(revDns.isConditional, isTrue);
        expect(revDns.domains, equals('1.168.192.in-addr.arpa'));
        expect(revDns.targetHost, equals('10.0.0.2'));
        expect(revDns.targetPort, equals(53));

        final malformed = AdGuardController.parseDnsmasqServerRule('/broken');
        expect(malformed.isMalformed, isTrue);
      },
    );

    test(
      'parseAdguardConditionalUpstream parses AdGuard conditional rules',
      () {
        final std = AdGuardController.parseAdguardConditionalUpstream(
          '[/lan/]192.168.1.1:53',
        );
        expect(std.isConditional, isTrue);
        expect(std.domains, equals('lan'));
        expect(std.targetHost, equals('192.168.1.1'));
        expect(std.targetPort, equals(53));

        final customPort = AdGuardController.parseAdguardConditionalUpstream(
          '[/lan/]127.0.0.1:5335',
        );
        expect(customPort.targetHost, equals('127.0.0.1'));
        expect(customPort.targetPort, equals(5335));

        final ipv6 = AdGuardController.parseAdguardConditionalUpstream(
          '[/lan/][2001:db8::1]:53',
        );
        expect(ipv6.targetHost, equals('2001:db8::1'));
        expect(ipv6.targetPort, equals(53));

        final block = AdGuardController.parseAdguardConditionalUpstream(
          '[/blocked/]',
        );
        expect(block.isConditional, isTrue);
        expect(block.isBlockOnly, isTrue);

        final malformed = AdGuardController.parseAdguardConditionalUpstream(
          '[/broken/unclosed',
        );
        expect(malformed.isMalformed, isTrue);

        final catchAllBlock = AdGuardController.parseAdguardConditionalUpstream(
          '[/]',
        );
        expect(catchAllBlock.isConditional, isTrue);
        expect(catchAllBlock.domains, isNull);
        expect(catchAllBlock.isBlockOnly, isTrue);
        expect(catchAllBlock.isMalformed, isFalse);

        final catchAllUpstream =
            AdGuardController.parseAdguardConditionalUpstream('[/]1.1.1.1');
        expect(catchAllUpstream.isConditional, isTrue);
        expect(catchAllUpstream.domains, isNull);
        expect(catchAllUpstream.targetHost, equals('1.1.1.1'));
        expect(catchAllUpstream.targetPort, equals(53));
        expect(catchAllUpstream.isBlockOnly, isFalse);
        expect(catchAllUpstream.isMalformed, isFalse);

        final catchAllSlash = AdGuardController.parseAdguardConditionalUpstream(
          '//1.1.1.1',
        );
        expect(catchAllSlash.isConditional, isTrue);
        expect(catchAllSlash.domains, isNull);
        expect(catchAllSlash.targetHost, equals('1.1.1.1'));

        final slashBlock = AdGuardController.parseAdguardConditionalUpstream(
          '//',
        );
        expect(slashBlock.isConditional, isTrue);
        expect(slashBlock.domains, isNull);
        expect(slashBlock.isBlockOnly, isTrue);

        final singleSlashMalformed =
            AdGuardController.parseAdguardConditionalUpstream('/broken');
        expect(singleSlashMalformed.isMalformed, isTrue);
      },
    );

    test(
      'handles catch-all upstream rules combining with circular upstreams without crashing',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/]1.1.1.1', '192.168.1.1'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isTrue);
        expect(res1.isWarningOnly, isFalse);

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/]192.168.1.1:53'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isTrue);
        expect(res2.isWarningOnly, isFalse);

        final res3 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[/]', '1.1.1.1', '8.8.8.8'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res3.loopDetected, isFalse);
      },
    );

    test(
      'detects loop for uncompressed IPv6 addresses and normalizes representations',
      () {
        const compressedRouterIpv6 = ['2001:db8::1'];

        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['2001:db8:0:0:0:0:0:1'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: compressedRouterIpv6,
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isTrue);
        expect(res1.isWarningOnly, isFalse);

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[2001:db8:0:0:0:0:0:1]:53'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: compressedRouterIpv6,
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isTrue);

        final res3 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[2001:db8:0:0:0:0:0:1]:5353'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: compressedRouterIpv6,
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res3.loopDetected, isFalse);
        expect(res3.isWarningOnly, isTrue);

        final res4 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['2001:db8::1'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8:0:0:0:0:0:1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res4.loopDetected, isTrue);

        final res5 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['2001:db8:0:0:0:0:0:2'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: compressedRouterIpv6,
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res5.loopDetected, isFalse);
      },
    );

    test(
      'correctly handles non-conditional #port syntax without false flags',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['192.168.1.1#53'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isTrue);
        expect(res1.isWarningOnly, isFalse);

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['192.168.1.1#5353'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isFalse);
        expect(res2.isWarningOnly, isTrue);

        final res3 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[2001:db8::1]#53'],
          routerIp: '192.168.1.1',
          routerIpv6Addresses: ['2001:db8::1'],
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res3.loopDetected, isTrue);

        final res4 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['1.1.1.1#53', '8.8.8.8#5353'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res4.loopDetected, isFalse);
        expect(res4.isWarningOnly, isFalse);

        final res5 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['udp://192.168.1.1#53'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res5.loopDetected, isTrue);
      },
    );

    test('clean public resolvers do not trigger loop detection', () {
      final res = AdGuardController.detectForwardingLoop(
        adguardUpstreams: [
          '1.1.1.1',
          '8.8.8.8',
          'https://dns.adguard-dns.com/dns-query',
          'tls://dns.google',
        ],
        routerIp: '192.168.1.1',
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res.loopDetected, isFalse);
    });

    test(
      'detects loop or advisory warning for bracketed and unbracketed IPv6 and custom ports',
      () {
        final res1 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[::1]:53'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res1.loopDetected, isTrue);
        expect(res1.isWarningOnly, isFalse);

        final res2 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['[::1]:5335'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res2.loopDetected, isFalse);
        expect(res2.isWarningOnly, isTrue);
        expect(
          res2.loopReason,
          contains('targets a local service on port 5335'),
        );

        final res3 = AdGuardController.detectForwardingLoop(
          adguardUpstreams: ['::1'],
          routerIp: '192.168.1.1',
          dnsmasqPort: 53,
          isExternal: false,
        );
        expect(res3.loopDetected, isTrue);
        expect(res3.isWarningOnly, isFalse);
      },
    );

    test('detects loop or advisory warning for router IPv6 LAN addresses', () {
      const routerIpv6 = ['fd00::1', '2001:db8::1'];

      final res1 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['[fd00::1]:53'],
        routerIp: '192.168.1.1',
        routerIpv6Addresses: routerIpv6,
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res1.loopDetected, isTrue);
      expect(res1.isWarningOnly, isFalse);

      final res2 = AdGuardController.detectForwardingLoop(
        adguardUpstreams: ['[fd00::1]:5353'],
        routerIp: '192.168.1.1',
        routerIpv6Addresses: routerIpv6,
        dnsmasqPort: 53,
        isExternal: false,
      );
      expect(res2.loopDetected, isFalse);
      expect(res2.isWarningOnly, isTrue);
    });
  });

  group('Preflight Safety Checks', () {
    test(
      'derives forwarder strictly from status.dnsPort (not web management port)',
      () async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_router_preflight',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_router_preflight',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh();
        final preflight = await controller.preflightRouterDnsConfiguration();

        expect(preflight.targetPort, equals(5353));
        expect(preflight.targetForwarder, equals('127.0.0.1#5353'));
        expect(preflight.targetForwarder, isNot(contains('3000')));
        expect(preflight.canProceed, isTrue);
      },
    );

    test(
      'warns when external destination is a hostname instead of IP',
      () async {
        final container = ProviderContainer();
        const profile = AdGuardInstanceProfile(
          id: 'ext_host_profile',
          name: 'Remote AdGuard',
          host: 'my-adguard.lan',
          port: 3000,
          type: AdGuardInstanceType.externalHost,
        );

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_router_hostname',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['192.168.1.99'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_router_hostname',
          initialProfile: profile,
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh();
        final preflight = await controller.preflightRouterDnsConfiguration();

        expect(preflight.isHostname, isTrue);
        expect(preflight.warnings.any((w) => w.contains('hostname')), isTrue);
      },
    );

    test(
      'blocks configuration when upstream creates forwarding loop',
      () async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_router_loop',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
        )..upstreamDns = ['192.168.1.1'];

        final controller = createController(
          container,
          'test_router_loop',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh();
        final preflight = await controller.preflightRouterDnsConfiguration();

        expect(preflight.loopDetected, isTrue);
        expect(preflight.canProceed, isFalse);
      },
    );

    test(
      'surfaces advisory warning but allows configuration to proceed when local resolver uses custom port',
      () async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_router_custom_port_resolver',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
        )..upstreamDns = ['127.0.0.1:5335'];

        final controller = createController(
          container,
          'test_router_custom_port_resolver',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh();
        final preflight = await controller.preflightRouterDnsConfiguration();

        expect(preflight.loopDetected, isFalse);
        expect(preflight.canProceed, isTrue);
        expect(
          preflight.warnings.any((w) => w.contains('targets a local service')),
          isTrue,
        );
      },
    );
  });

  group('Transaction Orchestration & Rollback Watchdog', () {
    test(
      'Reviewer Mode Isolation: performs zero ubus / RPC calls and returns simulated success',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final controller = createController(
          container,
          'reviewer-mock-router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(result.appliedServers, contains('127.0.0.1#53'));
        expect(result.appliedServers, contains('1.1.1.1'));
        expect(mockLuci.callLog, isEmpty);
        expect(mockLuci.uciApplyLog, isEmpty);
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Successful transaction: stages uci.set, applies with 30s rollback watchdog, verifies board & readback, confirms transaction',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_tx_router',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(result.appliedServers, equals(['127.0.0.1#53', '1.1.1.1']));

        expect(
          mockLuci.callLog.any((c) => c.object == 'uci' && c.method == 'set'),
          isTrue,
        );
        expect(
          mockLuci.uciApplyLog,
          equals(['uciApply(rollback: true, timeout: 30)']),
        );
        expect(
          mockLuci.callLog.any(
            (c) => c.object == 'system' && c.method == 'board',
          ),
          isTrue,
        );
        expect(mockLuci.uciConfirmLog, equals(['uciConfirm()']));
        expect(mockLuci.uciRevertLog, isEmpty);
      },
    );

    test(
      'Fallback replacement: when preserveExistingAsFallback is false, only target forwarder is set',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_router_exclusive',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_tx_router_exclusive',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: false,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(result.appliedServers, equals(['127.0.0.1#53']));
      },
    );

    test(
      '3b. Exclusive mode conditional forwarder preservation: keeps domain-specific rules starting with /',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': [
                    '/lan/192.168.1.1',
                    '/corp.local/10.0.0.1',
                    '1.1.1.1',
                    '8.8.8.8',
                  ],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_router_exclusive_conditional',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_tx_router_exclusive_conditional',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: false,
          targetForwarder: '192.168.1.20#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(
          result.appliedServers,
          equals([
            '192.168.1.20#53',
            '/lan/192.168.1.1',
            '/corp.local/10.0.0.1',
          ]),
        );

        final setCall = mockLuci.callLog.firstWhere(
          (c) => c.object == 'uci' && c.method == 'set',
        );
        expect(
          setCall.params?['values']?['server'],
          equals([
            '192.168.1.20#53',
            '/lan/192.168.1.1',
            '/corp.local/10.0.0.1',
          ]),
        );
      },
    );

    test(
      '3c. Strips conditional rules targeting AdGuard while preserving independent domain and reverse-DNS forwarders',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': [
                    '/lan/127.0.0.1#5353',
                    '/1.168.192.in-addr.arpa/127.0.0.1#5353',
                    '/corp/10.0.0.2',
                    '/local/',
                    '/1.168.192.in-addr.arpa/10.0.0.2#53',
                    '1.1.1.1',
                  ],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_sanitize_adguard_rules',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_tx_sanitize_adguard_rules',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final resExclusive = await controller.configureRouterDns(
          preserveExistingAsFallback: false,
          targetForwarder: '127.0.0.1#5353',
        );

        expect(resExclusive.status, equals(AdGuardDnsConfigStatus.success));
        expect(
          resExclusive.appliedServers,
          equals([
            '127.0.0.1#5353',
            '/corp/10.0.0.2',
            '/local/',
            '/1.168.192.in-addr.arpa/10.0.0.2#53',
          ]),
        );

        final resFallback = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#5353',
        );

        expect(resFallback.status, equals(AdGuardDnsConfigStatus.success));
        expect(
          resFallback.appliedServers,
          equals([
            '127.0.0.1#5353',
            '/corp/10.0.0.2',
            '/local/',
            '/1.168.192.in-addr.arpa/10.0.0.2#53',
            '1.1.1.1',
          ]),
        );
      },
    );

    test(
      'Apply failure: calls uciRevert on apply rejection and returns wasRolledBack: true',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService()
          ..applyResult = false;
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_apply_fail',
        );

        final controller = createController(
          container,
          'test_tx_apply_fail',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(result.wasRolledBack, isTrue);
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Reachability check failure: triggers rollback when router reachability check fails after apply',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService()
          ..reachabilityResult = false;
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_reach_fail',
        );

        final controller = createController(
          container,
          'test_tx_reach_fail',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.rolledBack));
        expect(result.wasRolledBack, isTrue);
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Readback mismatch: reverts configuration if verification readback fails',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService()
          ..readbackContainsTarget = false;
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_readback_fail',
        );

        final controller = createController(
          container,
          'test_tx_readback_fail',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(result.wasRolledBack, isTrue);
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Confirmation failure: reports ambiguous state when uciConfirm returns false',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService()
          ..confirmResult = false;
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_confirm_fail',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_tx_confirm_fail',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.ambiguous));
        expect(mockLuci.uciConfirmLog, equals(['uciConfirm()']));
      },
    );

    test(
      'Queue serialization: sequential execution via RouterScopedOperationQueue',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_tx_queue',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final queue = RouterScopedOperationQueue.instance;
        final controller = createController(
          container,
          'test_tx_queue',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
          operationQueueOverride: queue,
        );

        final future1 = controller.configureRouterDns(
          preserveExistingAsFallback: true,
          targetForwarder: '127.0.0.1#53',
        );
        final future2 = controller.configureRouterDns(
          preserveExistingAsFallback: false,
          targetForwarder: '127.0.0.1#53',
        );

        final results = await Future.wait([future1, future2]);
        expect(results[0].status, equals(AdGuardDnsConfigStatus.success));
        expect(results[1].status, equals(AdGuardDnsConfigStatus.success));
        expect(mockLuci.uciConfirmLog.length, equals(2));
      },
    );
  });

  group('UI & ConfigureRouterDnsDialog', () {
    testWidgets('renders preflight summary and handles user cancellation', (
      tester,
    ) async {
      final container = ProviderContainer();
      final mockAdGuard = OrchestrationTestMockAdGuardApiService(
        routerId: 'test_ui_router',
        status: const AdGuardStatus(
          version: 'v0.107.52',
          running: true,
          protectionState: AdGuardProtectionState.enabled,
          dnsAddresses: ['127.0.0.1'],
          dnsPort: 5353,
          httpPort: 3000,
        ),
      );

      final controller = createController(
        container,
        'test_ui_router',
        apiServiceOverride: mockAdGuard,
        authServiceOverride: OrchestrationTestMockAuthService(),
      );

      const preflight = AdGuardDnsPreflightResult(
        canProceed: true,
        targetHost: '127.0.0.1',
        targetPort: 5353,
        targetForwarder: '127.0.0.1#5353',
        currentServers: ['1.1.1.1'],
        warnings: [],
      );

      bool? dialogResult;

      await tester.pumpWidget(
        buildTestApp(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  dialogResult = await showModalBottomSheet<bool>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) => ConfigureRouterDnsDialog(
                      controller: controller,
                      routerId: 'test_ui_router',
                      initialPreflight: preflight,
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Point the router at AdGuard Home'), findsOneWidget);
      expect(find.text('127.0.0.1#5353'), findsOneWidget);
      expect(find.byType(KsChoice<bool>), findsOneWidget);

      expect(find.byKey(const Key('agh_cancel_dns_btn')), findsOneWidget);
      await tester.tap(find.byKey(const Key('agh_cancel_dns_btn')));
      await tester.pumpAndSettle();

      expect(dialogResult, isFalse);
    });

    testWidgets(
      'executes configuration in Reviewer Mode and renders success result view',
      (tester) async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'reviewer-mock-router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'reviewer-mock-router',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        const preflight = AdGuardDnsPreflightResult(
          canProceed: true,
          targetHost: '127.0.0.1',
          targetPort: 53,
          targetForwarder: '127.0.0.1#53',
          currentServers: ['1.1.1.1'],
          warnings: [],
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => ConfigureRouterDnsDialog(
                        controller: controller,
                        routerId: 'reviewer-mock-router',
                        initialPreflight: preflight,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('agh_apply_dns_btn')), findsOneWidget);
        await tester.tap(find.byKey(const Key('agh_apply_dns_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_dns_config_result_title')),
          findsOneWidget,
        );
        expect(
          find.text('Done. Every device now uses AdGuard Home.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_config_done_btn')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('agh_dns_config_done_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(ConfigureRouterDnsDialog), findsNothing);
      },
    );

    testWidgets(
      'ConfigureRouterDnsDialog renders advisory warning banner in preflight and result view for custom-port resolver (127.0.0.1:5335)',
      (tester) async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'reviewer-mock-router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'reviewer-mock-router',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        const customPortWarning =
            'AdGuard upstream "127.0.0.1:5335" targets a local service on port 5335. '
            'Verify that this resolver does not route queries back to router dnsmasq (port 53) or AdGuard.';

        const preflight = AdGuardDnsPreflightResult(
          canProceed: true,
          targetHost: '127.0.0.1',
          targetPort: 5353,
          targetForwarder: '127.0.0.1#5353',
          currentServers: ['1.1.1.1'],
          warnings: [customPortWarning],
          loopReason: customPortWarning,
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => ConfigureRouterDnsDialog(
                        controller: controller,
                        routerId: 'reviewer-mock-router',
                        initialPreflight: preflight,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_dns_advisory_warning_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_advisory_warning_text')),
          findsOneWidget,
        );
        expect(find.text(customPortWarning), findsOneWidget);

        expect(find.byKey(const Key('agh_apply_dns_btn')), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_apply_dns_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_dns_config_result_title')),
          findsOneWidget,
        );
        expect(
          find.text('Done. Every device now uses AdGuard Home.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_result_advisory_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_result_advisory_warning_text')),
          findsOneWidget,
        );
        expect(find.text(customPortWarning), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_dns_config_done_btn')));
        await tester.pumpAndSettle();
        expect(find.byType(ConfigureRouterDnsDialog), findsNothing);
      },
    );

    testWidgets(
      'ConfigureRouterDnsDialog end-to-end with preflightRouterDnsConfiguration() produces and renders advisory warning for 127.0.0.1:5335',
      (tester) async {
        final container = ProviderContainer();
        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'reviewer-mock-router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 5353,
            httpPort: 3000,
          ),
          upstreamDns: ['127.0.0.1:5335'],
        );

        final controller = createController(
          container,
          'reviewer-mock-router',
          apiServiceOverride: mockAdGuard,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        await controller.refresh();
        final preflight = await controller.preflightRouterDnsConfiguration();
        expect(preflight.canProceed, isTrue);
        expect(preflight.loopReason, isNotNull);
        expect(preflight.loopReason, contains('127.0.0.1:5335'));
        expect(preflight.warnings, contains(preflight.loopReason));

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => ConfigureRouterDnsDialog(
                        controller: controller,
                        routerId: 'reviewer-mock-router',
                        initialPreflight: preflight,
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_dns_advisory_warning_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_advisory_warning_text')),
          findsOneWidget,
        );
        expect(find.text(preflight.loopReason!), findsOneWidget);

        expect(find.byKey(const Key('agh_apply_dns_btn')), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_apply_dns_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_dns_config_result_title')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_result_advisory_card')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_dns_result_advisory_warning_text')),
          findsOneWidget,
        );
        expect(find.text(preflight.loopReason!), findsOneWidget);

        await tester.tap(find.byKey(const Key('agh_dns_config_done_btn')));
        await tester.pumpAndSettle();
        expect(find.byType(ConfigureRouterDnsDialog), findsNothing);
      },
    );
  });

  group('Localization Completeness Across All 9 Locales', () {
    test('All 9 supported locales define all 37 localization keys', () {
      final locales = [
        const Locale('en'),
        const Locale('de'),
        const Locale('es'),
        const Locale('fr'),
        const Locale('id'),
        const Locale('pt'),
        const Locale('pt', 'BR'),
        const Locale('ru'),
        const Locale('zh'),
      ];

      for (final locale in locales) {
        final l10n = lookupAppLocalizations(locale);
        expect(l10n.aghRoutingApiOnly, isNotEmpty);
        expect(l10n.aghRoutingServiceRunning, isNotEmpty);
        expect(l10n.aghRoutingForwardingUnverified, isNotEmpty);
        expect(l10n.aghRoutingForwardingVerified, isNotEmpty);
        expect(l10n.aghRoutingClientVerified, isNotEmpty);
        expect(l10n.aghRoutingExternalStandalone, isNotEmpty);
        expect(l10n.aghRoutingMisconfigured, isNotEmpty);
        expect(l10n.aghRoutingUnknown, isNotEmpty);
        expect(l10n.aghIpv6NoBypass, isNotEmpty);
        expect(l10n.aghIpv6ExternalBypass, isNotEmpty);
        expect(l10n.aghIpv6UnsupportedListener, isNotEmpty);
        expect(l10n.aghIpv6UnableToVerify, isNotEmpty);
        expect(l10n.aghConfigureRouterDns, isNotEmpty);
        expect(l10n.aghReconfigureRouterDns, isNotEmpty);
        expect(l10n.aghConfigureDnsTitle, isNotEmpty);
        expect(l10n.aghConfigureDnsDescription, isNotEmpty);
        expect(l10n.aghConfigureDnsTarget, isNotEmpty);
        expect(l10n.aghConfigureDnsChecking, isNotEmpty);
        expect(l10n.aghConfigureDnsModeExclusive, isNotEmpty);
        expect(l10n.aghConfigureDnsModeExclusiveDesc, isNotEmpty);
        expect(l10n.aghConfigureDnsModeExclusiveWarning, isNotEmpty);
        expect(l10n.aghConfigureDnsModeFallback, isNotEmpty);
        expect(l10n.aghConfigureDnsModeFallbackDesc, isNotEmpty);
        expect(l10n.aghConfigureDnsModeFallbackWarning, isNotEmpty);
        expect(l10n.aghConfigureDnsRollbackNotice, isNotEmpty);
        expect(l10n.aghConfigureDnsApplying, isNotEmpty);
        expect(l10n.aghConfigureDnsVerifying, isNotEmpty);
        expect(l10n.aghConfigureDnsConfirming, isNotEmpty);
        expect(l10n.aghConfigureDnsSuccess, isNotEmpty);
        expect(l10n.aghConfigureDnsRolledBack, isNotEmpty);
        expect(l10n.aghConfigureDnsAmbiguous, isNotEmpty);
        expect(l10n.aghConfigureDnsHostnameWarning, isNotEmpty);
        expect(l10n.aghConfigureDnsLoopError, isNotEmpty);
        expect(l10n.aghConfigureDnsConflictError, isNotEmpty);
        expect(l10n.aghConfigureDnsActionApply, isNotEmpty);
        expect(l10n.aghConfigureDnsCurrentUpstreams, isNotEmpty);
        expect(l10n.aghConfigureDnsNewUpstreams, isNotEmpty);
      }

      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.aghRoutingClientVerified, equals('Client Queries Verified'));
      final de = lookupAppLocalizations(const Locale('de'));
      expect(
        de.aghRoutingClientVerified,
        equals('Client-Abfragen verifiziert'),
      );
      final es = lookupAppLocalizations(const Locale('es'));
      expect(
        es.aghRoutingClientVerified,
        equals('Consultas de clientes verificadas'),
      );
      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(
        fr.aghRoutingClientVerified,
        equals('Requêtes des clients vérifiées'),
      );
    });
  });

  group('DNS Forwarding Removal / Revert', () {
    test(
      'Successful removal: removes AdGuard forwarder, preserves other servers, verifies readback and confirms',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_revert_router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_revert_router',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final preflight = await controller.preflightRevertRouterDns();
        expect(preflight.canProceed, isTrue);
        expect(preflight.targetRule, equals('127.0.0.1#53'));
        expect(preflight.remainingServers, equals(['1.1.1.1']));
        expect(preflight.isMissing, isFalse);
        expect(preflight.isAmbiguous, isFalse);

        final result = await controller.revertRouterDns(
          targetForwarder: preflight.targetRule!,
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(result.appliedServers, equals(['1.1.1.1']));

        final setCall = mockLuci.callLog.firstWhere(
          (c) => c.object == 'uci' && c.method == 'set',
        );
        expect(setCall.params?['values']?['server'], equals(['1.1.1.1']));
        expect(
          mockLuci.uciApplyLog,
          equals(['uciApply(rollback: true, timeout: 30)']),
        );
        expect(
          mockLuci.callLog.any(
            (c) => c.object == 'system' && c.method == 'board',
          ),
          isTrue,
        );
        expect(mockLuci.uciConfirmLog, equals(['uciConfirm()']));
        expect(mockLuci.uciRevertLog, isEmpty);

        expect(controller.state.isMutatingDns, isFalse);
        expect(controller.state.dnsActionError, isNull);
      },
    );

    testWidgets(
      'Cancellation: clicking Cancel in RevertRouterDnsDialog leaves configuration untouched with zero LuCI calls',
      (tester) async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final controller = createController(
          container,
          'test_revert_cancel_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        const preflight = AdGuardDnsRevertPreflightResult(
          canProceed: true,
          targetRule: '127.0.0.1#53',
          currentServers: ['127.0.0.1#53', '1.1.1.1'],
          remainingServers: ['1.1.1.1'],
        );

        bool? dialogResult;
        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    dialogResult = await RevertRouterDnsDialog.show(
                      context,
                      controller: controller,
                      routerId: 'test_revert_cancel_router',
                      initialPreflight: preflight,
                    );
                  },
                  child: const Text('Open Revert Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Revert Dialog'));
        await tester.pumpAndSettle();

        expect(find.byType(RevertRouterDnsDialog), findsOneWidget);
        expect(
          find.text('Stop sending lookups to AdGuard Home'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('agh_revert_dns_target_text')),
          findsOneWidget,
        );
        expect(find.text('127.0.0.1#53'), findsOneWidget);
        expect(
          find.byKey(const Key('agh_revert_dns_remaining_text')),
          findsOneWidget,
        );
        expect(find.text('1.1.1.1'), findsOneWidget);

        expect(
          find.byKey(const Key('agh_cancel_revert_dns_btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('agh_cancel_revert_dns_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(RevertRouterDnsDialog), findsNothing);
        expect(dialogResult, isFalse);

        expect(
          mockLuci.callLog.where((c) => c.object == 'uci' && c.method == 'set'),
          isEmpty,
        );
        expect(mockLuci.uciApplyLog, isEmpty);
      },
    );

    test(
      'Target missing: preflight detects no matching forwarder, revertRouterDns aborts without UCI mutation',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['1.1.1.1', '8.8.8.8'],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_missing_target_router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_missing_target_router',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final preflight = await controller.preflightRevertRouterDns();
        expect(preflight.canProceed, isFalse);
        expect(preflight.isMissing, isTrue);
        expect(
          preflight.failureReason,
          contains(
            'No active dnsmasq forwarder rule targeting this AdGuard Home instance',
          ),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(
          result.message,
          contains('no longer present in router configuration'),
        );
        expect(
          mockLuci.callLog.where((c) => c.object == 'uci' && c.method == 'set'),
          isEmpty,
        );
        expect(mockLuci.uciApplyLog, isEmpty);
        expect(
          controller.state.dnsActionError,
          contains('no longer present in router configuration'),
        );
      },
    );

    test(
      'Target modified: pre-mutation revalidation aborts safely if target was modified/removed before apply',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_modified_target_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final preflight = await controller.preflightRevertRouterDns();
        expect(preflight.canProceed, isTrue);

        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['9.9.9.9'],
                },
              },
            },
          ],
        };

        final result = await controller.revertRouterDns(
          targetForwarder: preflight.targetRule!,
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(result.message, contains('no longer present'));
        expect(mockLuci.uciApplyLog, isEmpty);
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Ambiguous rule: preflight and pre-mutation detect multiple matching rules and abort safely',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', 'localhost#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final mockAdGuard = OrchestrationTestMockAdGuardApiService(
          routerId: 'test_ambiguous_router',
          status: const AdGuardStatus(
            version: 'v0.107.52',
            running: true,
            protectionState: AdGuardProtectionState.enabled,
            dnsAddresses: ['127.0.0.1'],
            dnsPort: 53,
            httpPort: 3000,
          ),
        );

        final controller = createController(
          container,
          'test_ambiguous_router',
          apiServiceOverride: mockAdGuard,
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final preflight = await controller.preflightRevertRouterDns();
        expect(preflight.canProceed, isFalse);
        expect(preflight.isAmbiguous, isTrue);
        expect(
          preflight.failureReason,
          contains('Multiple ambiguous forwarding rules'),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(
          result.message,
          contains('multiple matching forwarder rules detected'),
        );
        expect(
          mockLuci.callLog.where((c) => c.object == 'uci' && c.method == 'set'),
          isEmpty,
        );
        expect(mockLuci.uciApplyLog, isEmpty);
      },
    );

    test(
      'Preservation of unrelated rules: user upstreams, conditional forwarders, and reverse DNS remain intact in exact order',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': [
                    '/corp/10.0.0.1',
                    '127.0.0.1#53',
                    '1.1.1.1',
                    '/example.com/8.8.4.4',
                    '9.9.9.9',
                  ],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_preserve_rules_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(
          result.appliedServers,
          equals([
            '/corp/10.0.0.1',
            '1.1.1.1',
            '/example.com/8.8.4.4',
            '9.9.9.9',
          ]),
        );

        final setCall = mockLuci.callLog.firstWhere(
          (c) => c.object == 'uci' && c.method == 'set',
        );
        expect(
          setCall.params?['values']?['server'],
          equals([
            '/corp/10.0.0.1',
            '1.1.1.1',
            '/example.com/8.8.4.4',
            '9.9.9.9',
          ]),
        );
      },
    );

    test(
      'Mutation failure: uciApply failure triggers uciRevert and reports rollback',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.applyResult = false;
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_apply_failure_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(result.wasRolledBack, isTrue);
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Partial failure / rollback: reachability check failure triggers uciRevert and reports rolledBack',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.reachabilityResult = false;
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_reachability_failure_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.rolledBack));
        expect(result.wasRolledBack, isTrue);
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    test(
      'Verification failure: readback failure (target still present) triggers uciRevert',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.readbackReturnsTargetForRevert = true;
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_readback_failure_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.failed));
        expect(result.wasRolledBack, isTrue);
        expect(
          result.message,
          contains('Configuration verification readback failed'),
        );
        expect(mockLuci.uciRevertLog, equals(['uciRevert(config: dhcp)']));
        expect(mockLuci.uciConfirmLog, isEmpty);
      },
    );

    testWidgets(
      'Retry after failure in RevertRouterDnsDialog re-runs preflight and allows retry',
      (tester) async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        mockLuci.applyResult = false;
        mockLuci.dhcpGetResponse = {
          'result': [
            0,
            {
              'values': {
                'cfg01': {
                  '.type': 'dnsmasq',
                  'server': ['127.0.0.1#53', '1.1.1.1'],
                },
              },
            },
          ],
        };

        final controller = createController(
          container,
          'test_dialog_retry_router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        const preflight = AdGuardDnsRevertPreflightResult(
          canProceed: true,
          targetRule: '127.0.0.1#53',
          currentServers: ['127.0.0.1#53', '1.1.1.1'],
          remainingServers: ['1.1.1.1'],
        );

        await tester.pumpWidget(
          buildTestApp(
            child: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (ctx) => RevertRouterDnsDialog(
                        controller: controller,
                        routerId: 'test_dialog_retry_router',
                        initialPreflight: preflight,
                      ),
                    );
                  },
                  child: const Text('Open Revert Dialog'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.text('Open Revert Dialog'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_confirm_revert_dns_btn')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('agh_confirm_revert_dns_btn')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_revert_dns_retry_btn')),
          findsOneWidget,
        );

        mockLuci.applyResult = true;
        await tester.tap(find.byKey(const Key('agh_revert_dns_retry_btn')));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('agh_confirm_revert_dns_btn')),
          findsOneWidget,
        );
      },
    );

    test(
      'Reviewer mode offline isolation: revertRouterDns performs zero RPCs and returns simulated success',
      () async {
        final container = ProviderContainer();
        final mockLuci = OrchestrationTestTrackingLuciApiService();
        final controller = createController(
          container,
          'reviewer-mock-router',
          luciApiServiceOverride: mockLuci,
          authServiceOverride: OrchestrationTestMockAuthService(),
        );

        final result = await controller.revertRouterDns(
          targetForwarder: '127.0.0.1#53',
        );

        expect(result.status, equals(AdGuardDnsConfigStatus.success));
        expect(result.appliedServers, equals(['1.1.1.1']));
        expect(mockLuci.callLog, isEmpty);
        expect(mockLuci.uciApplyLog, isEmpty);
        expect(mockLuci.uciConfirmLog, isEmpty);
        expect(mockLuci.uciRevertLog, isEmpty);
      },
    );

    test('Localization Completeness across all 9 supported locales', () {
      final locales = [
        const Locale('en'),
        const Locale('de'),
        const Locale('es'),
        const Locale('fr'),
        const Locale('id'),
        const Locale('pt'),
        const Locale('pt', 'BR'),
        const Locale('ru'),
        const Locale('zh'),
      ];

      for (final locale in locales) {
        final l10n = lookupAppLocalizations(locale);
        expect(l10n.aghRevertRouterDns, isNotEmpty);
        expect(l10n.aghRevertDnsTitle, isNotEmpty);
        expect(l10n.aghRevertDnsDescription, isNotEmpty);
        expect(l10n.aghRevertDnsRuleToRemove, isNotEmpty);
        expect(l10n.aghRevertDnsRemainingUpstreams, isNotEmpty);
        expect(l10n.aghRevertDnsNoRemainingWarning, isNotEmpty);
        expect(l10n.aghRevertDnsActionRemove, isNotEmpty);
        expect(l10n.aghRevertDnsRemoving, isNotEmpty);
        expect(l10n.aghRevertDnsSuccess, isNotEmpty);
        expect(l10n.aghRevertDnsSuccessTitle, isNotEmpty);
        expect(l10n.aghRevertDnsFailedTitle, isNotEmpty);
        expect(l10n.aghRevertDnsMissingError, isNotEmpty);
        expect(l10n.aghRevertDnsAmbiguousError, isNotEmpty);
      }

      final en = lookupAppLocalizations(const Locale('en'));
      expect(en.aghRevertRouterDns, equals('Remove Forwarding'));
      final de = lookupAppLocalizations(const Locale('de'));
      expect(de.aghRevertRouterDns, equals('Weiterleitung entfernen'));
      final es = lookupAppLocalizations(const Locale('es'));
      expect(es.aghRevertRouterDns, equals('Eliminar reenvío'));
      final fr = lookupAppLocalizations(const Locale('fr'));
      expect(fr.aghRevertRouterDns, equals('Supprimer la redirection'));
      final ru = lookupAppLocalizations(const Locale('ru'));
      expect(ru.aghRevertRouterDns, equals('Удалить перенаправление'));
      final zh = lookupAppLocalizations(const Locale('zh'));
      expect(zh.aghRevertRouterDns, equals('移除转发'));
    });
  });
}
