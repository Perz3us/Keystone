// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('Client Access Control & Live Router Query', () {
    late MockApiService mockApiService;

    setUp(() {
      mockApiService = MockApiService();
    });

    test('pauseClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: true,
      );
      expect(success, isTrue);
    });

    test('resumeClientInternet succeeds in mock service', () async {
      final success = await mockApiService.pauseClientInternet(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'AA:BB:CC:11:22:33',
        pause: false,
      );
      expect(success, isTrue);
    });

    test('banWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.banWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
        iface: 'wlan0',
      );
      expect(success, isTrue);
    });

    test('unbanWirelessClient succeeds in mock service', () async {
      final success = await mockApiService.unbanWirelessClient(
        '192.168.1.1',
        'mock-sysauth',
        false,
        macAddress: 'DD:EE:FF:44:55:66',
      );
      expect(success, isTrue);
    });

    test(
      'fetchRestrictedAndBannedClientsLive returns direct router status',
      () async {
        final data = await mockApiService.fetchRestrictedAndBannedClientsLive(
          '192.168.1.1',
          'mock-sysauth',
          false,
        );

        expect(data, contains('restricted'));
        expect(data, contains('banned'));
        expect(data['restricted'], isNotEmpty);
        expect(data['banned'], isNotEmpty);
        expect(data['restricted']!.first['mac'], equals('11:22:33:44:55:66'));
        expect(data['banned']!.first['mac'], equals('99:88:77:66:55:44'));
      },
    );
  });

  group('RealApiService Client Ban & Fast Unban Pipeline', () {
    test(
      'unbanWirelessClient fast-path completes immediately without service reload when no rules exist',
      () async {
        final executedCalls = <String>[];
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            executedCalls.add('$object.$method');
            if (object == 'uci' && method == 'get') {
              return [
                0,
                {
                  'values': {
                    'rule1': {
                      '.type': 'rule',
                      'name': 'Allow-DNS',
                      'target': 'ACCEPT',
                    },
                    'wifinet1': {
                      '.type': 'wifi-iface',
                      'macfilter': 'allow',
                      'maclist': ['AA:BB:CC:DD:EE:FF'],
                    },
                  },
                },
              ];
            }
            if (object.startsWith('hostapd.') && method == 'del_client') {
              return [0];
            }
            if (object == 'file' && method == 'exec') {
              return [
                0,
                {'code': 0, 'stdout': ''},
              ];
            }
            return [0];
          },
          mockObjects: ['hostapd.phy0-ap0', 'hostapd.phy1-ap0'],
        );

        final result = await testApi.unbanWirelessClient(
          '10.0.0.1',
          'token',
          false,
          macAddress: '11:22:33:44:55:66',
        );

        expect(result, isTrue);
        expect(executedCalls, contains('hostapd.phy0-ap0.del_client'));
        expect(executedCalls, contains('hostapd.phy1-ap0.del_client'));
        expect(executedCalls, contains('uci.get'));
        expect(executedCalls, isNot(contains('uci.commit')));
        expect(executedCalls, isNot(contains('rc.init')));
        expect(executedCalls, isNot(contains('network.wireless.up')));
      },
    );

    test(
      'disconnectWirelessClient discovers hostapd.* and calls del_client natively',
      () async {
        final delClientCalls = <String>[];
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object.startsWith('hostapd.') && method == 'del_client') {
              delClientCalls.add(object);
              return [0];
            }
            if (object == 'file' && method == 'exec') {
              return [
                0,
                {'code': 0, 'stdout': ''},
              ];
            }
            return [0];
          },
          mockObjects: [
            'hostapd.phy0-ap0',
            'hostapd.phy1-ap0',
            'hostapd.phy2-ap0',
          ],
        );

        final result = await testApi.disconnectWirelessClient(
          '10.0.0.1',
          'token',
          false,
          macAddress: 'C0:06:C3:47:D6:83',
          banTimeSeconds: 600,
        );

        expect(result, isTrue);
        expect(delClientCalls, contains('hostapd.phy0-ap0'));
        expect(delClientCalls, contains('hostapd.phy1-ap0'));
        expect(delClientCalls, contains('hostapd.phy2-ap0'));
      },
    );

    test(
      'fetchRestrictedAndBannedClientsLive ignores allowlist maclist in ubus fallback',
      () async {
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object == 'file' && method == 'exec') {
              return [6];
            }
            if (object == 'uci' &&
                method == 'get' &&
                params?['config'] == 'wireless') {
              return [
                0,
                {
                  'values': {
                    'wifinet1': {
                      '.type': 'wifi-iface',
                      'macfilter': 'allow',
                      'maclist': ['48:EF:1C:23:B8:7C', '2C:BE:EB:62:28:DC'],
                    },
                    'wifinet2': {
                      '.type': 'wifi-iface',
                      'macfilter': 'deny',
                      'maclist': ['99:88:77:66:55:44'],
                    },
                  },
                },
              ];
            }
            if (object == 'uci' &&
                method == 'get' &&
                params?['config'] == 'firewall') {
              return [
                0,
                {
                  'values': {
                    'rule_pause': {
                      '.type': 'rule',
                      'name': 'Pause_Internet_112233445566',
                      'target': 'DROP',
                      'src_mac': '11:22:33:44:55:66',
                    },
                  },
                },
              ];
            }
            return [0];
          },
          mockObjects: [],
        );

        final data = await testApi.fetchRestrictedAndBannedClientsLive(
          '10.0.0.1',
          'token',
          false,
        );

        expect(
          data['banned']!.map((e) => e['mac']),
          contains('99:88:77:66:55:44'),
        );
        expect(
          data['banned']!.map((e) => e['mac']),
          isNot(contains('48:EF:1C:23:B8:7C')),
        );
        expect(
          data['banned']!.map((e) => e['mac']),
          isNot(contains('2C:BE:EB:62:28:DC')),
        );

        expect(
          data['restricted']!.map((e) => e['mac']),
          contains('11:22:33:44:55:66'),
        );
      },
    );

    test('resuming a paused client keeps its ban and the user rules', () async {
      const mac = '02:AA:BB:CC:DD:09';
      final r = _routerWithBlocks(mac);
      final ok = await r.api.pauseClientInternet(
        '192.168.1.1',
        'token',
        false,
        macAddress: mac,
        pause: false,
      );
      expect(ok, isTrue);
      expect(r.fw.keys, unorderedEquals(['ban', 'mine']));
      expect(r.scripts.where((s) => s.contains('nft delete')), isEmpty);
    });

    test('block flush reloads first, then drops the device flows', () {
      final s = RealApiService.blockFlushScript('20:47:DA:56:00:B7');
      expect(s, contains("grep -i '20:47:DA:56:00:B7'"));
      expect(s, contains('/tmp/dhcp.leases'));
      expect(s, contains('hook prerouting priority -300'));
      expect(s, contains('firewall.keystone_block.path=/etc/keystone/block.fw'));
      expect(s.indexOf('cat > /etc/keystone/block.fw'), lessThan(s.indexOf('reload')));
      final reload = s.indexOf('/etc/init.d/firewall reload');
      expect(reload, greaterThanOrEqualTo(0));
      expect(s.indexOf('conntrack -D'), greaterThan(reload));
    });

    test('later calls reuse a renewed session token', () {
      final api = RealApiService();
      expect(api.currentToken('a'), 'a');
      api.rememberRenewedToken('a', 'b');
      api.rememberRenewedToken('b', 'c');
      expect(api.currentToken('a'), 'c');
      expect(api.currentToken('b'), 'c');
      api.rememberRenewedToken('c', 'c');
      expect(api.currentToken('c'), 'c');
    });

    test('unbanning a client keeps its pause and the user rules', () async {
      const mac = '02:AA:BB:CC:DD:09';
      final r = _routerWithBlocks(mac);
      await r.api.unbanWirelessClient(
        '192.168.1.1',
        'token',
        false,
        macAddress: mac,
      );
      expect(r.fw.keys, unorderedEquals(['pause', 'mine']));
    });

    test(
      'banWirelessClient on multiple wired clients updates the same Ban_Client_List firewall rule',
      () async {
        final Map<String, dynamic> firewallValues = {};
        final testApi = _TestableRealApiService(
          onCall: (object, method, params) async {
            if (object == 'uci' && method == 'get') {
              return [
                0,
                {'values': firewallValues},
              ];
            }
            if (object == 'uci' && method == 'add') {
              final secKey = 'rule_ban_${firewallValues.length + 1}';
              firewallValues[secKey] = {
                '.type': 'rule',
                ...params?['values'] as Map<String, dynamic>,
              };
              return [
                0,
                {'section': secKey},
              ];
            }
            if (object == 'uci' && method == 'set') {
              final sec = params?['section'] as String;
              if (firewallValues.containsKey(sec)) {
                final values = params?['values'] as Map<String, dynamic>;
                firewallValues[sec].addAll(values);
              }
              return [0];
            }
            if (object == 'uci' && method == 'delete') {
              final sec = params?['section'] as String;
              firewallValues.remove(sec);
              return [0];
            }
            if (object == 'uci' && method == 'commit') return [0];
            if (object == 'rc' && method == 'init') return [0];
            if (object == 'file' && method == 'exec') {
              return [
                0,
                {'code': 0, 'stdout': ''},
              ];
            }
            return [0];
          },
          mockObjects: [],
        );

        final res1 = await testApi.banWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:01',
        );
        expect(res1, isTrue);
        expect(firewallValues.length, equals(1));
        final secKey1 = firewallValues.keys.first;
        expect(firewallValues[secKey1]['name'], equals('Ban_Client_List'));
        expect(
          firewallValues[secKey1]['src_mac'],
          equals(['02:AA:BB:CC:DD:01']),
        );

        final res2 = await testApi.banWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:02',
        );
        expect(res2, isTrue);
        expect(firewallValues.length, equals(1));
        expect(
          firewallValues[secKey1]['src_mac'],
          equals(['02:AA:BB:CC:DD:01', '02:AA:BB:CC:DD:02']),
        );

        final unban1 = await testApi.unbanWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:01',
        );
        expect(unban1, isTrue);
        expect(firewallValues.length, equals(1));
        expect(
          firewallValues[secKey1]['src_mac'],
          equals(['02:AA:BB:CC:DD:02']),
        );

        final unban2 = await testApi.unbanWirelessClient(
          '192.168.1.1',
          'token',
          false,
          macAddress: '02:AA:BB:CC:DD:02',
        );
        expect(unban2, isTrue);
        expect(firewallValues.isEmpty, isTrue);
      },
    );
  });
}

