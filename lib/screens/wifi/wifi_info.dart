class WifiNet {
  const WifiNet({
    required this.ssid,
    this.key,
    this.security = 'WPA',
    this.hidden = false,
    this.enabled = true,
    this.devices = 0,
    this.section,
  });

  final String ssid;
  final String? key;

  final String security;
  final bool hidden;
  final bool enabled;
  final int devices;

  final String? section;

  bool get open => security == 'nopass';
}

class WifiBand {
  const WifiBand({
    required this.radio,
    required this.label,
    required this.on,
    this.devices = 0,
  });

  final String radio;
  final String label;
  final bool on;
  final int devices;
}

String _esc(String v) =>
    v.replaceAllMapped(RegExp(r'[\\;,:"]'), (m) => '\\${m[0]}');

String wifiQrPayload(WifiNet n) {
  final b = StringBuffer('WIFI:T:${n.security};S:${_esc(n.ssid)};');
  if (!n.open) b.write('P:${_esc(n.key ?? '')};');
  if (n.hidden) b.write('H:true;');
  b.write(';');
  return b.toString();
}

String _devices(int n) => switch (n) {
  0 => 'no devices',
  1 => '1 device',
  _ => '$n devices',
};

String bandLine(String label, int devices) {
  final what = switch (label) {
    '2.4 GHz' => 'Reaches further',
    '5 GHz' => 'Faster up close',
    '6 GHz' => 'Fastest, shortest reach',
    _ => null,
  };
  return what == null ? _devices(devices) : '$what · ${_devices(devices)}';
}

String offWarning(String what, int devices) => devices == 0
    ? 'Nothing is connected to $what right now.'
    : '${devices == 1 ? '1 device' : '$devices devices'} on $what will disconnect.';
