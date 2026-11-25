import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/bandix/bandix_rates.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';
import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';

Client c(
  String name, {
  String mac = 'AA:BB:CC:00:00:01',
  bool wifi = true,
  int? dbm,
  double? rx,
  double? tx,
}) => Client(
  ipAddress: '192.168.1.10',
  macAddress: mac,
  hostname: name,
  connectionType: wifi ? ConnectionType.wireless : ConnectionType.wired,
  isConnected: true,
  signalDbm: dbm,
  rxSpeed: rx,
  txSpeed: tx,
);

void main() {
  test('signal in words', () {
    expect(signalWord(-50), 'strong');
    expect(signalWord(-65), 'good');
    expect(signalWord(-78), 'weak signal');
    expect(signalWord(null), isNull);
  });

  test('a device line says how it is connected', () {
    expect(deviceLine(c('a', wifi: false)), 'Wired');
    expect(deviceLine(c('a', dbm: -50)), 'Wi-Fi · strong');
    expect(deviceLine(c('a')), 'Wi-Fi');
    expect(isWeak(c('a', dbm: -80)), isTrue);
    expect(isWeak(c('a', wifi: false)), isFalse);
  });

  test('Mbps from bytes per second both ways', () {
    expect(deviceMbps(c('a', rx: 1e6, tx: 250000)), closeTo(10, 0.001));
    expect(deviceMbps(c('a')), 0);
  });

  test('busy first, quiet by name, paused apart', () {
    final g = DeviceGroups.from(
      [
        c('Zed', mac: '01', rx: 10),
        c('TV', mac: '02', rx: 1e6),
        c('Phone', mac: '03', rx: 4e6),
        c('Alpha', mac: '04'),
        c('Kid', mac: '05', rx: 2e6),
      ],
      {'05'},
    );
    expect(g.using.map((d) => d.hostname), ['Phone', 'TV']);
    expect(g.quiet.map((d) => d.hostname), ['Alpha', 'Zed']);
    expect(g.paused.map((d) => d.hostname), ['Kid']);
  });

  test('Bandix fills in speeds, matched by MAC in any case', () {
    final out = withBandix(
      [c('PC', mac: 'AA:BB:CC:00:00:13', wifi: false), c('Phone', mac: '02')],
      {'aa:bb:cc:00:00:13': const BandixRate(1e6, 0, 5e8, 1e8)},
    );
    expect(deviceMbps(out[0]), closeTo(8, 0.001));
    expect(out[0].rxBytes, 500000000);
    expect(out[1].rxSpeed, isNull);
  });
}
