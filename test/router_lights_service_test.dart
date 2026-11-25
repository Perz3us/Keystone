import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/services/router_lights_service.dart';

const _aw1000 = [
  'green:power',
  'red:5g',
  'green:5g',
  'blue:5g',
  'red:signal',
  'green:signal',
  'blue:signal',
  'green:wifi',
  'green:internet',
  'green:phone',
];

UbusCall fake({
  List<String> names = _aw1000,
  Set<String> lit = const {},
  String? failRead,
  bool failList = false,
}) {
  return (object, method, params) async {
    final path = params['path'] as String;
    if (method == 'list') {
      if (failList) return [6];
      return [
        0,
        {
          'entries': [
            for (final n in names) {'name': n, 'type': 'symlink'},
          ],
        },
      ];
    }
    final name = path.split('/')[4];
    if (name == failRead) throw Exception('read failed');
    return [
      0,
      {'data': lit.contains(name) ? '255\n' : '0\n'},
    ];
  };
}

void main() {
  const g = LightColor.green, r = LightColor.red, off = LightColor.off;

  test('reads the AW1000 lights into six slots', () async {
    final lights = await RouterLightsService(
      fake(
        lit: {
          'green:power',
          'red:5g',
          'green:signal',
          'green:wifi',
          'green:internet',
        },
      ),
    ).read();
    expect(lights.slots, [g, r, g, g, g, off]);
  });

  test('red wins over green on a multi-colour light', () async {
    final lights = await RouterLightsService(
      fake(lit: {'red:signal', 'green:signal'}),
    ).read();
    expect(lights.slots[2], r);
  });

  test('a refused listing leaves everything unlit', () async {
    final lights = await RouterLightsService(fake(failList: true)).read();
    expect(lights.slots, RouterLights.unlit.slots);
  });

  test('a listing that throws leaves everything unlit', () async {
    final lights = await RouterLightsService(
      (o, m, p) async => throw Exception('no file access'),
    ).read();
    expect(lights.slots, RouterLights.unlit.slots);
  });

  test('another router model leaves everything unlit', () async {
    final lights = await RouterLightsService(
      fake(names: ['tp-link:green:system', 'tp-link:green:wan']),
    ).read();
    expect(lights.slots, RouterLights.unlit.slots);
  });

  test('one failed read only darkens that light', () async {
    final lights = await RouterLightsService(
      fake(lit: {'green:power', 'green:wifi'}, failRead: 'green:power'),
    ).read();
    expect(lights.slots, [off, off, off, g, off, off]);
  });
}
