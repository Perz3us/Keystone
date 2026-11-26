import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/services_system/restart_preset.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/restart_sheet.dart';

void main() {
  Future<String?> open(
    WidgetTester t, {
    required bool guarded,
    String? current,
  }) async {
    String? saved;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [KeystoneColors.light]),
        home: Scaffold(
          body: RestartForm(
            guarded: guarded,
            current: current,
            onSave: (line) async => saved = line,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return saved;
  }

  testWidgets('saves a guarded router restart at 4:00', (t) async {
    String? saved;
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [KeystoneColors.light]),
        home: Scaffold(
          body: RestartForm(guarded: true, onSave: (l) async => saved = l),
        ),
      ),
    );
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(
      saved,
      restartCronLine(
        target: RestartTarget.router,
        hour: 4,
        minute: 0,
        guarded: true,
      ),
    );
  });

  testWidgets('modem restart needs keystone-history', (t) async {
    await open(t, guarded: false);
    expect(find.text('Modem'), findsNothing);
    expect(
      find.textContaining(
        'Install signal history to skip restarts during calls and upgrades',
      ),
      findsOneWidget,
    );
  });

  testWidgets('modem restart offered with the guard', (t) async {
    await open(t, guarded: true);
    expect(find.text('Modem'), findsOneWidget);
  });

  testWidgets('opens on the saved time', (t) async {
    await open(
      t,
      guarded: true,
      current: restartCronLine(
        target: RestartTarget.modem,
        hour: 2,
        minute: 30,
        guarded: true,
      ),
    );
    expect(find.text('2:30 AM'), findsOneWidget);
  });

  testWidgets('can be removed', (t) async {
    String? saved = 'x';
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [KeystoneColors.light]),
        home: Scaffold(
          body: RestartForm(
            guarded: true,
            current: restartCronLine(
              target: RestartTarget.router,
              hour: 4,
              minute: 0,
              guarded: true,
            ),
            onSave: (l) async => saved = l,
          ),
        ),
      ),
    );
    await t.tap(find.text('Stop restarting'));
    await t.pumpAndSettle();
    expect(saved, isNull);
  });
}
