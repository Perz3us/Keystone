import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/services_forms.dart';

const _links = [
  {'interface': 'lan', 'device': 'br-lan'},
  {
    'interface': 'modem',
    'l3_device': 'wwan0',
    'route': [
      {'target': '0.0.0.0', 'mask': 0},
    ],
  },
];

const _inst = DdnsInstance(
  name: 'home',
  serviceName: 'cloudflare.com-v4',
  lookupHost: 'home.example.com',
  domain: 'example.com',
  username: 'u',
  password: 'p',
);

Future<DdnsInstance?> _saveWith(WidgetTester t, DdnsInstance inst) async {
  DdnsInstance? saved;
  await t.pumpWidget(
    MaterialApp(
      home: DdnsEditDialog(
        existingInstance: inst,
        links: _links,
        onSave: (d) async {
          saved = d;
          return true;
        },
        onTest: (_) async => throw UnimplementedError(),
      ),
    ),
  );
  await t.tap(find.text('Save'));
  await t.pumpAndSettle();
  return saved;
}

void main() {
  test('the IP settings reach the router', () {
    final p = _inst
        .copyWith(
          ipSource: 'interface',
          ipNetwork: 'modem',
          ipInterface: 'wwan0',
        )
        .toUciParams();
    expect(p['ip_network'], 'modem');
    expect(p['ip_interface'], 'wwan0');
    expect(
      DdnsInstance.fromUci('x', {'ip_interface': 'wwan0'}).ipInterface,
      'wwan0',
    );
  });

  testWidgets('a missing wan moves to the internet link', (t) async {
    final s = await _saveWith(
      t,
      _inst.copyWith(interface: 'wan', ipSource: 'network'),
    );
    expect(s?.interface, 'modem');
    expect(s?.ipNetwork, 'modem');
  });

  testWidgets('reading from a device saves the device', (t) async {
    final s = await _saveWith(
      t,
      _inst.copyWith(interface: 'wan', ipSource: 'interface'),
    );
    expect(s?.ipInterface, 'wwan0');
  });
}
