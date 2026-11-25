// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';

void main() {
  group('Client.fromWirelessStation', () {
    test('creates a client from just a MAC address', () {
      final client = Client.fromWirelessStation('AA:BB:CC:DD:EE:FF');

      expect(client.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(client.connectionType, ConnectionType.wireless);
      expect(client.ipAddress, 'N/A');
      expect(client.hostname, 'Unknown');
    });

    test('handles lowercase MAC address', () {
      final client = Client.fromWirelessStation('aa:bb:cc:dd:ee:ff');

      expect(client.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(client.connectionType, ConnectionType.wireless);
    });

    test('has no lease time or active time', () {
      final client = Client.fromWirelessStation('AA:BB:CC:DD:EE:FF');

      expect(client.leaseTime, isNull);
      expect(client.activeTime, isNull);
      expect(client.expiresAt, isNull);
    });
  });

  group('AP-mode client merging logic', () {
    test('wireless MACs not in DHCP produce fallback clients', () {
      final dhcpLeases = <Map<String, dynamic>>[];
      final wirelessMacs = {'AA:BB:CC:11:22:33', 'AA:BB:CC:44:55:66'};

      final clients = Client.buildMergedClientList(dhcpLeases, wirelessMacs);

      expect(clients, hasLength(2));
      expect(
        clients.every((c) => c.connectionType == ConnectionType.wireless),
        isTrue,
      );
      expect(
        clients.map((c) => c.macAddress.toUpperCase()).toSet(),
        wirelessMacs,
      );
    });

    test('wireless MACs already in DHCP are not duplicated', () {
      final dhcpLeases = <Map<String, dynamic>>[
        {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        },
      ];
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final clients = Client.buildMergedClientList(dhcpLeases, wirelessMacs);

      expect(clients, hasLength(1));
      expect(clients.first.hostname, 'iPhone-John');
      expect(clients.first.ipAddress, '192.168.1.100');
      expect(clients.first.connectionType, ConnectionType.wireless);
    });

    test('mix of DHCP and wireless-only clients', () {
      final dhcpLeases = <Map<String, dynamic>>[
        {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        },
        {
          'macaddr': 'dd:ee:ff:11:22:33',
          'ipaddr': '192.168.1.200',
          'hostname': 'Desktop-PC',
        },
      ];
      final wirelessMacs = {'AA:BB:CC:11:22:33', 'AA:BB:CC:99:88:77'};

      final clients = Client.buildMergedClientList(dhcpLeases, wirelessMacs);

      expect(clients, hasLength(3));

      final wirelessClients = clients
          .where((c) => c.connectionType == ConnectionType.wireless)
          .toList();
      expect(wirelessClients, hasLength(2));

      final wiredClients = clients
          .where((c) => c.connectionType == ConnectionType.wired)
          .toList();
      expect(wiredClients, hasLength(1));
      expect(wiredClients.first.hostname, 'Desktop-PC');
    });

    test('empty DHCP and empty wireless returns no clients', () {
      final clients = Client.buildMergedClientList([], {});
      expect(clients, isEmpty);
    });
  });

  group('Dumb AP tagging in Client.buildMergedClientList', () {
    test(
      'tags fallback wireless clients as Dumb AP clients when isDumbAp is true',
      () {
        final dhcpLeases = <Map<String, dynamic>>[];
        final wirelessMacs = {'AA:BB:CC:11:22:33'};

        final clients = Client.buildMergedClientList(
          dhcpLeases,
          wirelessMacs,
          isDumbAp: true,
          apName: 'Dumb AP Bedroom',
        );

        expect(clients, hasLength(1));
        expect(clients.first.isDumbApClient, isTrue);
        expect(clients.first.apName, 'Dumb AP Bedroom');
      },
    );

    test('tags DHCP clients as Dumb AP clients when isDumbAp is true', () {
      final dhcpLeases = <Map<String, dynamic>>[
        {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.50',
          'hostname': 'LivingRoom-TV',
        },
      ];
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final clients = Client.buildMergedClientList(
        dhcpLeases,
        wirelessMacs,
        isDumbAp: true,
        apName: 'Dumb AP Living Room',
      );

      expect(clients, hasLength(1));
      expect(clients.first.isDumbApClient, isTrue);
      expect(clients.first.apName, 'Dumb AP Living Room');
    });
  });
}
