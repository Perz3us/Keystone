import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/devices_usage/device_usage_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';

const info = {
  'version': '0.1.0',
  'backend': 'nft',
  'offload': true,
  'periods': ['2026-11-01', '2026-10-01', '2026-09-01'],
};

Map<String, dynamic> usage(String start, String end) => {
  'period_start': start,
  'period_end': end,
  'devices': [
    {'mac': 'aa:bb:cc:00:00:01', 'down': 100, 'up': 10},
    {'mac': 'aa:bb:cc:00:00:02', 'down': 20, 'up': 2},
    {'mac': 'bad'},
    'x',
  ],
};

void main() {
  DeviceUsageClient client({Object? error}) => DeviceUsageClient((m, p) async {
    if (error != null) throw error;
    if (m == 'info') return info;
    final p0 = p['period'] as String?;
    return usage(p0 ?? '2026-11-01', p0 == null ? '2026-11-30' : '');
  });

  test('reads info', () async {
    final i = (await client().info())!;
    expect(i.offload, isTrue);
    expect(i.periods.first, DateTime.utc(2026, 11));
    expect(i.backend, 'nft');
  });

  test('current period', () async {
    final u = (await client().usage())!;
    expect(u.start, DateTime.utc(2026, 11));
    expect(u.end, DateTime.utc(2026, 11, 30));
    expect(u.byMac['AA:BB:CC:00:00:01']!.total, 110);
    expect(u.byMac, hasLength(2));
  });

  test('an older period', () async {
    final u = (await client().usage(DateTime.utc(2026, 9)))!;
    expect(u.start, DateTime.utc(2026, 9));
    expect(u.end, isNull);
  });

  test('matches any MAC spelling', () async {
    final u = (await client().usage())!;
    expect(u.of('aa-bb-cc-00-00-02')!.down, 20);
    expect(u.of('AA:BB:CC:00:00:02')!.up, 2);
    expect(u.of('ff:ff:ff:ff:ff:ff'), isNull);
  });

  test('not installed', () async {
    expect(
      await client(error: const NoobRpcError('Method not found')).info(),
      isNull,
    );
    expect(await client(error: NoobRpcError.refused).usage(), isNull);
  });

  test('lost connection is an error', () {
    expect(
      client(error: const NoobRpcError('Timed out')).info(),
      throwsA(isA<NoobRpcError>()),
    );
  });

  test('last three periods for one device', () async {
    final h = await client().history('aa:bb:cc:00:00:01');
    expect(h.map((e) => e.$1), [
      DateTime.utc(2026, 11),
      DateTime.utc(2026, 10),
      DateTime.utc(2026, 9),
    ]);
    expect(h.first.$2, 110);
  });

  test('history without the package is empty', () async {
    expect(
      await client(error: const NoobRpcError('Method not found')).history('aa'),
      isEmpty,
    );
  });
}
