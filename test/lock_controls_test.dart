// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cellular_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/lock_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/preferred_towers.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

class _ExecApi extends Fake implements IApiService {
  _ExecApi({this.refuse = false, this.stamp = 'cell 1725 152'});
  final bool refuse;
  final String stamp;
  final sent = <String>[];

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    if (object == 'uci') {
      if (method != 'get') sent.add('$method ${params!['values'] ?? ''}');
      return [
        0,
        {
          'values': {
            'a': {'.name': 'a', '.index': 0, 'active_modem': '2-1'},
            'm_2_1': {
              '.name': 'm_2_1',
              '.index': 1,
              'at_port': '/dev/ttyUSB2',
              'celllock': stamp,
            },
          },
        },
      ];
    }
    final line = (params!['params'] as List).join(' ');
    sent.add(line);
    if (line.startsWith('json')) {
      return [
        0,
        {'code': 0, 'stdout': line == 'json' ? '{"supported":[]}' : 'bad verb'},
      ];
    }
    if (refuse && line.startsWith('set')) {
      return [
        0,
        {'code': 1, 'stdout': '{"error":"port not found"}'},
      ];
    }
    if (line.startsWith('/dev/')) {
      return [
        0,
        {'code': 0, 'stdout': 'OK'},
      ];
    }
    return [
      0,
      {'code': 0, 'stdout': ''},
    ];
  }
}

class _ExecApp extends Fake implements AppState {
  _ExecApp([_ExecApi? api]) : api = api ?? _ExecApi();
  final _ExecApi api;

  @override
  IApiService get apiService => api;

  @override
  String get sysauth => 'x';

  @override
  model.Router get selectedRouter => model.Router(
    id: 'r',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );
}

class _FakeTowers extends PreferredTowers {
  _FakeTowers(this.on, this.list) : super(_FakeApp());
  bool on;
  List<Tower> list;
  final calls = <String>[];

  @override
  Future<(bool, List<Tower>)?> load() async => (on, list);

  @override
  Future<void> setOn(bool v) async {
    calls.add('on:$v');
    on = v;
  }

  @override
  Future<void> setEnabled(Tower t, bool v) async => calls.add('enabled:$v');

  @override
  Future<void> add(String earfcn, String pci) async =>
      calls.add('add:$earfcn/$pci');

  @override
  Future<void> remove(Tower t) async => calls.add('remove');
}

class _NullTowers extends _FakeTowers {
  _NullTowers() : super(false, const []);

  @override
  Future<(bool, List<Tower>)?> load() async => null;
}

const _tower = Tower(
  section: 'cfg1',
  pci: '151',
  earfcn: '1725',
  enabled: true,
);

class _LockedLocks extends _FakeLocks {
  final locked = <String>[];

  @override
  Future<CellLock> cellLock() async => const CellLock(null, null, [
    NearbyCell('LTE', '1725', '152', null, null),
  ]);

  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) async => locked.add(pci);
}

