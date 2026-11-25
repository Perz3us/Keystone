// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/align_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';

ModemMetrics _m(Object? rsrp) =>
    ModemMetrics({'rsrp': rsrp, 'sinr': '12', 'rsrq': '-9'});

Future<void> _open(
  WidgetTester t,
  Future<ModemMetrics> Function() read,
  void Function(double) tone,
) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => AlignScreen(read: read, tone: tone),
            ),
          ),
          child: const Text('go'),
        ),
      ),
    ),
  );
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
}

void main() {
  test('alignPitch maps and clamps', () {
    expect(alignPitch(-120), 300);
    expect(alignPitch(-70), 1200);
    expect(alignPitch(-95), 750);
    expect(alignPitch(-140), 300);
    expect(alignPitch(-40), 1200);
  });

  testWidgets('shows the reading and tones it', (t) async {
    final tones = <double>[];
    await _open(t, () async => _m('-96'), tones.add);
    expect(find.text('-96'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('-9'), findsOneWidget);
    expect(tones, [alignPitch(-96)]);
    final style = t.widget<Text>(find.text('-96')).style!;
    expect(style.fontSize, greaterThanOrEqualTo(48));
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('no tone without a number', (t) async {
    final tones = <double>[];
    await _open(t, () async => _m(null), tones.add);
    expect(find.text('–'), findsWidgets);
    expect(tones, isEmpty);
  });

  testWidgets('tracks the best and resets it', (t) async {
    final vals = ['-100', '-90', '-95'];
    var i = 0;
    await _open(t, () async => _m(vals[i++ % 3]), (_) {});
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(seconds: 2));
    expect(find.text('-90 dBm'), findsOneWidget);
    await t.tap(find.text('Reset'));
    await t.pump();
    expect(find.text('-95 dBm'), findsOneWidget);
  });

  testWidgets('tone off stops the tone', (t) async {
    final tones = <double>[];
    await _open(t, () async => _m('-96'), tones.add);
    await t.tap(find.byType(Switch));
    await t.pump();
    await t.pump(const Duration(seconds: 2));
    expect(tones.length, 1);
  });

  testWidgets('tone not called after pop', (t) async {
    final tones = <double>[];
    await _open(t, () async => _m('-96'), tones.add);
    await t.pump(const Duration(seconds: 2));
    final n = tones.length;
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pumpAndSettle();
    await t.pump(const Duration(seconds: 10));
    expect(tones.length, n);
  });

  testWidgets('failed read clears the reading', (t) async {
    final tones = <double>[];
    var fail = false;
    await _open(t, () async {
      if (fail) throw Exception('x');
      return _m('-96');
    }, tones.add);
    fail = true;
    await t.pump(const Duration(seconds: 2));
    expect(find.text('-96'), findsNothing);
    expect(tones.length, 1);
  });

  testWidgets('skips a poll while a read is in flight', (t) async {
    var reads = 0;
    final slow = Completer<ModemMetrics>();
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: AlignScreen(
          read: () {
            reads++;
            return slow.future;
          },
          tone: (_) {},
        ),
      ),
    );
    await t.pump(const Duration(seconds: 4));
    expect(reads, 1);
    slow.complete(_m('-96'));
    await t.pump();
  });

  testWidgets('a hung read times out and polling goes on', (t) async {
    var reads = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: AlignScreen(
          read: () {
            reads++;
            return Completer<ModemMetrics>().future;
          },
          tone: (_) {},
        ),
      ),
    );
    await t.pump(const Duration(seconds: 4));
    expect(reads, 1);
    await t.pump(const Duration(seconds: 2));
    expect(reads, 2);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets('pauses in the background and resumes', (t) async {
    final tones = <double>[];
    await _open(t, () async => _m('-96'), tones.add);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final n = tones.length;
    await t.pump(const Duration(seconds: 10));
    expect(tones.length, n);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(tones.length, n + 1);
    await t.pump(const Duration(seconds: 2));
    expect(tones.length, n + 2);
  });
}
