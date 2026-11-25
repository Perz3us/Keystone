import 'package:yet_another_luci_app/models/router_lights.dart';

class LightRow {
  const LightRow(this.name, this.color, this.meaning);
  final String name;
  final LightColor color;
  final String meaning;
}

String signalQuality(int percent) => percent >= 60
    ? 'Good'
    : percent >= 30
    ? 'Fair'
    : 'Weak';

const _phone = {
  'idle': 'Line ready',
  'ringing': 'Ringing',
  'talking': 'In a call',
  'calling': 'Calling',
  'dialtone': 'Off the hook',
  'digits': 'Dialling',
  'busy': 'Busy',
};

List<LightRow> lightMeanings(
  RouterLights lights, {
  int? signalPercent,
  String? mode,
  int wifiNetworksOn = 0,
  String? phoneState,
}) {
  final s = lights.slots;
  bool on(int i) => s[i] != LightColor.off;
  final fiveG = switch (s[1]) {
    LightColor.off => 'Off',
    LightColor.red => mode == null ? 'No 5G here' : 'No 5G here, using $mode',
    _ => '5G connected',
  };
  final signal = !on(2)
      ? 'No signal'
      : signalPercent == null
      ? 'On'
      : '${signalQuality(signalPercent)} · $signalPercent%';
  return [
    LightRow('Power', s[0], on(0) ? 'On' : 'Off'),
    LightRow('5G', s[1], fiveG),
    LightRow('Mobile signal', s[2], signal),
    LightRow(
      'Wi-Fi',
      s[3],
      on(3)
          ? '$wifiNetworksOn network${wifiNetworksOn == 1 ? '' : 's'} on'
          : 'Off',
    ),
    LightRow('Internet', s[4], on(4) ? 'Connected' : 'Not connected'),
    LightRow(
      'Phone',
      s[5],
      on(5) ? (_phone[phoneState] ?? 'Line ready') : 'No phone line',
    ),
  ];
}
