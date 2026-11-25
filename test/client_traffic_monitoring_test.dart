// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';

class TestMockApiService implements IApiService {
  Map<String, List<Map<String, dynamic>>> mockStationDetails = {};
  Map<String, dynamic> mockDhcpResult = {
    'dhcp_leases': [
      {
        'ipaddr': '192.168.1.101',
        'macaddr': 'AA:BB:CC:DD:EE:01',
        'hostname': 'Phone-WiFi',
        'expires': 3600,
      },
      {
        'ipaddr': '192.168.1.102',
        'macaddr': 'AA:BB:CC:DD:EE:02',
        'hostname': 'Desktop-LAN',
        'expires': 3600,
      },
    ],
  };
  Map<String, Map<String, dynamic>> mockHostHints = {};
  Map<String, dynamic>? mockNetworkInterfaceDump;

  @override
  Future<Map<String, List<Map<String, dynamic>>>>
  fetchAllAssociatedWirelessStationsWithDetailsContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    return mockStationDetails;
  }

  @override
  Future<Map<String, Set<String>>> fetchAllAssociatedWirelessMacsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    final result = <String, Set<String>>{};
    mockStationDetails.forEach((k, v) {
      result[k] = v.map((s) => s['mac'].toString().toUpperCase()).toSet();
    });
    return result;
  }

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
    if (object == 'luci-rpc' && method == 'getDHCPLeases') {
      return [0, mockDhcpResult];
    }
    if (object == 'network.interface' && method == 'dump') {
      return [0, mockNetworkInterfaceDump ?? <String, dynamic>{}];
    }
    return [0, <String, dynamic>{}];
  }

  @override
  Future<Map<String, Map<String, dynamic>>> fetchHostHintsWithContext({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    BuildContext? context,
  }) async {
    return mockHostHints;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestMockAuthService implements IAuthService {
  @override
  String? get sysauth => 'valid-sysauth-token';
  @override
  bool get useHttps => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockClientControllerWithFixedClients extends ClientController {
  final List<Client> fixedClients;
  MockClientControllerWithFixedClients(this.fixedClients)
    : super(
        apiServiceRef: () => TestMockApiService(),
        authServiceRef: () => TestMockAuthService(),
        routerServiceRef: () => RouterService(),
        reviewerModeRef: () => false,
        executeRouterCommandOutput: (cmd, args) async => null,
        processDhcpLeases: (raw) => raw,
      );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async => fixedClients;

  @override
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client>)? onIncrementalUpdate,
  }) async => fixedClients;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Client Model - Traffic & PHY Vitals Formatter', () {
    test('Byte and speed formatting helpers behave', () {
      expect(Client.formatBytes(0), '0 B');
      expect(Client.formatBytes(512), '512 B');
      expect(Client.formatBytes(1024), '1.0 KB');
      expect(Client.formatBytes(1536), '1.5 KB');
      expect(Client.formatBytes(1048576), '1.0 MB');
      expect(Client.formatBytes(52428800), '50.0 MB');
      expect(Client.formatBytes(1073741824), '1.0 GB');

      expect(Client.formatSpeed(0), '0 B/s');
      expect(Client.formatSpeed(500), '500 B/s');
      expect(Client.formatSpeed(1024), '1.0 KB/s');
      expect(Client.formatSpeed(204800), '200.0 KB/s');
      expect(Client.formatSpeed(2097152), '2.0 MB/s');

      expect(Client.formatSpeed(0, speedUnit: 'bits'), '0 bps');
      expect(Client.formatSpeed(50, speedUnit: 'bits'), '400 bps');
      expect(Client.formatSpeed(125, speedUnit: 'bits'), '1.0 Kbps');
      expect(Client.formatSpeed(12500, speedUnit: 'bits'), '100 Kbps');
      expect(Client.formatSpeed(426700, speedUnit: 'bits'), '3.4 Mbps');
      expect(Client.formatSpeed(2500000, speedUnit: 'bits'), '20.0 Mbps');
    });

    test('Signal quality label classification', () {
      final clientGood = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        signalDbm: -55,
      );
      expect(clientGood.signalQualityLabel, 'Good');
      expect(clientGood.formattedSignalWithQuality, '-55 dBm (Good)');

      final clientExcellent = clientGood.copyWith(signalDbm: -45);
      expect(clientExcellent.signalQualityLabel, 'Excellent');

      final clientFair = clientGood.copyWith(signalDbm: -70);
      expect(clientFair.signalQualityLabel, 'Fair');

      final clientWeak = clientGood.copyWith(signalDbm: -82);
      expect(clientWeak.signalQualityLabel, 'Weak');

      final clientNone = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
      );
      expect(clientNone.signalQualityLabel, null);
      expect(clientNone.formattedSignalWithQuality, null);
    });

    test('PHY rate formatting maps kbit/s accurately', () {
      final clientPhy = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxRate: 866700,
        txRate: 866700,
      );
      expect(clientPhy.formattedPhyRate, '↓ 867 Mbps • ↑ 867 Mbps');

      final clientDownloadOnly = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        txRate: 300000,
      );
      expect(clientDownloadOnly.formattedPhyRate, '↓ 300 Mbps');

      final clientUploadOnly = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxRate: 72200,
      );
      expect(clientUploadOnly.formattedPhyRate, '↑ 72.2 Mbps');
    });

    test('Speed getters and session transfer formatting', () {
      final client = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Tester',
        rxBytes: 15728640,
        txBytes: 104857600,
        rxSpeed: 102400,
        txSpeed: 2097152,
        connectedTime: 3665,
      );

      expect(client.formattedTotalUploaded, '15.0 MB');
      expect(client.formattedTotalDownloaded, '100 MB');
      expect(client.formattedUploadSpeed, '100.0 KB/s');
      expect(client.formattedDownloadSpeed, '2.0 MB/s');
      expect(client.formattedUploadSpeedWithUnit('bits'), '819 Kbps');
      expect(client.formattedDownloadSpeedWithUnit('bits'), '16.8 Mbps');
      expect(client.formattedUploadSpeedWithUnit('bytes'), '100.0 KB/s');
      expect(client.formattedDownloadSpeedWithUnit('bytes'), '2.0 MB/s');
      expect(client.formattedConnectedTime, '1h 1m');
      expect(client.hasTrafficData, isTrue);
    });

    test('Hostapd rate scale (> 1,000,000) normalizes to Mbps', () {
      final clientHostapd = Client(
        ipAddress: '192.168.1.100',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        hostname: 'Phone',
        rxRate: 65000000,
        txRate: 26000000,
      );
      expect(clientHostapd.formattedPhyRate, '↓ 260 Mbps • ↑ 650 Mbps');
    });

    test(
      'Connected duration falls back to activeTime when connectedTime is null',
      () {
        final clientActive = Client(
          ipAddress: '192.168.1.100',
          macAddress: 'AA:BB:CC:DD:EE:FF',
          hostname: 'Wired-PC',
          activeTime: 7200,
        );
        expect(clientActive.formattedConnectedTime, '2h');
      },
    );
  });

  group('ClientController - Bandwidth Monitoring & Speed Delta', () {
    late TestMockApiService mockApi;
    late TestMockAuthService mockAuth;
    late RouterService routerService;
    late ClientController clientController;
    Future<String?> Function(String cmd, List<String> args)? mockExecuteCommand;

    setUp(() async {
      mockExecuteCommand = null;
      mockApi = TestMockApiService();
      mockAuth = TestMockAuthService();
      routerService = RouterService();
      final router = model.Router(
        id: 'test-router-1',
        name: 'Main Router',
        ipAddress: '192.168.1.1',
        username: 'root',
        password: 'password',
        useHttps: false,
      );
      await routerService.addRouter(router);
      await routerService.selectRouter(router.id);

      clientController = ClientController(
        apiServiceRef: () => mockApi,
        authServiceRef: () => mockAuth,
        routerServiceRef: () => routerService,
        reviewerModeRef: () => false,
        executeRouterCommandOutput: (cmd, args) async {
          if (mockExecuteCommand != null) {
            return mockExecuteCommand!(cmd, args);
          }
          return null;
        },
        processDhcpLeases: (raw) => raw,
      );
      AppState.instance.clientControllerForTesting = clientController;
    });

    test(
      'Associates wireless station vitals and computes speed delta on refresh',
      () async {
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'noise': -95,
              'thr': 450000,
              'connected_time': 1800,
              'rx': {'bytes': 1000000, 'packets': 1000, 'rate': 866700},
              'tx': {'bytes': 5000000, 'packets': 4000, 'rate': 866700},
            },
          ],
        };

        final firstFetch = await clientController
            .fetchClientsForSelectedRouter();
        final wifiClientFirst = firstFetch.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(wifiClientFirst.connectionType, ConnectionType.wireless);
        expect(wifiClientFirst.rxBytes, 1000000);
        expect(wifiClientFirst.txBytes, 5000000);
        expect(wifiClientFirst.signalDbm, -52);
        expect(wifiClientFirst.rxSpeed, isNull);
        expect(wifiClientFirst.txSpeed, isNull);

        await Future<void>.delayed(const Duration(milliseconds: 600));
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -50,
              'noise': -95,
              'thr': 450000,
              'connected_time': 1801,
              'rx': {'bytes': 1600000, 'packets': 1500, 'rate': 866700},
              'tx': {'bytes': 6200000, 'packets': 4900, 'rate': 866700},
            },
          ],
        };

        final secondFetch = await clientController
            .fetchClientsForSelectedRouter();
        final wifiClientSecond = secondFetch.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(wifiClientSecond.rxBytes, 1600000);
        expect(wifiClientSecond.txBytes, 6200000);
        expect(wifiClientSecond.rxSpeed, isNotNull);
        expect(wifiClientSecond.txSpeed, isNotNull);
        expect(wifiClientSecond.rxSpeed!, greaterThan(0));
        expect(wifiClientSecond.txSpeed!, greaterThan(0));
      },
    );

    test(
      'Counter rollback / station reconnection does not cause negative speed or crash',
      () async {
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'rx': {'bytes': 50000000},
              'tx': {'bytes': 80000000},
            },
          ],
        };
        await clientController.fetchClientsForSelectedRouter();

        await Future<void>.delayed(const Duration(milliseconds: 600));
        mockApi.mockStationDetails = {
          'wlan0|Home-WiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:01',
              'signal': -52,
              'rx': {'bytes': 1000},
              'tx': {'bytes': 1000},
            },
          ],
        };

        final rolledBack = await clientController
            .fetchClientsForSelectedRouter();
        final client = rolledBack.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:01',
        );
        expect(client.rxBytes, 1000);
        expect(client.txBytes, 1000);
        expect(client.rxSpeed, isNull);
        expect(client.txSpeed, isNull);
      },
    );

    test('Wired clients do not receive fake wireless stats', () async {
      mockApi.mockStationDetails = {};
      final clients = await clientController.fetchClientsForSelectedRouter();
      final wiredClient = clients.firstWhere(
        (c) => c.macAddress == 'AA:BB:CC:DD:EE:02',
      );
      expect(wiredClient.connectionType, ConnectionType.wired);
      expect(wiredClient.hasTrafficData, isFalse);
      expect(wiredClient.formattedPhyRate, isNull);
    });

    test(
      'Extracts vitals from hostapd schema ({bytes: {rx, tx}, rate: {rx, tx}})',
      () async {
        mockApi.mockStationDetails = {
          'phy2-ap0|MyWiFi': [
            {
              'mac': 'AA:BB:CC:DD:EE:02',
              'signal': -46,
              'bytes': {'rx': 44397734, 'tx': 511611221},
              'packets': {'rx': 131830, 'tx': 440857},
              'rate': {'rx': 65000000, 'tx': 26000000},
            },
          ],
        };

        final clients = await clientController.fetchClientsForSelectedRouter();
        final phone = clients.firstWhere(
          (c) => c.macAddress == 'AA:BB:CC:DD:EE:02',
        );

        expect(phone.connectionType, ConnectionType.wireless);
        expect(phone.rxBytes, 44397734);
        expect(phone.txBytes, 511611221);
        expect(phone.rxRate, 65000000);
        expect(phone.txRate, 26000000);
        expect(phone.formattedPhyRate, '↓ 260 Mbps • ↑ 650 Mbps');
      },
    );

    test(
      'WAN upstream gateway and WAN interface devices are excluded from client list',
      () async {
        mockApi.mockStationDetails = {};
        mockApi.mockNetworkInterfaceDump = {
          'interface': [
            {
              'interface': 'wan',
              'device': 'eth1',
              'l3_device': 'eth1',
              'ipv4-address': [
                {'address': '172.16.0.50'},
              ],
              'route': [
                {'nexthop': '172.16.0.1'},
              ],
            },
          ],
        };
        mockApi.mockHostHints = {
          '14:C3:5E:26:6F:21': {
            'ipaddrs': ['172.16.0.1'],
            'name': 'ISP-Gateway',
          },
        };

        mockExecuteCommand = (cmd, args) async {
          if (args.contains('neigh')) {
            return '172.16.0.1 dev eth1 lladdr 14:c3:5e:26:6f:21 REACHABLE\n'
                '192.168.1.102 dev br-lan lladdr aa:bb:cc:dd:ee:02 REACHABLE';
          }
          return null;
        };

        final clients = await clientController.fetchClientsForSelectedRouter();

        expect(
          clients.any((c) => c.macAddress.toUpperCase() == '14:C3:5E:26:6F:21'),
          isFalse,
        );
        expect(clients.any((c) => c.ipAddress == '172.16.0.1'), isFalse);

        expect(
          clients.any((c) => c.macAddress.toUpperCase() == 'AA:BB:CC:DD:EE:02'),
          isTrue,
        );
      },
    );
  });

  group('ClientsScreen UI - Vitals and Badges Rendering', () {});
}
