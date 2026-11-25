// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/preferred_towers.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

class _FakeIo implements UciIo {
  final List<String> log = [];
  bool fail = false;
  bool failSet = false;

  @override
  Future<List<Map<String, dynamic>>> sections(String config) async {
    if (fail) throw Exception('no config');
    return [
      {'.name': 'main', '.type': 'settings', 'enabled': '0'},
      {
        '.name': 'cfg1',
        '.type': 'cell',
        'pci': '346',
        'earfcn': '525',
        'enabled': '1',
      },
      {
        '.name': 'cfg2',
        '.type': 'cell',
        'pci': '346',
        'earfcn': '400',
        'enabled': '1',
      },
      {
        '.name': 'cfg3',
        '.type': 'cell',
        'pci': '151',
        'earfcn': '1725',
        'enabled': '1',
      },
    ];
  }

  @override
  Future<void> set(String config, String section, Map<String, String> v) async {
    if (failSet && section == 'new1') throw Exception('set failed');
    log.add('set $section $v');
  }

  @override
  Future<String> add(String config, String type) async {
    log.add('add $config $type');
    return 'new1';
  }

  @override
  Future<void> delete(String config, String section) async =>
      log.add('delete $section');

  @override
  Future<void> commit(String config) async => log.add('commit');
}

void main() {
  late _FakeIo io;
  late PreferredTowers pt;
  setUp(() {
    io = _FakeIo();
    pt = PreferredTowers(_FakeApp(), io: io);
  });

  test('load gives state and towers in file order', () async {
    final (on, towers) = (await pt.load())!;
    expect(on, false);
    expect(towers.map((t) => '${t.earfcn}/${t.pci}'), [
      '525/346',
      '400/346',
      '1725/151',
    ]);
    expect(towers.first.section, 'cfg1');
    expect(towers.first.enabled, true);
  });

  test('load is null when reading fails', () async {
    io.fail = true;
    expect(await pt.load(), isNull);
  });

  test('add of an existing tower only enables it', () async {
    await pt.add('1725', '151');
    expect(io.log, ['set cfg3 {enabled: 1}', 'commit']);
  });

  test('add of a new tower creates a section', () async {
    await pt.add('400', '347');
    expect(io.log, [
      'add auto-pci-cell cell',
      'set new1 {pci: 347, earfcn: 400, enabled: 1}',
      'commit',
    ]);
  });

  test('setOn sets main and commits', () async {
    await pt.setOn(true);
    expect(io.log, ['set main {enabled: 1}', 'commit']);
  });

  test('setEnabled and remove commit', () async {
    final (_, towers) = (await pt.load())!;
    await pt.setEnabled(towers.first, false);
    await pt.remove(towers.first);
    expect(io.log, [
      'set cfg1 {enabled: 0}',
      'commit',
      'delete cfg1',
      'commit',
    ]);
  });

  test('add trims when matching a duplicate', () async {
    await pt.add(' 1725 ', '151 ');
    expect(io.log, ['set cfg3 {enabled: 1}', 'commit']);
  });

  test('add throws and creates nothing when the read fails', () async {
    io.fail = true;
    await expectLater(pt.add('400', '347'), throwsException);
    expect(io.log, isEmpty);
  });

  test('add removes the new section when set fails', () async {
    io.failSet = true;
    await expectLater(pt.add('400', '347'), throwsException);
    expect(io.log, ['add auto-pci-cell cell', 'delete new1']);
  });

  test('add rejects empty values', () async {
    expect(() => pt.add(' ', '347'), throwsArgumentError);
    expect(() => pt.add('400', ''), throwsArgumentError);
  });
}
