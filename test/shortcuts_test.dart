import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/home/shortcuts.dart';

const _all = [
  ShortcutChoice('share', 'Share Wi-Fi', Icons.qr_code_rounded),
  ShortcutChoice('modem', 'Modem', Icons.cell_tower),
  ShortcutChoice('phone', 'Phone', Icons.phone),
  ShortcutChoice('passwall2', 'Passwall2', Icons.vpn_lock),
  ShortcutChoice('traffic', 'Traffic', Icons.swap_vert),
  ShortcutChoice('tools', 'Tools', Icons.handyman),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nothing saved: the first four', () {
    expect(pickShortcuts(_all, null).map((c) => c.id), [
      'share',
      'modem',
      'phone',
      'passwall2',
    ]);
  });

  test('saved order wins; removed features drop out', () {
    expect(pickShortcuts(_all, ['tools', 'gone', 'share']).map((c) => c.id), [
      'tools',
      'share',
    ]);
  });

  test('saved and read back', () async {
    SharedPreferences.setMockInitialValues({});
    await saveShortcutIds(['tools', 'share']);
    expect(await loadShortcutIds(), ['tools', 'share']);
  });

  testWidgets('pick up to four, Done saves', (t) async {
    List<String>? saved;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: ShortcutsView(
          all: _all,
          chosen: const ['share', 'modem', 'phone', 'passwall2'],
          onDone: (ids) => saved = ids,
        ),
      ),
    );
    expect(
      find.text('Pick up to 4 for home. Drag to reorder.'),
      findsOneWidget,
    );
    await t.tap(find.text('Traffic'));
    await t.pump();
    await t.tap(find.text('Done'));
    expect(saved, ['share', 'modem', 'phone', 'passwall2']);
    await t.tap(find.text('Phone'));
    await t.tap(find.text('Traffic'));
    await t.pump();
    await t.tap(find.text('Done'));
    expect(saved, ['share', 'modem', 'passwall2', 'traffic']);
  });
}
