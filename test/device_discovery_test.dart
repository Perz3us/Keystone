import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/services/device_discovery.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

void main() {
  test('announcements map to the right kind', () {
    final cases = {
      '_device-info._tcp. model=macbookpro18,3': DeviceKind.laptop,
      '_companion-link._tcp. rpmd=iphone15,2': DeviceKind.phone,
      '_device-info._tcp. model=ipad13,4': DeviceKind.tablet,
      '_device-info._tcp. model=macmini9,1': DeviceKind.computer,
      '_device-info._tcp. model=mac14,2': DeviceKind.laptop,
      '_airplay._tcp. model=appletv6,2': DeviceKind.tv,
      '_raop._tcp. am=audioaccessory5,1': DeviceKind.speaker,
      '_googlecast._tcp. md=chromecast': DeviceKind.tv,
      '_googlecast._tcp. md=google nest mini': DeviceKind.speaker,
      '_ipp._tcp. ty=hp laserjet m110': DeviceKind.printer,
      'microsoft-windows/10.0 upnp/1.0 urn:schemas-upnp-org:device:mediarenderer:1':
          DeviceKind.computer,
      'urn:schemas-upnp-org:device:mediarenderer:1 samsung tizen':
          DeviceKind.tv,
      'xbox upnp/1.0': DeviceKind.console,
      'playstation 5': DeviceKind.console,
      '_hap._tcp. ci=5': DeviceKind.smartHome,
      '_adisk._tcp. _smb._tcp.': DeviceKind.storage,
      '_workstation._tcp.': DeviceKind.computer,
    };
    cases.forEach(
      (hint, kind) => expect(kindFromHint(hint), kind, reason: hint),
    );
    expect(kindFromHint(''), isNull);
    expect(kindFromHint('uuid:1234'), isNull);
    expect(
      kindFromHint('_spotify-connect._tcp. version=1.0 cpath=/zc/0 stack=sp'),
      isNull,
    );
  });

  test('a laptop running Spotify keeps its laptop icon', () {
    final c = Client(
      ipAddress: '192.168.1.183',
      macAddress: 'AA:BB:CC:00:01:83',
      hostname: 'LAPTOP-AB12CD3',
    );
    DeviceDiscovery.instance.value = {
      '192.168.1.183': '_spotify-connect._tcp. version=1.0 cpath=/zc/0',
    };
    expect(ClientNamingHelper.getDeviceIcon(c), Icons.laptop_mac_rounded);
    DeviceDiscovery.instance.value = const {};
  });

  test('a pick wins over the name and is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final c = Client(
      ipAddress: '10.0.0.9',
      macAddress: 'AA:BB:CC:00:00:09',
      hostname: 'Johns-iPhone',
    );
    expect(ClientNamingHelper.getDeviceIcon(c), Icons.phone_android_rounded);
    await DeviceKindStore.instance.set('aa:bb:cc:00:00:09', DeviceKind.console);
    expect(ClientNamingHelper.getDeviceIcon(c), Icons.sports_esports_rounded);
    DeviceKindStore.instance.value = const {};
    await DeviceKindStore.instance.load();
    expect(
      DeviceKindStore.instance.kindOf('AA:BB:CC:00:00:09'),
      DeviceKind.console,
    );
    await DeviceKindStore.instance.set('aa:bb:cc:00:00:09', null);
    expect(ClientNamingHelper.getDeviceIcon(c), Icons.phone_android_rounded);
  });
}
