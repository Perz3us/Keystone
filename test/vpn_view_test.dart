// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/models/vpn_info.dart';
import 'package:yet_another_luci_app/modules/vpn_connectivity/screens/vpn_connectivity_screen.dart';

VpnConnectivityOverview overview(Map<String, dynamic> data) =>
    VpnConnectivityOverview.fromDashboardData(data);

void main() {
  test('only what is set up is listed, in plain words', () {
    final items = vpnItems(
      overview({
        'wireguard': {
          'wg0': {
            'public_key': 'k',
            'listen_port': 51820,
            'up': true,
            'peers': [
              {'public_key': 'p1', 'allowed_ips': <String>[]},
            ],
          },
        },
        'tailscale': {
          'configured': true,
          'running': true,
          'hostname': 'Home',
          'ip': '100.64.0.15',
          'state': 'Running',
          'peers_count': 4,
        },
        'openvpn': {
          'sample_client': {'enabled': '0'},
          'office': {'enabled': '1', 'running': false},
        },
      }),
    );
    expect(items.map((i) => i.title), [
      'WireGuard · wg0',
      'OpenVPN · office',
      'Tailscale · Home',
    ]);
    expect(items[0].line, 'On · 1 peer');
    expect(items[0].on, isNull, reason: 'WireGuard opens its Network page');
    expect(items[1].line, 'On, not connected yet');
    expect(items[2].line, 'Connected · 100.64.0.15 · 4 devices');
  });

  test('Tailscale waiting for a sign-in says so', () {
    final items = vpnItems(
      overview({
        'tailscale': {'configured': true, 'state': 'NeedsLogin'},
      }),
    );
    expect(items.single.line, startsWith('Needs signing in'));
  });

  testWidgets('switches toggle; WireGuard opens', (tester) async {
    final toggled = <String>[];
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VpnView(
            items: const [
              VpnItem(
                kind: VpnKind.wireguard,
                id: 'wg0',
                title: 'WireGuard · wg0',
                line: 'On',
              ),
              VpnItem(
                kind: VpnKind.nextdns,
                id: 'nextdns',
                title: 'NextDNS',
                line: 'Off',
                on: false,
              ),
            ],
            onToggle: (i, on) => toggled.add('${i.id}:$on'),
            onOpen: (i) => opened.add(i.id),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('WireGuard · wg0'));
    expect(toggled, ['nextdns:true']);
    expect(opened, ['wg0']);
  });

  testWidgets('nothing set up explains what would show', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VpnView(items: const [], onToggle: (_, _) {}, onOpen: (_) {}),
        ),
      ),
    );
    expect(find.textContaining('No other VPN is set up'), findsOneWidget);
  });
}
