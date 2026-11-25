import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/speed/speed_test.dart';
import 'package:yet_another_luci_app/screens/speed/speed_view.dart';

Future<List<String>> _pump(
  WidgetTester t, {
  SpeedTestProgress? progress,
  bool available = true,
  bool mobileData = false,
  List<SpeedResult> history = const [],
  double textScale = 1,
}) async {
  final calls = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SpeedView(
          progress: progress,
          available: available,
          mobileData: mobileData,
          history: history,
          onStart: () => calls.add('start'),
          onCancel: () => calls.add('cancel'),
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 500));
  return calls;
}

void main() {
  testWidgets('before a test: what it measures and Start', (t) async {
    final calls = await _pump(t, mobileData: true);
    expect(find.text('Speed test'), findsOneWidget);
    expect(
      find.text(
        "Run from your router, so it measures your internet, not this phone's Wi-Fi.",
      ),
      findsOneWidget,
    );
    expect(find.textContaining('mobile data'), findsOneWidget);
    await t.tap(find.text('Start test'));
    expect(calls, ['start']);
  });

  testWidgets('while testing: live number, phase, Cancel', (t) async {
    final calls = await _pump(
      t,
      progress: const SpeedTestProgress(
        phase: SpeedPhase.download,
        liveMbps: 38.6,
        progress: 0.4,
        pingMs: 31,
        server: 'Jio · Colombo',
      ),
    );
    expect(find.text('38.6'), findsOneWidget);
    expect(find.text('Testing download'), findsOneWidget);
    expect(find.text('31 ms'), findsOneWidget);
    expect(find.text('Jio · Colombo'), findsOneWidget);
    expect(find.text('—'), findsWidgets);
    await t.tap(find.text('Cancel'));
    expect(calls, ['cancel']);
  });

  testWidgets('done: the three numbers and Test again', (t) async {
    final calls = await _pump(
      t,
      progress: const SpeedTestProgress(
        phase: SpeedPhase.done,
        downMbps: 42.8,
        upMbps: 9.2,
        pingMs: 31.4,
        jitterMs: 2.1,
        isp: 'Bharti Airtel',
        server: 'Jio · Colombo',
        externalIp: '1.2.3.4',
        downLoadedPingMs: 88,
        upLoadedPingMs: 140,
        packetLoss: 0,
        downSamples: [10, 30, 42],
        upSamples: [5, 9],
      ),
      history: [
        SpeedResult(
          at: DateTime(2026, 11, 22, 21, 5),
          downMbps: 39.1,
          upMbps: 8.7,
          pingMs: 34,
        ),
      ],
    );
    expect(find.text('42.8'), findsWidgets);
    expect(find.text('9.2'), findsOneWidget);
    expect(find.text('31 ms'), findsOneWidget);
    expect(find.text('Jitter 2 ms'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Jio · Colombo'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Bharti Airtel'), findsOneWidget);
    expect(find.text('Your IP'), findsOneWidget);
    expect(find.text('1.2.3.4'), findsOneWidget);
    expect(find.text('88 ms down · 140 ms up'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Test again'), 200);
    await t.tap(find.text('Test again'));
    expect(calls, ['start']);
    await t.scrollUntilVisible(find.text('39.1 down · 8.7 up · 34 ms'), 200);
    expect(find.text('Earlier tests'), findsOneWidget);
  });

  testWidgets('a failure says so and offers Try again', (t) async {
    await _pump(
      t,
      progress: const SpeedTestProgress(
        phase: SpeedPhase.failed,
        error: 'Cannot open socket',
      ),
    );
    expect(find.text("The test didn't finish."), findsOneWidget);
    expect(find.text('Cannot open socket'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('no speed test on the router', (t) async {
    await _pump(t, available: false);
    expect(
      find.text("This router doesn't have a speed test installed."),
      findsOneWidget,
    );
    expect(find.text('Start test'), findsNothing);
  });

  testWidgets('fits at 2x text', (t) async {
    await _pump(
      t,
      textScale: 2,
      progress: const SpeedTestProgress(
        phase: SpeedPhase.done,
        downMbps: 942.5,
        upMbps: 88.1,
        pingMs: 4,
      ),
    );
    expect(t.takeException(), isNull);
  });
}
