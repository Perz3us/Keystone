import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';

void main() {
  test('QR payload escapes the special characters', () {
    expect(
      wifiQrPayload(
        const WifiNet(ssid: r'My;Net', key: r'a:b\c"d,e', security: 'WPA'),
      ),
      r'WIFI:T:WPA;S:My\;Net;P:a\:b\\c\"d\,e;;',
    );
  });

  test('open and hidden networks', () {
    expect(
      wifiQrPayload(const WifiNet(ssid: 'Cafe', security: 'nopass')),
      'WIFI:T:nopass;S:Cafe;;',
    );
    expect(
      wifiQrPayload(
        const WifiNet(ssid: 'H', key: 'k', security: 'WPA', hidden: true),
      ),
      'WIFI:T:WPA;S:H;P:k;H:true;;',
    );
  });

  test('what each band is good for', () {
    expect(bandLine('2.4 GHz', 3), 'Reaches further · 3 devices');
    expect(bandLine('5 GHz', 1), 'Faster up close · 1 device');
    expect(bandLine('6 GHz', 0), 'Fastest, shortest reach · no devices');
    expect(bandLine('Wi-Fi', 2), '2 devices');
  });

  test('turning off asks first, naming who drops', () {
    expect(offWarning('5 GHz', 2), '2 devices on 5 GHz will disconnect.');
    expect(
      offWarning('Guest Wi-Fi', 1),
      '1 device on Guest Wi-Fi will disconnect.',
    );
    expect(offWarning('5 GHz', 0), 'Nothing is connected to 5 GHz right now.');
  });
}
