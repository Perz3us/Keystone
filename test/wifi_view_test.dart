import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/wifi/share_wifi_sheet.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_view.dart';

const _home = WifiNet(ssid: 'Home', key: 'secret123', devices: 5);
const _guest = WifiNet(
  ssid: 'Home Guest',
  key: 'guestpw',
  devices: 1,
  section: 'g',
);
const _bands = [
  WifiBand(radio: 'radio0', label: '2.4 GHz', on: true, devices: 3),
  WifiBand(radio: 'radio1', label: '5 GHz', on: true, devices: 2),
];

Future<List<String>> _pump(
  WidgetTester t, {
  WifiNet? guest = _guest,
  double textScale = 1,
}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: WifiView(
          routerName: 'AW1000',
          home: _home,
          bands: _bands,
          guest: guest,
          onEditName: () => calls.add('name'),
          onEditPassword: () => calls.add('password'),
          onBand: (b, on) => calls.add('${b.label} $on'),
          onGuest: (on) => calls.add('guest $on'),
          onSetUpGuest: () => calls.add('setup'),
          onShare: () => calls.add('share'),
          onMoreOptions: () => calls.add('more'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('the things people change most', (t) async {
    await _pump(t);
    expect(find.text('Wi-Fi'), findsOneWidget);
    expect(find.text('5 devices on Wi-Fi · 1 on guest'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Reaches further · 3 devices'), findsOneWidget);
    expect(find.text('Faster up close · 2 devices'), findsOneWidget);
    expect(find.text('secret123'), findsNothing);
  });

  testWidgets('the eye shows the password', (t) async {
    await _pump(t);
    await t.tap(find.byTooltip('Show password'));
    await t.pump();
    expect(find.text('secret123'), findsOneWidget);
  });

  testWidgets('turning a band off asks first; Keep on keeps it', (t) async {
    final calls = await _pump(t);
    await t.tap(find.byType(Switch).at(1));
    await t.pumpAndSettle();
    expect(find.text('2 devices on 5 GHz will disconnect.'), findsOneWidget);
    await t.tap(find.text('Keep on'));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
    await t.tap(find.byType(Switch).at(1));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(calls, ['5 GHz false']);
  });

  testWidgets('rows and buttons', (t) async {
    final calls = await _pump(t);
    await t.tap(find.text('Name'));
    await t.tap(find.text('Password'));
    await t.ensureVisible(find.text('Share Wi-Fi'));
    await t.tap(find.text('Share Wi-Fi'));
    await t.ensureVisible(find.text('More options'));
    await t.tap(find.text('More options'));
    expect(calls, ['name', 'password', 'share', 'more']);
  });

  testWidgets('no guest network offers to set one up', (t) async {
    final calls = await _pump(t, guest: null);
    await t.ensureVisible(find.text('Set up guest Wi-Fi'));
    await t.tap(find.text('Set up guest Wi-Fi'));
    expect(calls, ['setup']);
  });

  testWidgets('fits at 2x text', (t) async {
    await _pump(t, textScale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('share sheet: QR, switch to guest, copy', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        if (c.method == 'Clipboard.setData') {
          copied = (c.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () => showShareWifi(c, home: _home, guest: _guest),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Point a phone camera at this to join.'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    await t.tap(find.text('Guest'));
    await t.pumpAndSettle();
    expect(find.text('Home Guest'), findsOneWidget);
    await t.ensureVisible(find.text('Copy'));
    await t.pumpAndSettle();
    await t.tap(find.text('Copy'));
    await t.pump();
    expect(copied, 'Wi-Fi: Home Guest\nPassword: guestpw');
  });
}
