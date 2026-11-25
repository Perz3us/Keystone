import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/devices/device_view.dart';

Future<List<String>> _pump(
  WidgetTester t, {
  bool wifi = true,
  bool weak = false,
  bool paused = false,
  String? limit,
  ControlState pauseState = ControlState.idle,
  ControlState limitState = ControlState.idle,
  double textScale = 1,
  bool blocked = false,
  bool fixedAddress = false,
}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(
          ctx,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: DeviceView(
          name: 'Living room TV',
          line: weak ? 'Wi-Fi · weak signal' : 'Wired',
          weak: weak,
          wifi: wifi,
          mbps: 9.4,
          usedBytes: 3100000000,
          samples: const [1, 4, 9.4],
          paused: paused,
          limitLine: limit,
          ip: '192.168.1.20',
          mac: 'AA:BB:CC:00:00:12',
          onPause: (v) => calls.add('pause $v'),
          onLimit: (v) => calls.add('limit $v'),
          onSchedule: () => calls.add('schedule'),
          onBlock: () => calls.add('block'),
          onWhy: () => calls.add('why'),
          pauseState: pauseState,
          limitState: limitState,
          onRetryPause: () => calls.add('retry pause'),
          onRetryLimit: () => calls.add('retry limit'),
          blocked: blocked,
          extraDetails: const [
            ('Maker', 'Samsung'),
            ('Wi-Fi network', 'Home'),
            ('Signal', '-61 dBm'),
          ],
          onForgetAddress: fixedAddress ? () => calls.add('forget') : null,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  return calls;
}

void main() {
  testWidgets('says what it is doing first', (t) async {
    await _pump(t);
    expect(find.text('Living room TV'), findsOneWidget);
    expect(find.text('9.4 Mbps'), findsOneWidget);
    expect(find.textContaining('3.1 GB used'), findsOneWidget);
    expect(find.text('192.168.1.20'), findsOneWidget);
  });

  testWidgets('the three controls do what they say', (t) async {
    final calls = await _pump(t, limit: '10 Mbps down · 2 up');
    await t.tap(find.text('Pause internet'));
    await t.tap(find.text('Limit speed'));
    await t.tap(find.text('Pause for a while'));
    expect(calls, ['pause true', 'limit false', 'schedule']);
    expect(find.text('10 Mbps down · 2 up'), findsOneWidget);
  });

  testWidgets('paused shows as on', (t) async {
    final calls = await _pump(t, paused: true);
    await t.tap(find.text('Pause internet'));
    expect(calls, ['pause false']);
  });

  testWidgets('Why only for a weak signal, Block only on Wi-Fi', (t) async {
    await _pump(t, wifi: false);
    expect(find.text('Why?'), findsNothing);
    expect(find.text('Block this device…'), findsNothing);
    final calls = await _pump(t, weak: true);
    await t.tap(find.text('Why?'));
    await t.ensureVisible(find.text('Block this device…'));
    await t.tap(find.text('Block this device…'));
    expect(calls, ['why', 'block']);
  });

  testWidgets('fits at 2x text', (t) async {
    await _pump(t, weak: true, limit: '10 Mbps down · 2 up', textScale: 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('while it applies, it says so and waits', (t) async {
    final calls = await _pump(t, limitState: ControlState.applying);
    expect(find.text('Applying on the router…'), findsOneWidget);
    await t.tap(find.text('Limit speed'));
    expect(calls, isEmpty);
  });

  testWidgets('a failure says nothing changed and offers Try again', (t) async {
    final calls = await _pump(t, pauseState: ControlState.failed);
    expect(find.text("Couldn't pause it"), findsOneWidget);
    expect(
      find.text("The router didn't answer. Nothing was changed."),
      findsOneWidget,
    );
    await t.tap(find.text('Try again'));
    expect(calls, ['retry pause']);
  });

  testWidgets('every detail the router gives, and forget fixed address', (
    t,
  ) async {
    final calls = await _pump(t, fixedAddress: true);
    await t.scrollUntilVisible(
      find.text('-61 dBm'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Samsung'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Forget its fixed address'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Forget its fixed address'));
    expect(calls, ['forget']);
  });

  testWidgets('a blocked device offers Unblock', (t) async {
    final calls = await _pump(t, blocked: true);
    await t.scrollUntilVisible(
      find.text('Unblock this device…'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Unblock this device…'));
    expect(calls, ['block']);
  });
}
