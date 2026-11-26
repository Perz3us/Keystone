import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/utils/internet_link.dart';

const _default = [
  {'target': '0.0.0.0', 'mask': 0},
];

void main() {
  test('a modem link with the default route', () {
    final i = internetInterface([
      {'interface': 'lan', 'device': 'br-lan'},
      {'interface': 'loopback', 'l3_device': 'lo'},
      {'interface': 'modem', 'l3_device': 'wwan0', 'route': _default},
    ]);
    expect(i?['interface'], 'modem');
    expect(linkDevice(i!), 'wwan0');
  });

  test('wan wins over a full-tunnel VPN', () {
    final i = internetInterface([
      {'interface': 'awg', 'proto': 'wireguard', 'route': _default},
      {
        'interface': 'wan',
        'device': 'eth0.2',
        'l3_device': 'pppoe-wan',
        'route': _default,
      },
    ]);
    expect(linkDevice(i!), 'pppoe-wan');
  });

  test('a down wan is still found by name', () {
    final i = internetInterface([
      {'interface': 'lan', 'device': 'br-lan'},
      {'interface': 'wan', 'device': 'eth1'},
    ]);
    expect(i?['interface'], 'wan');
    expect(internetInterface(const []), isNull);
  });

  test('the firewall zone that holds the internet link', () {
    final zones = {
      'cfg1': {
        '.type': 'zone',
        'name': 'lan',
        'network': ['lan'],
      },
      'cfg2': {
        '.type': 'zone',
        'name': 'internet',
        'network': ['wan', 'modem'],
      },
    };
    expect(internetZone(zones, 'modem'), 'internet');
    expect(
      internetZone({
        'z': {'.type': 'zone', 'name': 'up', 'network': 'wan modem'},
      }, 'modem'),
      'up',
    );
    expect(internetZone(const {}, 'modem'), 'wan');
    expect(internetZone(zones, null), 'wan');
  });
}