({_TestableRealApiService api, Map<String, dynamic> fw, List<String> scripts})
_routerWithBlocks(String mac) {
  final fw = <String, dynamic>{
    'ban': {
      '.type': 'rule',
      'name': 'Ban_Client_List',
      'src_mac': [mac],
      'target': 'DROP',
    },
    'pause': {
      '.type': 'rule',
      'name': 'nointernet_wireless_clients',
      'src_mac': [mac],
      'target': 'DROP',
    },
    'mine': {
      '.type': 'rule',
      'name': 'Kids_bedtime',
      'src_mac': [mac],
      'target': 'REJECT',
    },
  };
  final scripts = <String>[];
  final api = _TestableRealApiService(
    onCall: (object, method, params) async {
      if (object == 'uci' && method == 'get') {
        return [
          0,
          {'values': fw},
        ];
      }
      if (object == 'uci' && method == 'set') {
        final sec = params?['section'] as String;
        (fw[sec] as Map).addAll(params?['values'] as Map<String, dynamic>);
        return [0];
      }
      if (object == 'uci' && method == 'delete') {
        fw.remove(params?['section']);
        return [0];
      }
      if (object == 'file' && method == 'exec') {
        final p = params?['params'];
        if (p is List && p.length > 1) scripts.add(p[1].toString());
        return [
          0,
          {'code': 0, 'stdout': ''},
        ];
      }
      return [0];
    },
    mockObjects: [],
  );
  return (api: api, fw: fw, scripts: scripts);
}

class _TestableRealApiService extends RealApiService {
  final Future<dynamic> Function(
    String object,
    String method,
    Map<String, dynamic>? params,
  )
  onCall;
  final List<String> mockObjects;

  _TestableRealApiService({required this.onCall, required this.mockObjects});

  @override
  Future<List<String>> listUbusObjects(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String? pattern,
    BuildContext? context,
  }) async {
    return mockObjects;
  }

  @override
  Future<dynamic> callWithContext(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
    bool isRetry = false,
  }) async {
    return onCall(object, method, params);
  }
}
