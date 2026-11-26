// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cell_guard.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cellular_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/lock_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/preferred_towers.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

class _ExecApi extends Fake implements IApiService {
  _ExecApi({
    this.refuse = false,
    this.busy = false,
    this.stamp = 'cell 1725 152',
  });
  final bool refuse, busy;
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
    final args = [for (final a in params!['params'] as List) '$a'];
    if (args.first == '-c') {
      final verb = args.skip(3).join(' ');
      sent.add('bg $verb');
      final out = busy
          ? ''
          : refuse
          ? 'rc=1\nport not found'
          : 'rc=0';
      return [
        0,
        {'code': 0, 'stdout': out},
      ];
    }
    final line = args.join(' ');
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

  @override
  Future<void> removeAll(List<Tower> list) async =>
      calls.add('removeAll:${list.length}');
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
  CellGuard? guard,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildDarkTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: LockControls(
            locks: l,
            towers: p,
            nearby: nearby,
            guard: guard,
          ),
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

class _Guard {
  _Guard({this.installed = true, this.state, this.slowArm = false});
  final bool installed, slowArm;
  Map<String, dynamic>? state;
  final calls = <String>[];

  CellGuard get guard => CellGuard(
    _FakeApp(),
    call: (m, p) async {
      if (!installed) throw const NoobRpcError('Not found');
      calls.add(m == 'arm' ? 'arm ${p['pci']} ${p['arfcn']} ${p['nr']}' : m);
      if (m == 'arm' && slowArm) throw NoobRpcError.slow;
      if (m == 'ack') state = {...?state, 'last': null};
      if (m == 'disarm') state = {...?state, 'lock': null};
      return state ?? {'version': '0.1.0', 'lock': null, 'last': null};
    },
  );
}

class _RefusingLocks extends _LockedLocks {
  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) async => throw const NoobRpcError('port not found');
}

