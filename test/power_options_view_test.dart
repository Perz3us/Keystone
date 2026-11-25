import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/router/power_sheet.dart';

Future<List<String>> _pump(
  WidgetTester t, {
  bool checking = false,
  String? other = 'Slot B · OpenWrt 23.05',
  bool powerOff = true,
}) async {
  final calls = <String>[];
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      home: Scaffold(
        body: PowerOptionsView(
          checking: checking,
          otherFirmware: other,
          canPowerOff: powerOff,
          onOtherFirmware: () => calls.add('other'),
          onPowerOff: () => calls.add('off'),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return calls;
}

void main() {
  testWidgets('the other firmware asks first, then starts it', (t) async {
    final calls = await _pump(t);
    expect(find.text('Slot B · OpenWrt 23.05'), findsOneWidget);
    await t.tap(find.text('Start the other firmware'));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
    await t.tap(find.text('Restart'));
    await t.pumpAndSettle();
    expect(calls, ['other']);
  });

  testWidgets('power off asks first', (t) async {
    final calls = await _pump(t);
    await t.tap(find.text('Power off'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('says so when neither is possible', (t) async {
    await _pump(t, other: null, powerOff: false);
    expect(find.textContaining('can only restart normally'), findsOneWidget);
  });

  testWidgets('shows that it is checking', (t) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: PowerOptionsView(checking: true))),
    );
    expect(find.text('Checking what this router can do…'), findsOneWidget);
  });
}
