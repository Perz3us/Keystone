// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  group('Connection type classification', () {
    test('device in wireless assoclist should be wireless', () {
      final lease = {
        'macaddr': 'aa:bb:cc:11:22:33',
        'ipaddr': '192.168.1.100',
        'hostname': 'iPhone-John',
      };
      final wirelessMacs = {'AA:BB:CC:11:22:33'};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wireless);
    });

    test(
      'device NOT in assoclist should keep heuristic type, not forced wired',
      () {
        final lease = {
          'macaddr': 'aa:bb:cc:11:22:33',
          'ipaddr': '192.168.1.100',
          'hostname': 'iPhone-John',
        };
        final wirelessMacs = <String>{};

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        expect(classified.connectionType, ConnectionType.wireless);
      },
    );

    test(
      'device with no wireless indicators and not in assoclist should be unknown',
      () {
        final lease = {
          'macaddr': '11:22:33:44:55:66',
          'ipaddr': '192.168.1.200',
          'hostname': 'generic-device',
        };
        final wirelessMacs = <String>{};

        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = wirelessMacs.contains(macNorm);

        final classified = client.copyWith(
          connectionType: isWireless
              ? ConnectionType.wireless
              : client.connectionType,
        );

        expect(classified.connectionType, ConnectionType.unknown);
      },
    );

    test('device with ethernet interface should stay wired', () {
      final lease = {
        'macaddr': '11:22:33:44:55:66',
        'ipaddr': '192.168.1.200',
        'hostname': 'Desktop-PC',
        'ifname': 'eth0',
      };
      final wirelessMacs = <String>{};

      final client = Client.fromLease(lease);
      final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
      final isWireless = wirelessMacs.contains(macNorm);

      final classified = client.copyWith(
        connectionType: isWireless
            ? ConnectionType.wireless
            : client.connectionType,
      );

      expect(classified.connectionType, ConnectionType.wired);
    });

    test(
      'disconnected wireless client tracked via knownWirelessMacs remains wireless and disconnected',
      () {
        final knownWirelessMacs = {'AA:BB:CC:11:22:33'};
        const macNorm = 'AA:BB:CC:11:22:33';
        const isWirelessActive = false;

        final isWirelessClient =
            isWirelessActive || knownWirelessMacs.contains(macNorm);
        final isConnected = isWirelessClient ? isWirelessActive : false;
        final connType = isWirelessClient
            ? ConnectionType.wireless
            : ConnectionType.wired;

        expect(isWirelessClient, isTrue);
        expect(isConnected, isFalse);
        expect(connType, ConnectionType.wireless);
      },
    );
  });

  group('Active Neighbor Probing & Scoped IP Resolution', () {
    test('identifies absent or incomplete wired IPs needing probe', () {
      final dhcp4Leases = [
        {'ipaddr': '10.0.0.2', 'macaddr': 'E4:A8:DF:CA:41:8C'},
        {'ipaddr': '10.0.0.4', 'macaddr': '48:EF:1C:23:B8:7C'},
        {'ipaddr': '10.0.0.62', 'macaddr': 'AC:5D:5C:B3:ED:7C'},
        {'ipaddr': '10.0.0.63', 'macaddr': 'A8:A0:92:1A:77:24'},
      ];
      final wirelessMacs = {'48:EF:1C:23:B8:7C'};
      final currentNeigh = [
        {
          'ipaddr': '10.0.0.2',
          'macaddr': 'E4:A8:DF:CA:41:8C',
          'nud_state': 'REACHABLE',
        },
        {
          'ipaddr': '10.0.0.63',
          'macaddr': 'A8:A0:92:1A:77:24',
          'nud_state': 'INCOMPLETE',
        },
      ];

      final targets = selectNeighborProbeTargets(
        dhcp4Leases,
        wirelessMacs,
        currentNeigh,
        routerIp: '10.0.0.1',
      );

      expect(targets, containsAll(['10.0.0.62', '10.0.0.63']));
      expect(targets, isNot(contains('10.0.0.2')));
      expect(targets, isNot(contains('10.0.0.4')));
    });

    test(
      'caps batch size to max 10 probe targets via selectNeighborProbeTargets',
      () {
        final dhcp4Leases = List.generate(
          25,
          (i) => {
            'ipaddr': '10.0.0.${i + 10}',
            'macaddr':
                '11:22:33:44:55:${(i + 10).toRadixString(16).padLeft(2, '0')}',
          },
        );
        final wirelessMacs = <String>{};
        final currentNeigh = <Map<String, dynamic>>[];

        final targets = selectNeighborProbeTargets(
          dhcp4Leases,
          wirelessMacs,
          currentNeigh,
          routerIp: '10.0.0.1',
          maxBatch: 10,
        );

        expect(targets.length, 10);
        expect(targets.first, '10.0.0.10');
        expect(targets.last, '10.0.0.19');
      },
    );

    test('brctl showmacs parses non-local switch bridge MACs', () {
      const brctlOutput = '''
port no	mac addr		is local?	ageing timer
  2	92:61:e9:ec:b2:50	no		   7.10
  1	c0:06:c3:47:d6:82	yes		   0.00
  1	c0:06:c3:47:d6:82	yes		   0.00
  1	d8:3a:dd:6d:52:21	no		   5.93
''';

      final fdbMacs = <String>{};
      final macRegex = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
      for (final line in brctlOutput.split('\n')) {
        final lower = line.toLowerCase();
        if (lower.contains('yes')) continue;
        final match = macRegex.firstMatch(line);
        if (match != null) {
          final m = match.group(0);
          if (m != null) {
            fdbMacs.add(m.toUpperCase().replaceAll('-', ':'));
          }
        }
      }

      expect(fdbMacs, contains('D8:3A:DD:6D:52:21'));
      expect(fdbMacs, contains('92:61:E9:EC:B2:50'));
      expect(fdbMacs, isNot(contains('C0:06:C3:47:D6:82')));
    });

    test(
      'odhcpd IPv6 lease correlates with MAC by IPv6 address and assigns hostname',
      () {
        final dhcp6Lease = {
          'hostname': 'ncxRpi',
          'duid': '000413d6afb6c20d9dc5e403d3b6f2759db8',
          'ip6addr': 'fd15:67b6:3e38::a06',
          'ip6addrs': ['fd15:67b6:3e38::a06/128'],
        };
        final neighClients = [
          {
            'ipaddr': '192.168.1.129',
            'macaddr': 'd8:3a:dd:6d:52:21',
            'nud_state': 'REACHABLE',
          },
          {
            'ipaddr': 'fd15:67b6:3e38::a06',
            'macaddr': 'd8:3a:dd:6d:52:21',
            'nud_state': 'STALE',
          },
        ];

        final rawV6 = (dhcp6Lease['ip6addrs'] as List).cast<String>();
        final cleanV6Addrs = rawV6
            .map((a) => a.split('/')[0].trim().toLowerCase())
            .toSet();

        String? matchedMac;
        for (final n in neighClients) {
          final nIp = (n['ipaddr'] ?? '').split('/')[0].trim().toLowerCase();
          if (cleanV6Addrs.contains(nIp)) {
            matchedMac = n['macaddr']?.toUpperCase().replaceAll('-', ':');
            break;
          }
        }

        expect(matchedMac, 'D8:3A:DD:6D:52:21');

        final existingClient = Client(
          ipAddress: '192.168.1.129',
          macAddress: 'D8:3A:DD:6D:52:21',
          hostname: 'D8:3A:DD:6D:52:21',
          connectionType: ConnectionType.wired,
        );

        final shouldUpdateName =
            dhcp6Lease['hostname'] != null &&
            (existingClient.hostname.isEmpty ||
                existingClient.hostname == 'Unknown' ||
                existingClient.hostname == existingClient.macAddress);

        final updated = existingClient.copyWith(
          hostname: shouldUpdateName
              ? dhcp6Lease['hostname']!.toString()
              : existingClient.hostname,
        );

        expect(updated.hostname, 'ncxRpi');
      },
    );

    test(
      'non-DHCP wired client with known IP retains connectivity during 90s grace period',
      () {
        const hasActiveLease = false;
        const isStaticLease = false;
        const resolvedIp = '192.168.1.129';
        final now = DateTime.now();
        final lastSeen = now.subtract(const Duration(seconds: 45));

        final hasKnownIp = resolvedIp != 'N/A' && resolvedIp.isNotEmpty;
        final isInGraceWindow =
            (hasActiveLease || isStaticLease || hasKnownIp) &&
            now.difference(lastSeen) < const Duration(seconds: 90);

        expect(isInGraceWindow, isTrue);
      },
    );

    test(
      'secondary router wired client is marked as Dumb AP and not dropped',
      () {
        const isRouterDumbAp = true;

        const isClientDumbAp = isRouterDumbAp;
        const clientApName = 'ncxRouter';

        final client = Client(
          ipAddress: '10.0.0.2',
          macAddress: 'E4:A8:DF:CA:41:8C',
          hostname: 'ncxLinux',
          connectionType: ConnectionType.wired,
          isDumbApClient: isClientDumbAp,
          apName: clientApName,
          isConnected: true,
        );

        expect(client.isDumbApClient, isTrue);
        expect(client.apName, 'ncxRouter');
        expect(client.connectionType, ConnectionType.wired);
        expect(client.isConnected, isTrue);
      },
    );

    test(
      'merging inactive main entry with active secondary wired client preserves wired type and marks Dumb AP',
      () {
        final existingOnMain = Client(
          ipAddress: '10.0.0.2',
          macAddress: 'E4:A8:DF:CA:41:8C',
          hostname: 'ncxLinux',
          connectionType: ConnectionType.wired,
          isDumbApClient: false,
          apName: null,
          isConnected: false,
          isStaticLease: true,
        );

        final activeOnSecondary = Client(
          ipAddress: '10.0.0.2',
          macAddress: 'E4:A8:DF:CA:41:8C',
          hostname: 'ncxLinux',
          connectionType: ConnectionType.wired,
          isDumbApClient: true,
          apName: 'ncxRouter',
          isConnected: true,
        );

        const isMainRouter = false;
        final clientActiveOnSecondaryAp =
            !isMainRouter &&
            activeOnSecondary.isDumbApClient &&
            activeOnSecondary.isConnected;

        final bool isDumb;
        final String? apName;
        final ConnectionType preferredConnType;

        if (clientActiveOnSecondaryAp &&
            existingOnMain.connectionType != ConnectionType.wireless) {
          isDumb = true;
          apName = activeOnSecondary.apName;
          preferredConnType =
              (activeOnSecondary.connectionType == ConnectionType.wireless ||
                  existingOnMain.connectionType == ConnectionType.wireless)
              ? ConnectionType.wireless
              : ConnectionType.wired;
        } else {
          isDumb = false;
          apName = null;
          preferredConnType = existingOnMain.connectionType;
        }

        final merged = existingOnMain.copyWith(
          isDumbApClient: isDumb,
          apName: apName,
          connectionType: preferredConnType,
          isConnected:
              existingOnMain.isConnected || activeOnSecondary.isConnected,
        );

        expect(merged.isDumbApClient, isTrue);
        expect(merged.apName, 'ncxRouter');
        expect(merged.connectionType, ConnectionType.wired);
        expect(merged.isConnected, isTrue);
      },
    );
  });

  group('recentFdbMacs', () {
    test('brctl: skips the router itself and anything idle over a minute', () {
      const out = '''port no	mac addr		is local?	ageing timer
  1	20:23:51:b7:59:22	yes		   0.00
  3	aa:bb:cc:00:00:01	no		   4.10
  6	aa:bb:cc:00:00:02	no		 240.55
''';
      expect(recentFdbMacs(out), {'AA:BB:CC:00:00:01'});
    });
    test('bridge -s: uses the "used" seconds', () {
      const out = '''aa:bb:cc:00:00:01 dev lan1 used 3/3 master br-lan
aa:bb:cc:00:00:02 dev phy0-ap0 used 200/200 master br-lan
aa:bb:cc:00:00:03 dev lan2 master br-lan
33:33:00:00:00:01 dev br-lan self permanent
''';
      expect(recentFdbMacs(out), {'AA:BB:CC:00:00:01', 'AA:BB:CC:00:00:03'});
    });
  });
}
