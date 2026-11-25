// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';

void main() {
  group('Wireless txpower NaN and Auto handling tests', () {
    test('WirelessRadio.fromJson safely parses config with txpower auto', () {
      final radio = WirelessRadio.fromJson('radio0', {
        'up': true,
        'config': {
          'channel': '1',
          'htmode': 'HT20',
          'country': 'IN',
          'txpower': 'auto',
          'frequency': '2412',
        },
        'interfaces': [],
      }, null);

      expect(radio.name, 'radio0');
      expect(radio.channel, '1');
      expect(radio.txPowerDbm, isNull);
      expect(radio.frequency, 2412);
      expect(radio.country, 'IN');
    });

    test('WirelessStation.fromJson safely parses string/null metrics', () {
      final station = WirelessStation.fromJson('AA:BB:CC:DD:EE:FF', {
        'signal': '-65',
        'noise': '-90',
        'rx_rate': '54.0',
        'tx_rate': '72.2',
        'inactive': '10',
      });

      expect(station.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(station.signalDbm, -65);
      expect(station.noiseDbm, -90);
      expect(station.rxRate, 54.0);
      expect(station.txRate, 72.2);
      expect(station.inactiveSeconds, 10);
    });

    test(
      'WirelessOverview.fromDashboardData handles uci txpower auto and null wireless',
      () {
        final dashboardData = {
          'wireless': <String, dynamic>{},
          'uciWirelessConfig': {
            'values': {
              'radio0': {
                '.type': 'wifi-device',
                '.name': 'radio0',
                'channel': '1',
                'country': 'IN',
                'txpower': 'auto',
              },
              'default_radio0': {
                '.type': 'wifi-iface',
                '.name': 'default_radio0',
                'device': 'radio0',
                'ssid': 'MySSID',
                'disabled': '0',
              },
            },
          },
        };

        final overview = WirelessOverview.fromDashboardData(dashboardData);
        expect(overview.radios.length, 1);
        expect(overview.radios.first.name, 'radio0');
        expect(overview.radios.first.txPowerDbm, isNull);
        expect(overview.radios.first.interfaces.length, 1);
        expect(overview.radios.first.interfaces.first.ssid, 'MySSID');
      },
    );
  });
}
