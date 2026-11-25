import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/screens/routers/routers_view.dart';

Widget _app(Widget child) => MaterialApp(
  theme: KeystoneTheme.buildDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  const routers = [
    RouterEntry(
      id: 'a',
      name: 'AW1000',
      line: '192.168.1.1 · root',
      selected: true,
    ),
    RouterEntry(id: 'b', name: 'Office', line: '10.0.0.1 · admin'),
  ];

  testWidgets('lists routers, marks the current one, switches on tap', (
    t,
  ) async {
    final calls = <String>[];
    await t.pumpWidget(
      _app(
        RoutersView(
          routers: routers,
          onSelect: (id) => calls.add('select $id'),
          onAction: (id, a) => calls.add('$a $id'),
          onAdd: () => calls.add('add'),
        ),
      ),
    );
    expect(find.text('192.168.1.1 · root'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Current router')), findsOneWidget);
    await t.tap(find.text('Office'));
    await t.tap(find.text('Add a router'));
    expect(calls, ['select b', 'add']);
  });

  testWidgets('each router has rename, edit and remove', (t) async {
    final calls = <String>[];
    await t.pumpWidget(
      _app(
        RoutersView(
          routers: routers,
          onSelect: (_) {},
          onAction: (id, a) => calls.add('${a.name} $id'),
          onAdd: () {},
        ),
      ),
    );
    await t.tap(find.byTooltip('Options for Office'));
    await t.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Change address or password'), findsOneWidget);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(calls, ['remove b']);
  });

  testWidgets('while connecting, the row says so and taps wait', (t) async {
    final calls = <String>[];
    await t.pumpWidget(
      _app(
        RoutersView(
          routers: routers,
          switchingId: 'b',
          error: null,
          onSelect: (id) => calls.add(id),
          onAction: (_, _) {},
          onAdd: () => calls.add('add'),
        ),
      ),
    );
    expect(find.text('Connecting…'), findsOneWidget);
    await t.tap(find.text('AW1000'));
    await t.tap(find.text('Add a router'));
    expect(calls, isEmpty);
  });

  testWidgets('the form needs an address and shows what failed', (t) async {
    RouterFormValues? got;
    await t.pumpWidget(
      _app(
        RouterForm(
          title: 'Add a router',
          saveLabel: 'Connect',
          onSave: (v) async {
            got = v;
            return 'Wrong password.';
          },
        ),
      ),
    );
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.textContaining("router's address"), findsOneWidget);
    expect(got, isNull);

    await t.enterText(find.widgetWithText(TextField, 'Address'), '10.0.0.1');
    await t.enterText(find.widgetWithText(TextField, 'Password'), 'pw');
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(got!.address, '10.0.0.1');
    expect(got!.user, 'root');
    expect(got!.password, 'pw');
    expect(find.text('Wrong password.'), findsOneWidget);
  });
}
