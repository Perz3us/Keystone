// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/services/app_update.dart';

Client _c(String mac, String name, double bytesPerSec) => Client(
  ipAddress: '192.168.1.2',
  macAddress: mac,
  hostname: name,
  isConnected: true,
  rxSpeed: bytesPerSec,
);

void main() {
  test('settings survive a save and load, bad values fall back', () {
    const p = HomePrefs(
      layout: HomeLayout.topDown,
      deviceCount: 3,
      pick: HomePick.pinned,
      pinned: ['aa:bb'],
      flow: false,
      unit: SpeedUnit.mbs,
    );
    final back = HomePrefs.fromJson(p.toJson());
    expect(back.layout, HomeLayout.topDown);
    expect(back.deviceCount, 3);
    expect(back.pinned, ['aa:bb']);
    expect(back.unit, SpeedUnit.mbs);
    final bad = HomePrefs.fromJson({'layout': 'diagonal', 'deviceCount': 9});
    expect(bad.layout, HomeLayout.side);
    expect(bad.deviceCount, 4);
    expect(HomePrefs.fromJson({'deviceCount': 5}).deviceCount, 5);
  });

  test('the busiest devices come first, pinned ones before them', () {
    final online = [
      _c('AA:00', 'Phone', 100000),
      _c('AA:01', 'TV', 2000000),
      _c('AA:02', 'Laptop', 0),
      _c('AA:03', 'PS5', 500000),
      _c('AA:04', 'Watch', 0),
    ];
    expect(
      pickFlowDevices(online, const HomePrefs()).map((c) => c.displayName),
      ['TV', 'PS5', 'Phone', 'Laptop'],
    );
    expect(
      pickFlowDevices(
        online,
        const HomePrefs(
          pick: HomePick.pinned,
          pinned: ['aa:04'],
          deviceCount: 3,
        ),
      ).map((c) => c.displayName),
      ['Watch', 'TV', 'PS5'],
    );
  });

  test('version compare', () {
    expect(isNewerVersion('v1.0.1', '1.0.0'), isTrue);
    expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(isNewerVersion('v1.2', '1.10.0'), isFalse);
    expect(isNewerVersion('2.0.0+5', '1.9.9'), isTrue);
  });
}
