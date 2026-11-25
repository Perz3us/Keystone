// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';

void main() {
  test('stations given as bare MAC addresses are counted', () {
    final o = WirelessOverview.fromDashboardData({
      'wireless': {
        'radio0': {
          'up': true,
          'channel': 6,
          'frequency': 2437,
          'interfaces': [
            {
              'section': 'default_radio0',
              'ifname': 'wlan0',
              'config': {'mode': 'ap', 'ssid': 'Home'},
            },
          ],
        },
      },
      'wirelessStations': {
        'wlan0': {'AA:BB:CC:11:22:33', 'AA:BB:CC:44:55:66'},
      },
    });
    expect(o.radios.single.interfaces.single.stations.length, 2);
  });
}
