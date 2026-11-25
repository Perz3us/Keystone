import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_tab.dart';

WirelessInterface ap(
  String section,
  String ssid, {
  int stations = 0,
  bool enabled = true,
  String mode = 'AP',
  WifiSecurityMode sec = WifiSecurityMode.wpa2Psk,
}) => WirelessInterface(
  ifName: section,
  sectionName: section,
  ssid: ssid,
  mode: mode,
  encryption: 'psk2',
  securityMode: sec,
  pmfState: PmfState.disabled,
  channel: '1',
  isEnabled: enabled,
  stations: [
    for (var i = 0; i < stations; i++)
      WirelessStation.fromJson('AA:00:00:00:00:0$i', const {}),
  ],
  key: 'pw',
);

WirelessRadio radio(
  String name,
  int mhz,
  List<WirelessInterface> i, {
  bool disabled = false,
}) => WirelessRadio(
  name: name,
  isUp: !disabled,
  channel: '1',
  frequency: mhz,
  country: 'US',
  isDisabled: disabled,
  interfaces: i,
);

void main() {
  test('home on two bands, guest apart, clients mode ignored', () {
    final s = WifiSetup(
      WirelessOverview(
        radios: [
          radio('radio0', 2437, [
            ap('default_radio0', 'Home', stations: 3),
            ap('guest0', 'Home Guest', stations: 1),
            ap('sta0', 'Upstream', mode: 'Client'),
          ]),
          radio('radio1', 5180, [
            ap('default_radio1', 'Home', stations: 2),
          ], disabled: true),
        ],
      ),
    );
    expect(s.home?.ssid, 'Home');
    expect(s.home?.devices, 5);
    expect(s.guest?.ssid, 'Home Guest');
    expect(s.guest?.devices, 1);
    expect(s.bands.map((b) => '${b.label} ${b.on} ${b.devices}'), [
      '2.4 GHz true 3',
      '5 GHz false 2',
    ]);
  });

  test('an open network shares without a password', () {
    final s = WifiSetup(
      WirelessOverview(
        radios: [
          radio('radio0', 2437, [
            ap('default_radio0', 'Cafe', sec: WifiSecurityMode.open),
          ]),
        ],
      ),
    );
    expect(s.home?.open, isTrue);
    expect(s.guest, isNull);
  });

  test('no access point means no home network', () {
    final s = WifiSetup(const WirelessOverview(radios: []));
    expect(s.home, isNull);
    expect(s.bands, isEmpty);
  });
}
