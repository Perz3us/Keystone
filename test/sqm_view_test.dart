// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_telemetry.dart';
import 'package:yet_another_luci_app/modules/sqm/screens/sqm_screen.dart';

void main() {
  test('speeds read back in plain Mbps', () {
    expect(sqmMbps(85000), '85');
    expect(sqmMbps(10500), '10.5');
    expect(sqmMbps(0), '');
  });

  test('the health line says what the queue is doing', () {
    SqmQueueTelemetry t(int backlog, int dropped) => SqmQueueTelemetry(
      interfaceName: 'eth1',
      qdisc: 'cake',
      root: true,
      sentBytes: 0,
      sentPackets: 0,
      droppedPackets: dropped,
      overlimits: 0,
      requeues: 0,
      backlogBytes: 0,
      backlogPackets: backlog,
      rawOutput: '',
      timestamp: DateTime(2026),
    );
    expect(sqmHealthLine(null), isNull);
    expect(sqmHealthLine(t(0, 0)), 'Nothing waiting');
    expect(
      sqmHealthLine(t(3, 12)),
      '3 packets waiting · 12 dropped to keep things moving',
    );
  });

  Widget wrap(Widget w) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: w)),
  );

  SqmView view({
    required TextEditingController down,
    bool on = false,
    bool changed = false,
    bool offloading = false,
    ValueChanged<bool>? onToggle,
    VoidCallback? onSave,
  }) => SqmView(
    on: on,
    busy: false,
    down: down,
    up: TextEditingController(),
    presetId: 'cake_fiber',
    interface: 'wan',
    interfaces: const ['wan'],
    changed: changed,
    offloading: offloading,
    onOffloading: () {},
    onToggle: onToggle ?? (_) {},
    onPreset: (_) {},
    onInterface: (_) {},
    onSave: onSave ?? () {},
  );

  testWidgets('it cannot be turned on before the speeds are in', (
    tester,
  ) async {
    bool? toggled;
    await tester.pumpWidget(
      wrap(view(down: TextEditingController(), onToggle: (v) => toggled = v)),
    );
    expect(find.text('Enter your speeds below first'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(toggled, isNull);
  });

  testWidgets('with speeds it turns on; save waits for a change', (
    tester,
  ) async {
    bool? toggled;
    var saved = 0;
    await tester.pumpWidget(
      wrap(
        view(
          down: TextEditingController(text: '85'),
          onToggle: (v) => toggled = v,
          onSave: () => saved++,
        ),
      ),
    );
    await tester.tap(find.byType(Switch));
    expect(toggled, true);
    await tester.tap(find.text('Save'));
    expect(saved, 0);
    await tester.pumpWidget(
      wrap(
        view(
          down: TextEditingController(text: '85'),
          changed: true,
          onSave: () => saved++,
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    expect(saved, 1);
  });

  testWidgets('offloading is pointed out with a way to fix it', (tester) async {
    await tester.pumpWidget(
      wrap(view(down: TextEditingController(text: '85'), offloading: true)),
    );
    expect(find.textContaining('Fast-path offloading is on'), findsOneWidget);
    expect(find.text('Turn it off'), findsOneWidget);
  });
}
