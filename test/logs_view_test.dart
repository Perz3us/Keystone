import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_entry.dart';
import 'package:yet_another_luci_app/screens/router/logs_screen.dart';

LogEntry _e(int i, String msg, LogLevel level, {String tag = 'dnsmasq'}) =>
    LogEntry(
      index: i,
      raw: '$tag: $msg',
      timestamp: 'Mon Nov 23 10:0$i:00 2026',
      tag: tag,
      level: level,
      message: msg,
    );

Future<List<bool>> _pump(WidgetTester t, {String? problem}) async {
  final asked = <bool>[];
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      home: Scaffold(
        body: LogsView(
          kernel: false,
          entries: [
            _e(1, 'DHCPACK to phone', LogLevel.info),
            _e(2, 'link down', LogLevel.error, tag: 'netifd'),
            _e(3, 'retrying', LogLevel.warning, tag: 'netifd'),
          ],
          problem: problem,
          onKernel: asked.add,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return asked;
}

void main() {
  testWidgets('newest first, with what wrote each line', (t) async {
    await _pump(t);
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(y('retrying'), lessThan(y('DHCPACK to phone')));
    expect(find.textContaining('netifd'), findsWidgets);
  });

  testWidgets('search narrows the lines', (t) async {
    await _pump(t);
    await t.enterText(find.byType(TextField), 'phone');
    await t.pumpAndSettle();
    expect(find.text('DHCPACK to phone'), findsOneWidget);
    expect(find.text('link down'), findsNothing);
  });

  testWidgets('problems only keeps errors and warnings', (t) async {
    await _pump(t);
    await t.tap(find.text('Problems'));
    await t.pumpAndSettle();
    expect(find.text('DHCPACK to phone'), findsNothing);
    expect(find.text('link down'), findsOneWidget);
    expect(find.text('retrying'), findsOneWidget);
  });

  testWidgets('switching to the kernel log asks for it', (t) async {
    final asked = await _pump(t);
    await t.tap(find.text('Kernel'));
    expect(asked, [true]);
  });

  testWidgets("says why when the log can't be read", (t) async {
    await _pump(t, problem: "This sign-in isn't allowed to read logs.");
    expect(
      find.text("This sign-in isn't allowed to read logs."),
      findsOneWidget,
    );
  });
}
