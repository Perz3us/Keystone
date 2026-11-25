import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/interface.dart';
import 'package:yet_another_luci_app/screens/network/network_screen.dart';

NetworkInterface _i(
  String name,
  String proto, {
  bool up = true,
  String? ip,
  String? gw,
}) => NetworkInterface(
  name: name,
  isUp: up,
  protocol: proto,
  uptime: up ? 7200 : 0,
  device: 'eth0',
  ipAddress: ip,
  gateway: gw,
  dnsServers: const [],
  stats: const {'rx_bytes': 2000000000, 'tx_bytes': 300000000},
);

Widget _app(Widget w) =>
    MaterialApp(theme: KeystoneTheme.buildLightTheme(), home: w);

void main() {
  test('connections in plain words', () {
    expect(connectionName('wan', 'dhcp'), 'Internet');
    expect(connectionName('lan', 'static'), 'Home network');
    expect(connectionName('modem', 'qmiraw'), 'Mobile internet');
    expect(connectionName('modem6', 'dhcpv6'), 'Mobile internet, IPv6');
    expect(connectionName('wg0', 'wireguard'), 'VPN · wg0');
    expect(connectionName('iot', 'static'), 'iot');
    expect(connectionName('openvpn', 'none'), 'VPN · openvpn');
    expect(protocolWords('pppoe'), 'Dial-up login (PPPoE)');
  });

  test('reads the dump: drops loopback, puts the internet first', () {
    final list = readConnections({
      'interfaceDump': {
        'interface': [
          {'interface': 'loopback', 'up': true, 'proto': 'static'},
          {'interface': 'lan', 'up': true, 'proto': 'static'},
          {'interface': 'wan', 'up': false, 'proto': 'dhcp'},
          {'interface': 'modem', 'up': true, 'proto': 'qmiraw'},
        ],
      },
    });
    expect([for (final i in list) i.name], ['modem', 'lan', 'wan']);
  });

  testWidgets('the list opens each connection', (t) async {
    final opened = <String>[];
    var addresses = 0;
    await t.pumpWidget(
      _app(
        NetworkView(
          connections: [
            _i('modem', 'qmiraw', ip: '10.55.85.5'),
            _i('wan', 'dhcp', up: false),
          ],
          onOpen: (i) => opened.add(i.name),
          onAddresses: () => addresses++,
        ),
      ),
    );
    expect(find.text('Up 2 hours · 10.55.85.5'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    await t.tap(find.text('Mobile internet'));
    await t.tap(find.text('Addresses and DNS'));
    expect(opened, ['modem']);
    expect(addresses, 1);
  });

  testWidgets('turning off the one Keystone uses warns first', (t) async {
    final calls = <bool>[];
    await t.pumpWidget(
      _app(
        ConnectionView(
          connection: _i('lan', 'static', ip: '192.168.1.1'),
          signsInThrough: true,
          onSwitch: calls.add,
        ),
      ),
    );
    expect(find.text('Fixed address'), findsOneWidget);
    expect(find.text('2.0 GB down · 300 MB up'), findsOneWidget);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.textContaining('cuts this app off'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(calls, [false]);
  });
}
