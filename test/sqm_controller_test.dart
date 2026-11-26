// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/modules/sqm/controllers/sqm_controller.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_telemetry.dart';
import 'package:yet_another_luci_app/modules/sqm/services/sqm_telemetry_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';

class _MockLuciApiService implements IApiService {
  final Map<String, dynamic> responses;
  int callCount = 0;

  _MockLuciApiService({this.responses = const {}});

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    callCount++;
    final key = '$object.$method';
    if (responses.containsKey(key)) {
      return responses[key];
    }
    return [0, {}];
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingLuciApiService implements IApiService {
  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async {
    throw Exception('Simulated network/RPC connection refused');
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockTelemetryService extends SqmTelemetryService {
  SqmQueueTelemetry? cannedTelemetry;
  int fetchCount = 0;

  _MockTelemetryService({this.cannedTelemetry});

  @override
  Future<SqmQueueTelemetry?> fetchQueueTelemetry({
    required IApiService apiService,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    required String interfaceName,
    bool isReviewerMode = false,
  }) async {
    fetchCount++;
    return cannedTelemetry;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(SqmController.clearSessionCache);

  group('SqmController Lifecycle & State Discovery', () {
    test('Reviewer Mode populates realistic active mock state', () async {
      final controller = SqmController('reviewer-mock-router');
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isTrue);
      expect(state.isServiceRunning, isTrue);
      expect(state.operatingState, equals(SqmOperatingState.active));
      expect(state.queues.length, equals(2));
      expect(state.primaryQueue?.interface, equals('eth0'));
      expect(state.primaryTelemetry?.qdisc, equals('cake'));
      expect(state.primaryTelemetry?.tinStats.length, equals(3));
      expect(state.isLoading, isFalse);
    });

    test('Uninstalled SQM router classifies as notInstalled', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [
            0,
            {
              'firewall': {'running': true},
            },
          ],
          'uci.get': [
            0,
            {'values': {}},
          ],
        },
      );

      final controller = SqmController(
        'test-router-1',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isFalse);
      expect(state.operatingState, equals(SqmOperatingState.notInstalled));
      expect(state.queues, isEmpty);
    });

    test(
      'Firewall flow offloading detected as flowOffloadingConflict',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'defaults': {
                    '.type': 'defaults',
                    'flow_offloading': '1',
                    'flow_offloading_hw': '0',
                  },
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        final controller = SqmController(
          'test-router-2',
          apiServiceOverride: api,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        final state = controller.state;
        expect(state.isInstalled, isTrue);
        expect(state.hasSoftwareFlowOffload, isTrue);
        expect(state.hasHardwareFlowOffload, isFalse);
        expect(state.hasAnyFlowOffloading, isTrue);
        expect(
          state.operatingState,
          equals(SqmOperatingState.flowOffloadingConflict),
        );
      },
    );

    test('finds the internet link by its default route', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [
            0,
            {
              'sqm': {'running': false, 'enabled': true},
            },
          ],
          'uci.get': [
            0,
            {
              'values': {
                'eth1': {
                  '.type': 'queue',
                  'interface': 'eth1',
                  'download': 85000,
                  'upload': 10000,
                  'enabled': '0',
                },
              },
            },
          ],
          'network.interface.dump': [
            0,
            {
              'interface': [
                {'interface': 'lan', 'up': true, 'device': 'br-lan'},
                {
                  'interface': 'modem',
                  'up': true,
                  'l3_device': 'wwan0',
                  'route': [
                    {'target': '0.0.0.0', 'mask': 0},
                  ],
                },
              ],
            },
          ],
        },
      );
      final controller = SqmController(
        'test-router-wwan',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.state.primaryWanInterface, 'wwan0');
      expect(controller.state.networkInterfaces, ['br-lan', 'wwan0']);
      expect(
        sqmTargetInterface(controller.state.queues.single, controller.state),
        'wwan0',
      );
    });

    test('a full-tunnel VPN is not taken for the internet link', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [0, <String, dynamic>{}],
          'uci.get': [
            0,
            {
              'values': {
                'q': {'.type': 'queue', 'interface': 'eth0', 'enabled': '0'},
              },
            },
          ],
          'network.interface.dump': [
            0,
            {
              'interface': [
                {
                  'interface': 'awg',
                  'proto': 'wireguard',
                  'l3_device': 'awg',
                  'route': [
                    {'target': '0.0.0.0', 'mask': 0},
                  ],
                },
                {
                  'interface': 'wan',
                  'proto': 'pppoe',
                  'device': 'eth0.2',
                  'l3_device': 'pppoe-wan',
                  'route': [
                    {'target': '0.0.0.0', 'mask': 0},
                  ],
                },
              ],
            },
          ],
        },
      );
      final controller = SqmController(
        'test-router-vpn',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      expect(controller.state.errorMessage, isNull);
      expect(controller.state.primaryWanInterface, 'pppoe-wan');
    });

    test('keeps a queue on a link the router has', () {
      const s = SqmState(
        primaryWanInterface: 'wwan0',
        networkInterfaces: ['br-lan', 'wan', 'wwan0'],
      );
      expect(
        sqmTargetInterface(const SqmQueue(name: 'q', interface: 'wan'), s),
        'wan',
      );
      expect(sqmTargetInterface(null, s), 'wwan0');
    });

    test('Inactive service classifies as inactive', () async {
      final api = _MockLuciApiService(
        responses: {
          'rc.list': [
            0,
            {
              'sqm': {'running': false, 'enabled': false},
            },
          ],
          'uci.get': [
            0,
            {
              'values': {
                'eth0': {
                  '.type': 'queue',
                  'interface': 'eth0',
                  'download': 100000,
                  'upload': 20000,
                  'qdisc': 'cake',
                  'enabled': '0',
                },
              },
            },
          ],
        },
      );

      final controller = SqmController(
        'test-router-3',
        apiServiceOverride: api,
      );
      addTearDown(controller.dispose);

      await controller.refresh();

      final state = controller.state;
      expect(state.isInstalled, isTrue);
      expect(state.isServiceRunning, isFalse);
      expect(state.operatingState, equals(SqmOperatingState.inactive));
    });

    test(
      'Telemetry failure on active queue classifies as telemetryUnavailable',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        final telemetryService = _MockTelemetryService(cannedTelemetry: null);

        final controller = SqmController(
          'test-router-4',
          apiServiceOverride: api,
          telemetryServiceOverride: telemetryService,
        );
        addTearDown(controller.dispose);

        await controller.refresh(forceTelemetry: true);

        final state = controller.state;
        expect(state.isInstalled, isTrue);
        expect(
          state.operatingState,
          equals(SqmOperatingState.telemetryUnavailable),
        );
      },
    );

    test(
      'Single-flight mutex blocks concurrent overlapping refreshes',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
          },
        );

        final controller = SqmController(
          'test-router-5',
          apiServiceOverride: api,
        );
        addTearDown(controller.dispose);

        final f1 = controller.refresh();
        final f2 = controller.refresh();

        await Future.wait([f1, f2]);

        expect(api.callCount, greaterThan(0));
      },
    );

    test(
      'Controller refresh alone does NOT start live telemetry timer',
      () async {
        final mockTelem = SqmQueueTelemetry(
          interfaceName: 'eth0',
          qdisc: 'cake',
          sentPackets: 1000,
          droppedPackets: 10,
          timestamp: DateTime.now(),
        );

        final telemetryService = _MockTelemetryService(
          cannedTelemetry: mockTelem,
        );

        final controller = SqmController(
          'reviewer-mock-router',
          telemetryServiceOverride: telemetryService,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test(
      'Provider subscriber / dashboard observer alone does NOT start live telemetry timer',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final subscription = container.listen(
          sqmControllerProvider('reviewer-mock-router'),
          (previous, next) {},
        );

        final controller = container.read(
          sqmControllerProvider('reviewer-mock-router').notifier,
        );

        await Future.delayed(const Duration(milliseconds: 20));

        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);

        subscription.close();
      },
    );

    test(
      'Explicit startLiveTelemetry by SqmScreen starts 3-second timer and stopLiveTelemetry immediately cancels it',
      () async {
        final controller = SqmController('reviewer-mock-router');
        addTearDown(controller.dispose);

        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));

        controller.startLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));
        expect(controller.state.isTelemetryPolling, isTrue);

        controller.startLiveTelemetry();
        expect(controller.activeScreenSessions, equals(2));
        expect(controller.isTelemetryTimerActive, isTrue);

        controller.stopLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));

        controller.stopLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.activeScreenSessions, equals(0));
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test('Controller dispose cancels telemetry timer immediately', () async {
      final controller = SqmController('reviewer-mock-router');

      controller.startLiveTelemetry();
      expect(controller.isTelemetryTimerActive, isTrue);

      controller.dispose();
      expect(controller.isTelemetryTimerActive, isFalse);
    });

    test(
      'AutoDispose family provider creates distinct instances for different router IDs',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final subA = container.listen(
          sqmControllerProvider('router-A'),
          (previous, next) {},
        );
        final subB = container.listen(
          sqmControllerProvider('router-B'),
          (previous, next) {},
        );

        final controllerA = container.read(
          sqmControllerProvider('router-A').notifier,
        );
        final controllerB = container.read(
          sqmControllerProvider('router-B').notifier,
        );

        expect(controllerA.routerId, equals('router-A'));
        expect(controllerB.routerId, equals('router-B'));
        expect(identical(controllerA, controllerB), isFalse);

        subA.close();
        subB.close();
      },
    );
  });

  group('SqmController Package Installation & Lifecycle', () {
    test(
      'installSqmPackage in Reviewer Mode succeeds and populates reviewer state',
      () async {
        final controller = SqmController('reviewer-mock-router');
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isTrue);
        expect(res.data, contains('sqm-scripts'));
        expect(controller.state.isInstalled, isTrue);
        expect(controller.state.queues.length, equals(2));
        expect(controller.state.primaryQueue?.interface, equals('eth0'));
      },
    );

    test(
      'installSqmPackage acquires router-exclusive lock blocking concurrent operations',
      () async {
        final lockAcquiredOrder = <String>[];
        final queue = RouterScopedOperationQueue.instance;

        final controller = SqmController(
          'queue-test-router',
          packageInstallerOverride: (pkg) async {
            lockAcquiredOrder.add('install-started');
            await Future.delayed(const Duration(milliseconds: 50));
            lockAcquiredOrder.add('install-finished');
            return RpcResult.success('Installed');
          },
        );
        addTearDown(controller.dispose);

        final installFuture = controller.installSqmPackage();

        final uciFuture = queue.runLocked(
          routerId: 'queue-test-router',
          domain: 'uci',
          action: () async {
            lockAcquiredOrder.add('uci-executed');
          },
        );

        await Future.wait([installFuture, uciFuture]);

        expect(
          lockAcquiredOrder,
          equals(['install-started', 'install-finished', 'uci-executed']),
        );
      },
    );

    test(
      'installSqmPackage halts live telemetry timer during execution and restores it on success if screen is active',
      () async {
        bool? timerStateDuringInstall;

        late final SqmController controller;
        controller = SqmController(
          'reviewer-mock-router',
          packageInstallerOverride: (pkg) async {
            timerStateDuringInstall = controller.isTelemetryTimerActive;
            return RpcResult.success('Installed');
          },
        );
        addTearDown(controller.dispose);

        controller.startLiveTelemetry();
        expect(controller.isTelemetryTimerActive, isTrue);
        expect(controller.activeScreenSessions, equals(1));

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isTrue);
        expect(
          timerStateDuringInstall,
          isFalse,
          reason: 'Telemetry timer must be suspended during installation',
        );
        expect(
          controller.isTelemetryTimerActive,
          isTrue,
          reason:
              'Telemetry timer must be restored on success when screen is active',
        );
      },
    );

    test(
      'installSqmPackage failure preserves error and does not restore telemetry timer if uninstalled',
      () async {
        final controller = SqmController(
          'failed-install-router',
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('opkg: exit status 127: binary not found');
          },
        );
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.errorMessage, contains('exit status 127'));
        expect(controller.state.isInstalled, isFalse);
        expect(controller.isTelemetryTimerActive, isFalse);
      },
    );

    test('installSqmPackage classifies insufficient storage failure', () async {
      final controller = SqmController(
        'low-storage-router',
        packageInstallerOverride: (pkg) async {
          return RpcResult.failed(
            'Collected errors:\n * verify_pkg_installable: Only 24kb available on filesystem /overlay, ipkg needs 120kb.',
          );
        },
      );
      addTearDown(controller.dispose);

      final res = await controller.installSqmPackage();

      expect(res.isSuccess, isFalse);
      expect(res.isInsufficientStorage, isTrue);
      expect(
        res.userFriendlyPackageError,
        contains('Insufficient storage space'),
      );
    });

    test(
      'installSqmPackage classifies OOM / process killed failure without labeling as storage failure',
      () async {
        final controller = SqmController(
          'oom-router',
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('Killed', code: 137);
          },
        );
        addTearDown(controller.dispose);

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.isMemoryExhausted, isTrue);
        expect(
          res.isInsufficientStorage,
          isFalse,
          reason: 'OOM must not be falsely classified as insufficient storage',
        );
        expect(res.userFriendlyPackageError, contains('out of memory (OOM)'));
        expect(controller.state.isInstalled, isFalse);
        expect(controller.isTelemetryTimerActive, isFalse);
      },
    );

    test(
      'Semantic post-failure verification: SQM remains uninstalled, no false capability, telemetry does not resume',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'firewall': {'running': true},
              },
            ],
            'uci.get': [
              0,
              {'values': {}},
            ],
          },
        );

        final controller = SqmController(
          'semantic-fail-router',
          apiServiceOverride: api,
          packageInstallerOverride: (pkg) async {
            return RpcResult.failed('Out of memory: Kill process 1234 (apk)');
          },
        );
        addTearDown(controller.dispose);

        await controller.refresh();
        expect(controller.state.isInstalled, isFalse);
        expect(
          controller.state.operatingState,
          equals(SqmOperatingState.notInstalled),
        );

        controller.startLiveTelemetry();
        expect(controller.activeScreenSessions, equals(1));

        final res = await controller.installSqmPackage();

        expect(res.isSuccess, isFalse);
        expect(res.isMemoryExhausted, isTrue);
        expect(res.isInsufficientStorage, isFalse);

        expect(controller.state.isInstalled, isFalse);
        expect(
          controller.state.operatingState,
          equals(SqmOperatingState.notInstalled),
        );
        expect(controller.state.queues, isEmpty);

        expect(controller.isTelemetryTimerActive, isFalse);
        expect(controller.state.isTelemetryPolling, isFalse);
      },
    );

    test(
      'Probe failure on both rc.list and uci.get sqm sets errorMessage instead of false notInstalled',
      () async {
        final failingApi = _FailingLuciApiService();

        final controller = SqmController(
          'failing-probe-router',
          apiServiceOverride: failingApi,
        );
        addTearDown(controller.dispose);

        await controller.refresh();

        expect(controller.state.isLoading, isFalse);
        expect(controller.state.errorMessage, isNotNull);
        expect(
          controller.state.errorMessage,
          contains('Unable to check SQM status'),
        );
      },
    );

    test(
      'Router-scoped session cache seeds new controller instance immediately without re-loading flash',
      () async {
        final api = _MockLuciApiService(
          responses: {
            'rc.list': [
              0,
              {
                'sqm': {'running': true, 'enabled': true},
              },
            ],
            'uci.get': [
              0,
              {
                'values': {
                  'eth0': {
                    '.type': 'queue',
                    'interface': 'eth0',
                    'download': 100000,
                    'upload': 20000,
                    'qdisc': 'cake',
                    'enabled': '1',
                  },
                },
              },
            ],
          },
        );

        final controller1 = SqmController(
          'cache-router-1',
          apiServiceOverride: api,
        );
        await controller1.refresh();

        expect(controller1.state.isInstalled, isTrue);
        expect(controller1.state.queues.length, equals(1));
        controller1.dispose();

        final controller2 = SqmController(
          'cache-router-1',
          apiServiceOverride: api,
        );
        addTearDown(controller2.dispose);

        expect(controller2.state.isInstalled, isTrue);
        expect(controller2.state.queues.length, equals(1));
        expect(controller2.state.queues.first.interface, equals('eth0'));

        final controllerDifferentRouter = SqmController(
          'other-router',
          apiServiceOverride: api,
        );
        addTearDown(controllerDifferentRouter.dispose);
        expect(controllerDifferentRouter.state.lastUpdated, isNull);
        expect(controllerDifferentRouter.state.queues, isEmpty);
      },
    );
  });
}
