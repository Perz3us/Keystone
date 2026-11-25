import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/router/light_meanings.dart';

const _g = LightColor.green, _r = LightColor.red, _o = LightColor.off;

void main() {
  test('each light in words, like the real router', () {
    final rows = lightMeanings(
      const RouterLights([_g, _r, _g, _g, _g, _g]),
      signalPercent: 73,
      mode: 'LTE',
      wifiNetworksOn: 2,
      phoneState: 'idle',
    );
    expect(rows.map((r) => '${r.name}: ${r.meaning}'), [
      'Power: On',
      '5G: No 5G here, using LTE',
      'Mobile signal: Good · 73%',
      'Wi-Fi: 2 networks on',
      'Internet: Connected',
      'Phone: Line ready',
    ]);
  });

  test('off lights and missing details', () {
    final rows = lightMeanings(
      const RouterLights([_g, _o, _o, _g, _o, _o]),
      wifiNetworksOn: 1,
    );
    expect(rows.map((r) => r.meaning), [
      'On',
      'Off',
      'No signal',
      '1 network on',
      'Not connected',
      'No phone line',
    ]);
  });

  test('signal words', () {
    expect(signalQuality(80), 'Good');
    expect(signalQuality(45), 'Fair');
    expect(signalQuality(12), 'Weak');
  });
}
