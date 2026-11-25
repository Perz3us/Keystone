import 'package:yet_another_luci_app/models/router_lights.dart';

typedef UbusCall =
    Future<dynamic> Function(
      String object,
      String method,
      Map<String, dynamic> params,
    );

class RouterLightsService {
  RouterLightsService(this._call);

  final UbusCall _call;

  static const _dir = '/sys/class/leds';

  static const _slots = [
    ['green:power'],
    ['red:5g', 'green:5g', 'blue:5g'],
    ['red:signal', 'green:signal', 'blue:signal'],
    ['green:wifi'],
    ['green:internet'],
    ['green:phone'],
  ];

  Future<RouterLights> read() async {
    try {
      final listing = _payload(await _call('file', 'list', {'path': _dir}));
      final present = {
        for (final e in (listing?['entries'] as List? ?? const []))
          if (e is Map) e['name']?.toString(),
      };
      final wanted = _slots.expand((s) => s).where(present.contains).toList();
      if (wanted.isEmpty) return RouterLights.unlit;

      final lit = <String>{};
      await Future.wait(
        wanted.map((name) async {
          try {
            final res = _payload(
              await _call('file', 'read', {'path': '$_dir/$name/brightness'}),
            );
            final v = int.tryParse(res?['data']?.toString().trim() ?? '') ?? 0;
            if (v > 0) lit.add(name);
          } catch (_) {}
        }),
      );

      return RouterLights([
        for (final names in _slots) _colour(names.where(lit.contains)),
      ]);
    } catch (_) {
      return RouterLights.unlit;
    }
  }

  static LightColor _colour(Iterable<String> litNames) {
    final first = litNames.firstOrNull;
    if (first == null) return LightColor.off;
    return switch (first.split(':').first) {
      'red' => LightColor.red,
      'blue' => LightColor.blue,
      _ => LightColor.green,
    };
  }

  static Map<String, dynamic>? _payload(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
      return Map<String, dynamic>.from(res[1] as Map);
    }
    return null;
  }
}
