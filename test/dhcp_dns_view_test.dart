import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/screens/dhcp_dns_screen.dart';

const _o = DhcpDnsOverview(
  dnsConfig: DnsmasqConfig(
    localDomain: 'lan',
    upstreamDnsServers: ['1.1.1.1'],
    rebindProtection: true,
    domainNeeded: true,
    authoritative: true,
  ),
  activeLeases: [
    DhcpLease(
      hostname: 'android-1',
      ipAddress: '192.168.1.20',
      macAddress: 'AA:00:00:00:00:01',
      expirySeconds: 597240,
    ),
  ],
  activeDhcp6Leases: [],
  staticMappings: [
    DhcpStaticMapping(
      hostname: 'nas',
      ipAddress: '192.168.1.5',
      macAddress: 'AA:00:00:00:00:05',
    ),
  ],
  configuredSubnets: [],
);

void main() {
  testWidgets('names, fixed addresses and what is given out', (t) async {
    final calls = <String>[];
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: DhcpDnsView(
          overview: _o,
          nameFor: (mac) => mac.endsWith('01') ? 'Phone' : null,
          onRestart: () => calls.add('restart'),
          onAddFixed: () => calls.add('add'),
          onFixed: (m) => calls.add('fixed ${m.hostname}'),
          onLease: (l) => calls.add('lease ${l.ipAddress}'),
        ),
      ),
    );
    expect(find.text('Addresses and DNS'), findsOneWidget);
    expect(find.text('1.1.1.1'), findsOneWidget);
    expect(find.text('.lan'), findsOneWidget);
    expect(find.text('192.168.1.5 · AA:00:00:00:00:05'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Phone'), 200);
    expect(find.text('192.168.1.20 · Ends in 6 d 21 h'), findsOneWidget);

    await t.tap(find.text('Phone'));
    await t.tap(find.text('nas'));
    await t.tap(find.text('Add'));
    expect(calls, ['lease 192.168.1.20', 'fixed nas', 'add']);
  });
}
