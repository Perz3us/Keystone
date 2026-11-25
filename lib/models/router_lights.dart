enum LightColor { off, green, red, blue }

class RouterLights {
  const RouterLights(this.slots);

  final List<LightColor> slots;

  static const names = [
    'power',
    '5G',
    'mobile signal',
    'Wi-Fi',
    'internet',
    'phone',
  ];

  static const unlit = RouterLights([
    LightColor.off,
    LightColor.off,
    LightColor.off,
    LightColor.off,
    LightColor.off,
    LightColor.off,
  ]);

  bool get anyLit => slots.any((s) => s != LightColor.off);
}
