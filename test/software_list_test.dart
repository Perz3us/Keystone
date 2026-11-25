// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/package_manager/models/package_info.dart';
import 'package:yet_another_luci_app/modules/package_manager/screens/package_manager_screen.dart';

OpenWrtPackage pkg(String name, {bool installed = true, String about = ''}) =>
    OpenWrtPackage(
      name: name,
      version: '1.0',
      description: about,
      isInstalled: installed,
    );

void main() {
  final o = PackageManagerOverview(
    activeManager: PackageManagerType.apk,
    installedPackages: [
      pkg('busybox'),
      pkg('libcurl4'),
      pkg('kmod-usb-net'),
      pkg('ath11k-firmware-ipq8074'),
      pkg('samba4-server', about: 'Share drives'),
      pkg('luci-app-sqm'),
    ],
    availablePackages: [
      pkg('samba4-server'),
      pkg('adguardhome', installed: false, about: 'Blocks ads'),
    ],
    discoveredLuciApps: const [],
  );

  test('core and system parts are hidden unless asked for', () {
    expect(softwareList(o, SoftwareTab.installed, '').map((p) => p.name), [
      'samba4-server',
      'luci-app-sqm',
    ]);
    expect(
      softwareList(o, SoftwareTab.installed, '', everything: true),
      hasLength(6),
    );
    expect(isCorePackage('busybox'), isTrue);
    expect(isCorePackage('samba4-server'), isFalse);
  });

  test('get more lists only what is not installed, and search finds it', () {
    expect(softwareList(o, SoftwareTab.available, '').map((p) => p.name), [
      'adguardhome',
    ]);
    expect(softwareList(o, SoftwareTab.available, 'ads').map((p) => p.name), [
      'adguardhome',
    ]);
    expect(softwareList(o, SoftwareTab.available, 'zzz'), isEmpty);
  });

  test('sizes read plainly', () {
    expect(sizeWords('512'), '512 B');
    expect(sizeWords('2048'), '2 KB');
    expect(sizeWords('1572864'), '1.5 MB');
    expect(sizeWords('?'), isNull);
  });

  test('apk list lines are read; installed ones are not offered', () {
    final o = PackageManagerOverview.fromDashboardData({
      'installedPackages': 'adb 5.0.2 Android tool\n',
      'availablePackages':
          'adb-5.0.2~6fe92d1a-r4 aarch64_cortex-a53 {feeds/base/utils/adb} () [installed]\n'
          'ath11k-firmware-ipq8074-2024.10.14~15f05012-r1 aarch64_cortex-a53 {feeds/base/firmware} (ISC)\n'
          'adguardhome-0.107.55-r1 aarch64_cortex-a53 {feeds/packages/net/adguardhome} (GPL-3.0-only)\n',
    });
    expect(o.availablePackages.map((p) => (p.name, p.version)), [
      ('ath11k-firmware-ipq8074', '2024.10.14~15f05012-r1'),
      ('adguardhome', '0.107.55-r1'),
    ]);
    expect(o.availablePackages.last.license, 'GPL-3.0-only');
  });

  test('descriptions are cut to their first sentence', () {
    expect(shortAbout('Share drives. It also does more.'), 'Share drives');
    expect(shortAbout('x' * 120).length, 88);
  });
}
