import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/passwall/passwall_view.dart';

Widget _app(Widget child) => MaterialApp(
  theme: KeystoneTheme.buildDarkTheme(),
  home: Scaffold(body: child),
);

void main() {
  test('share links: one per line, junk ignored', () {
    expect(
      shareLinks('vless://a@b:443?x=1#Home\n\n  ss://abc#2\nnot a link\r\n'),
      ['vless://a@b:443?x=1#Home', 'ss://abc#2'],
    );
    expect(shareLinks('hello'), isEmpty);
  });

  testWidgets('status, what goes through it, nodes and their menu', (t) async {
    final calls = <String>[];
    await t.pumpWidget(
      _app(
        PasswallView(
          title: 'Passwall2',
          on: true,
          running: true,
          currentId: 'b',
          routerTraffic: true,
          lanTraffic: false,
          nodes: const [
            PasswallNode(id: 'a', name: 'Singapore', line: 'vless · sg:443'),
            PasswallNode(id: 'b', name: 'Airtel SIM', line: 'vless · x:443'),
            PasswallNode(id: 'c', name: 'Split', line: '', rules: true),
          ],
          onToggle: (v) => calls.add('toggle $v'),
          onNode: (id, a) => calls.add('${a.name} $id'),
          onAdd: () => calls.add('add'),
          onRouterTraffic: (v) => calls.add('router $v'),
          onLanTraffic: (v) => calls.add('lan $v'),
        ),
      ),
    );
    expect(find.text('Using Airtel SIM'), findsOneWidget);
    expect(find.text('Nodes · 3'), findsOneWidget);
    expect(find.text('Rules: picks a node per site'), findsOneWidget);

    await t.tap(find.text('Singapore'));
    await t.tap(find.text('Add'));
    await t.tap(find.byType(Switch).at(1));
    await t.tap(find.byTooltip('Options for Singapore'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(calls, ['use a', 'add', 'lan true', 'remove a']);
  });

  testWidgets('the node in use cannot be removed', (t) async {
    final calls = <String>[];
    await t.pumpWidget(
      _app(
        PasswallView(
          title: 'Passwall2',
          on: true,
          running: false,
          currentId: 'b',
          routerTraffic: true,
          lanTraffic: true,
          nodes: const [PasswallNode(id: 'b', name: 'Airtel', line: 'x')],
          onToggle: (_) {},
          onNode: (id, a) => calls.add('${a.name} $id'),
          onAdd: () {},
          onRouterTraffic: (_) {},
          onLanTraffic: (_) {},
        ),
      ),
    );
    expect(find.text('On, but not running'), findsOneWidget);
    await t.tap(find.byTooltip('Options for Airtel'));
    await t.pumpAndSettle();
    await t.tap(find.text("Remove (it's in use)"));
    await t.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('adding needs a real link', (t) async {
    List<String>? got;
    await t.pumpWidget(
      _app(
        AddNodesSheet(
          onAdd: (l) async {
            got = l;
            return null;
          },
        ),
      ),
    );
    await t.enterText(find.byType(TextField), 'nonsense');
    await t.tap(find.text('Add node'));
    await t.pump();
    expect(find.textContaining('vless://'), findsWidgets);
    expect(got, isNull);
    await t.enterText(
      find.byType(TextField),
      'vless://a@b:1#x\ntrojan://p@q:2',
    );
    await t.pump();
    await t.tap(find.text('Add 2 nodes'));
    await t.pump();
    expect(got, ['vless://a@b:1#x', 'trojan://p@q:2']);
  });
}