Future<void> _pump(
  WidgetTester t,
  ModemLocks l,
  PreferredTowers? p, {
  List<NearbyCell>? nearby,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LockControls(locks: l, towers: p, nearby: nearby),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

class _NoLockLocks extends _FakeLocks {
  @override
  Future<CellLock> cellLock() async => throw const CellLockUnsupported();
}

class _FailOff extends _FakeTowers {
  _FailOff() : super(true, const []);

  @override
  Future<void> setOn(bool v) async => throw StateError('nope');
}

class _FiveGLocks extends _LockedLocks {
  @override
  Future<CellLock> cellLock() async => const CellLock(null, null, [
    NearbyCell('NR', '633984', '10', null, null),
  ]);
}

class _FakeLocks implements ModemLocks {
  final saved = <(String, List<String>)>[];

  @override
  bool get nrNeedsBand => false;

  @override
  Future<List<BandClass>> bands() async => [
    const BandClass(
      'LTE',
      [('1', 'B1'), ('3', 'B3'), ('7', 'B7')],
      {'1', '3', '7'},
    ),
  ];

  @override
  Future<void> saveBands(BandClass c, List<String> picked) async =>
      saved.add((c.id, picked));

  @override
  Future<CellLock> cellLock() async => const CellLock(null, null, []);

  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) async {}
}

class _DeafLocks extends _LockedLocks {
  bool deaf = false;
  bool lag = false;

  @override
  Future<CellLock> cellLock() async {
    if (deaf) throw StateError('timeout');
    return lag
        ? const CellLock(null, null, [])
        : const CellLock('PCI 1 · EARFCN 2', null, []);
  }
}

void main() {
  test('5G Modem unlock sends both offs without reading first', () async {
    final app = _ExecApp();
    await FiveGModemLocks(app).setLock(nr: false);
    expect(app.api.sent, ['setcelllock off', 'setcelllock5g off']);
  });

  test('unlock goes through atcmd when ModemManager blocks it', () async {
    final app = _ExecApp(_ExecApi(refuse: true));
    await FiveGModemLocks(app).setLock(nr: false);
    expect(app.api.sent, contains('/dev/ttyUSB2 AT+QNWLOCK="common/4g",0'));
    expect(app.api.sent, contains('set {celllock: }'));
  });

  test('a silent modem shows the lock 5gmodem remembers', () async {
    final app = _ExecApp();
    final lock = await FiveGModemLocks(app).cellLock();
    expect(lock.lte, 'PCI 152 · EARFCN 1725');
    expect(app.api.sent, ['jsonrefresh', 'json']);
    expect(
      FiveGModemLocks(_ExecApp(_ExecApi(stamp: ''))).cellLock(),
      throwsA(isA<CellLockUnsupported>()),
    );
  });

  testWidgets('a modem that does not answer can still be unlocked', (t) async {
    final locks = _DeafLocks()..deaf = true;
    await _pump(t, locks, null);
    await t.tap(find.text('Unlock'));
    await t.pumpAndSettle();
    expect(locks.locked, ['']);
    expect(find.text('Off'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pump();
    expect(find.text('Unlock'), findsOneWidget);
    expect(find.textContaining("isn't answering"), findsOneWidget);
    locks.deaf = false;
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(seconds: 10));
    }
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('a lock shows at once while readings lag', (t) async {
    final locks = _DeafLocks()..lag = true;
    await _pump(
      t,
      locks,
      null,
      nearby: const [NearbyCell('LTE', '1725', '152', null, null)],
    );
    await t.tap(find.textContaining('4G PCI 152'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lock now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Lock'));
    await t.pumpAndSettle();
    expect(locks.locked, ['152']);
    expect(find.text('PCI 152 · EARFCN 1725'), findsOneWidget);
    await t.pump(const Duration(seconds: 6));
    await t.pump();
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('bands stay folded until opened, then save the picks', (t) async {
    final locks = _FakeLocks();
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(child: LockControls(locks: locks)),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('All 3'), findsOneWidget);
    expect(find.text('B3'), findsNothing);
    expect(find.text('Not locked'), findsNWidgets(2));

    await t.tap(find.text('4G').first);
    await t.pumpAndSettle();
    await t.tap(find.text('B7'));
    await t.pumpAndSettle();
    expect(find.text('2 of 3 · B1 B3'), findsOneWidget);

    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(locks.saved.single.$1, 'LTE');
    expect(locks.saved.single.$2, ['1', '3']);
  });

  testWidgets('towers list, toggle and menu', (t) async {
    final p = _FakeTowers(false, [_tower]);
    await _pump(t, _LockedLocks(), p);
    expect(find.text('Preferred towers'), findsOneWidget);
    expect(
      find.text('Moves to the best tower on this list by itself'),
      findsOneWidget,
    );
    expect(find.text('PCI 151 · EARFCN 1725'), findsOneWidget);
    await t.tap(find.text('Preferred towers'));
    await t.pumpAndSettle();
    expect(find.text('Turn on Preferred towers?'), findsOneWidget);
    expect(
      find.text(
        'The modem may move to another tower. The connection drops for a moment.',
      ),
      findsOneWidget,
    );
    expect(p.calls, isEmpty);
    await t.tap(find.text('Turn on'));
    await t.pumpAndSettle();
    expect(p.calls, ['on:true']);

    await t.tap(find.byTooltip('Tower options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(p.calls.last, 'enabled:false');

    await t.tap(find.byTooltip('Tower options'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.text('Remove this tower?'), findsOneWidget);
    await t.tap(find.text('Remove').last);
    await t.pumpAndSettle();
    expect(p.calls.last, 'remove');
  });

  testWidgets('turning preferred towers off is instant', (t) async {
    final p = _FakeTowers(true, [_tower]);
    await _pump(t, _LockedLocks(), p);
    await t.tap(find.text('Preferred towers'));
    await t.pumpAndSettle();
    expect(find.text('Turn on Preferred towers?'), findsNothing);
    expect(p.calls, ['on:false']);
  });

  testWidgets('nearby cell sheet offers lock and add', (t) async {
    final p = _FakeTowers(false, const []);
    await _pump(t, _LockedLocks(), p);
    await t.tap(find.textContaining('PCI 152'));
    await t.pumpAndSettle();
    expect(find.text('Lock now'), findsOneWidget);
    await t.tap(find.text('Add to preferred towers'));
    await t.pumpAndSettle();
    expect(p.calls, ['add:1725/152']);
  });

  testWidgets('known tower is not offered again', (t) async {
    final p = _FakeTowers(false, [
      const Tower(section: 'c', pci: '152', earfcn: '1725', enabled: true),
    ]);
    await _pump(t, _LockedLocks(), p);
    await t.tap(find.textContaining('4G PCI 152'));
    await t.pumpAndSettle();
    expect(find.text('Already in preferred towers'), findsOneWidget);
  });

  testWidgets('locking by hand turns towers off first', (t) async {
    final p = _FakeTowers(true, [_tower]);
    await _pump(t, _LockedLocks(), p);
    await t.tap(find.text('Lock to a cell'));
    await t.pumpAndSettle();
    expect(find.text('Turn off Preferred towers?'), findsOneWidget);
    expect(
      find.text(
        'Preferred towers is moving the modem between towers. '
        'Turn it off to lock by hand?',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(p.calls, ['on:false']);
    expect(find.text('Lock'), findsOneWidget);
  });

  testWidgets('no towers part without towers', (t) async {
    for (final p in [null, _NullTowers()]) {
      await _pump(t, _LockedLocks(), p);
      expect(find.text('Preferred towers'), findsNothing);
      await t.tap(find.textContaining('PCI 152'));
      await t.pumpAndSettle();
      expect(find.text('Lock now'), findsOneWidget);
      expect(find.text('Add to preferred towers'), findsNothing);
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
    }
  });

  testWidgets('towers show without cell lock support', (t) async {
    final p = _FakeTowers(false, [_tower]);
    await _pump(
      t,
      _NoLockLocks(),
      p,
      nearby: const [NearbyCell('LTE', '1725', '152', null, null)],
    );
    expect(find.text('Preferred towers'), findsNWidgets(2));
    expect(find.text('Cell lock'), findsNothing);
    await t.tap(find.textContaining('4G PCI 152'));
    await t.pumpAndSettle();
    expect(find.text('Lock now'), findsNothing);
    await t.tap(find.text('Add to preferred towers'));
    await t.pumpAndSettle();
    expect(p.calls, ['add:1725/152']);
  });

  testWidgets('lock sheet stays shut if towers will not turn off', (t) async {
    await _pump(t, _LockedLocks(), _FailOff());
    await t.tap(find.text('Lock to a cell'));
    await t.pumpAndSettle();
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(find.text('Lock'), findsNothing);
  });

  testWidgets('5G neighbour only offers lock now', (t) async {
    await _pump(t, _FiveGLocks(), _FakeTowers(false, const []));
    await t.tap(find.textContaining('5G PCI 10'));
    await t.pumpAndSettle();
    expect(find.text('Lock now'), findsOneWidget);
    expect(find.text('Add to preferred towers'), findsNothing);
  });
}
