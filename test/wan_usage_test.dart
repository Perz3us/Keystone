import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';

final _dump = {
  'interface': [
    {
      'interface': 'lan',
      'up': true,
      'uptime': 99999,
      'l3_device': 'br-lan',
      'route': <dynamic>[],
    },
    {
      'interface': 'wwan',
      'up': true,
      'uptime': 18 * 3600,
      'l3_device': 'wwan0',
      'route': [
        {'target': '0.0.0.0', 'mask': 0},
      ],
    },
  ],
};

final _devices = {
  'br-lan': {
    'stats': {'rx_bytes': 1, 'tx_bytes': 1},
  },
  'wwan0': {
    'stats': {'rx_bytes': 10000000000, 'tx_bytes': 1200000000},
  },
};

void main() {
  test('usage comes from the internet connection only', () {
    final u = WanUsage.from(_dump, _devices)!;
    expect(u.seconds, 18 * 3600);
    expect(u.down, 10000000000);
    expect(u.up, 1200000000);
    expect(u.averageMbps, closeTo(11.2e9 * 8 / (18 * 3600) / 1e6, 0.01));
  });

  test('no internet connection, no numbers', () {
    expect(WanUsage.from({'interface': []}, _devices), isNull);
    expect(WanUsage.from(_dump, const {}), isNull);
  });
}