class _BusyLocks extends _LockedLocks {
  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) async => throw const LockPending();
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
  group('cell guard', () {
    test('a lock arms the guard first', () async {
      final g = _Guard();
      final l = _LockedLocks();
      await guardedLock(l, g.guard, nr: false, pci: '151', arfcn: '1725');
      expect(g.calls, ['arm 151 1725 false']);
      expect(l.locked, ['151']);
    });

    test('unlocking disarms, also while the modem is busy', () async {
      final g = _Guard();
      await guardedLock(_LockedLocks(), g.guard, nr: false);
      expect(g.calls, ['disarm']);
      final busy = _Guard();
      await expectLater(
        guardedLock(_BusyLocks(), busy.guard, nr: false),
        throwsA(isA<LockPending>()),
      );
      expect(busy.calls, ['disarm']);
    });

    test('a lock the modem refuses is not left armed', () async {
      final g = _Guard();
      await expectLater(
        guardedLock(_RefusingLocks(), g.guard, nr: true, pci: '1', arfcn: '2'),
        throwsA(isA<NoobRpcError>()),
      );
      expect(g.calls, ['arm 1 2 true', 'disarm']);
    });

    test('a late arm reply still disarms when the lock fails', () async {
      final g = _Guard(slowArm: true);
      await expectLater(
        guardedLock(_RefusingLocks(), g.guard, nr: false, pci: '1', arfcn: '2'),
        throwsA(isA<NoobRpcError>()),
      );
      expect(g.calls, ['arm 1 2 false', 'disarm']);
    });

    test('a pending lock stays armed', () async {
      final g = _Guard();
      await expectLater(
        guardedLock(_BusyLocks(), g.guard, nr: false, pci: '1', arfcn: '2'),
        throwsA(isA<LockPending>()),
      );
      expect(g.calls, ['arm 1 2 false']);
    });

    test('no guard installed means info is null', () async {
      expect(await _Guard(installed: false).guard.info(), isNull);
    });

    test('what the guard did reads plainly', () {
      final s = GuardState.parse({
        'lock': {'pci': 503, 'phase': 'trial'},
        'last': {'time': 0, 'reason': 'no_service', 'pci': 503},
      });
      expect(s.line, 'Checking the new cell');
      expect(
        s.last!.text,
        startsWith(
          "The modem couldn't connect to PCI 503, so Cell guard removed the "
          'lock',
        ),
      );
      expect(GuardState.parse({'lock': null}).line, isNull);
      expect(GuardEvent.parse({'reason': 'lost'}), isNull);
    });

    testWidgets('the lock screen shows the guard and what it did', (t) async {
      final g = _Guard(
        state: {
          'lock': {'pci': 151, 'phase': 'watch'},
          'last': {'time': 0, 'reason': 'lost', 'pci': 503},
        },
      );
      await _pump(t, _LockedLocks(), null, guard: g.guard);
      expect(find.text('Watching the lock'), findsOneWidget);
      expect(
        find.textContaining('The internet was down for 5 minutes'),
        findsOneWidget,
      );
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(g.calls, contains('ack'));
      expect(find.textContaining('The internet was down'), findsNothing);
    });

    testWidgets('without the guard the screen offers it', (t) async {
      await _pump(
        t,
        _LockedLocks(),
        null,
        guard: _Guard(installed: false).guard,
      );
      expect(find.text('Add'), findsOneWidget);
      expect(find.textContaining('Add Cell guard'), findsOneWidget);
    });
  });

  group('locking by hand', () {
    testWidgets('starts from the cells the modem can see', (t) async {
      final l = _LockedLocks();
      await _pump(t, l, null);
      await t.tap(find.text('Lock to a cell'));
      await t.pumpAndSettle();
      expect(find.text('Cells your modem can see'), findsOneWidget);
      await t.tap(find.text('4G PCI 152 · EARFCN 1725').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Lock'));
      await t.pumpAndSettle();
      expect(find.textContaining("can't see this cell"), findsNothing);
      expect(l.locked, ['152']);
    });

    testWidgets('warns about a cell the modem cannot see', (t) async {
      final l = _LockedLocks();
      await _pump(t, l, null);
      await t.tap(find.text('Lock to a cell'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enter numbers yourself'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).at(0), '1725');
      await t.enterText(find.byType(TextFormField).at(1), '503');
      await t.tap(find.text('Lock'));
      await t.pumpAndSettle();
      expect(
        find.text("Your modem can't see this cell right now"),
        findsOneWidget,
      );
      expect(find.text('Lock anyway'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(l.locked, isEmpty);
    });

    test('a cell counts as seen only with the same type and numbers', () {
      const cells = [NearbyCell('LTE', '1725', '152', null, null)];
      expect(canSee(cells, nr: false, pci: ' 152', arfcn: '1725'), isTrue);
      expect(canSee(cells, nr: false, pci: '153', arfcn: '1725'), isFalse);
      expect(canSee(cells, nr: true, pci: '152', arfcn: '1725'), isFalse);
      expect(canSee(const [], nr: false, pci: '1', arfcn: '2'), isTrue);
    });
  });

  test('5G Modem unlock sends both offs without reading first', () async {
    final app = _ExecApp();
    await FiveGModemLocks(app).setLock(nr: false);
    expect(app.api.sent, ['bg setcelllock off']);
  });

  test('a busy modem gets the change in the background', () async {
    final app = _ExecApp(_ExecApi(busy: true));
    await expectLater(
      FiveGModemLocks(app).setLock(nr: false, pci: '152', arfcn: '1725'),
      throwsA(isA<LockPending>()),
    );
    expect(app.api.sent, ['bg setcelllock cell 1725 152']);
  });

  test('the lock result is read from the router', () {
    expect(lockResult('rc=0'), isNull);
    expect(lockResult('rc=2\nbad cell'), 'bad cell');
    expect(lockResult('rc=1'), 'Error 1');
    expect(() => lockResult(''), throwsA(isA<LockPending>()));
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
    await t.tap(find.text('Enter numbers yourself'));
    await t.pumpAndSettle();
    expect(find.text('Lock'), findsOneWidget);
  });

  testWidgets('the firmware examples can be cleared in one go', (t) async {
    Tower w(String pci, String earfcn) =>
        Tower(section: pci + earfcn, pci: pci, earfcn: earfcn, enabled: true);
    final samples = [w('175', '400'), w('175', '525'), w('115', '1725')];
    expect(firmwareSamples(samples), isTrue);
    expect(firmwareSamples([...samples.take(2), w('151', '1725')]), isFalse);
    final p = _FakeTowers(false, samples);
    await _pump(t, _LockedLocks(), p);
    await t.tap(find.text('Remove them'));
    await t.pumpAndSettle();
    expect(p.calls, ['removeAll:3']);
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
