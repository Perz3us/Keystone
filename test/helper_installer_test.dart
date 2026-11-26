// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_installer.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

class _Io implements RouterIo {
  _Io({
    this.apk = false,
    this.failUrl = true,
    this.failFile = false,
    this.throwUrl = false,
    this.refuseWrite,
    this.reloadThrows = false,
    this.never = false,
    this.shortWrite = false,
    this.urlLog = 'no net',
    this.rc,
    this.pid,
    this.op,
    this.opError = false,
    this.alive = false,
    this.hide = 0,
    this.readThrows = 0,
    this.readError,
  });
  final bool apk,
      failUrl,
      failFile,
      throwUrl,
      never,
      shortWrite,
      alive,
      opError;
  final String urlLog;
  final int hide;
  final int readThrows;
  final Object? readError;
  final Object? refuseWrite;
  final bool reloadThrows;
  final calls = <String>[];
  final writes = <String, List<int>>{};
  String? rc, pid, log, op;
  int _rcReads = 0, _thrown = 0, checks = 0, reads = 0;

  @override
  Future<(int, String)> exec(String cmd, List<String> args) async {
    calls.add([cmd, ...args].join(' '));
    if (cmd != '/bin/sh') return (0, '');
    final script = args[1];
    if (script.contains('rpcd reload')) {
      if (reloadThrows) throw 'dropped';
      return (0, '');
    }
    if (script.contains('alive=1')) {
      checks++;
      if (opError) throw 'wifi';
      return (
        0,
        [
          for (final p in args.skip(3)) ...[
            '== $p',
            'op=${op ?? ''}',
            'rc=${rc ?? ''}',
            if (pid != null && alive) 'alive=1',
            if (apk) 'apk=1',
            'version=${versionFiles['/usr/share/$p/version'] ?? ''}',
            if (rc != null) ...['---', log ?? ''],
          ],
        ].join('\n'),
      );
    }
    if (script.contains('wc -c') &&
        shortWrite &&
        args.last.startsWith('/tmp/')) {
      return (97, '');
    }
    if (script.contains('echo \$r')) {
      rc = log = null;
      pid = '123';
      op = RegExp(r'echo (install|remove) >').firstMatch(script)?.group(1);
      if (never) return (0, '');
      final arg = args.last;
      if (arg.startsWith('http')) {
        if (throwUrl) throw 'boom';
        rc = failUrl ? '1' : '0';
        log = failUrl ? urlLog : '';
      } else if (arg.startsWith('/tmp/')) {
        rc = failFile ? '1' : '0';
        log = failFile ? 'Downloading\nbad package\n' : '';
      } else {
        rc = '0';
        log = '';
      }
      return (0, _waitOut());
    }
    if (script.contains('while [ ! -s')) return (0, _waitOut());
    rc = log = pid = op = null;
    return (0, '');
  }

  String _waitOut() {
    if (never || hide > 0 || readThrows > 0 || readError != null) return '';
    return rc == null ? '' : 'rc=$rc\n---\n${log ?? ''}';
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    calls.add('write $path');
    if (refuseWrite != null) throw refuseWrite!;
    writes[path] = bytes;
  }

  final versionFiles = <String, String>{};

  @override
  Future<String?> read(String path) async {
    reads++;
    if (path.endsWith('/version')) return versionFiles[path];
    if (path.endsWith('.op')) {
      if (opError) throw 'wifi';
      return op;
    }
    if (path.endsWith('.pid')) return pid;
    if (path.endsWith('.log')) return log;
    if (readError != null && _rcReads++ >= 1) throw readError!;
    if (pid != null && _thrown < readThrows) {
      _thrown++;
      throw 'wifi';
    }
    return _rcReads++ < hide ? null : rc;
  }
}

const _rel = HelperRelease(
  version: '1.0.0',
  ipkUrl: 'https://x/a.ipk',
  apkUrl: 'https://x/a.apk',
);

HelperInstaller _make(
  _Io io, {
  HelperRelease? rel = _rel,
  bool offline = false,
  String? package,
  List<int>? bytes,
  Future<String?> Function()? version,
  Future<List<int>> Function(String)? download,
  List<HelperInstaller>? needs,
}) {
  var n = 0;
  return HelperInstaller(
    _FakeApp(),
    io: io,
    needs: needs,
    package: package ?? 'keystone-history',
    latest: () async => offline ? throw Exception('no net') : rel,
    download: download ?? (url) async => bytes ?? [1, 2, 3],
    version: version ?? () async => n++ == 0 ? null : '1.0.0',
    sleep: (_) async {},
  );
}

Matcher _says(String s) =>
    throwsA(isA<NoobRpcError>().having((e) => e.message, 'm', contains(s)));

bool _ran(_Io io, String pm, String arg) => io.calls.any(
  (c) =>
      c.startsWith('/bin/sh -c rm -f') &&
      c.contains('$pm "\$1"') &&
      c.endsWith(arg),
);

const _reloadCall =
    '/bin/sh -c (sleep 1; /etc/init.d/rpcd reload) </dev/null >/dev/null 2>&1 &';

int _launches(_Io io) => io.calls.where((c) => c.contains('echo \$r')).length;

void main() {
  test('an add-on install takes three trips to the router', () async {
    final io = _Io(apk: true);
    io.versionFiles['/usr/share/keystone-history/version'] = '1.0.0';
    final history = _make(io, version: () async => '1.0.0');
    final alerts = _make(io, package: 'keystone-alerts', needs: [history]);
    await alerts.install();
    await Future<void>.delayed(Duration.zero);
    final trips = io.calls
        .where(
          (c) =>
              !c.contains('rpcd reload') &&
              !(c.startsWith('/bin/sh -c rm -f') && !c.contains('echo')),
        )
        .toList();
    expect(trips, hasLength(3), reason: trips.join(' | '));
    expect(io.reads, 0);
  });

  test('installs from the phone and never asks the router to fetch', () async {
    final io = _Io(apk: true, failUrl: false);
    await _make(io).install();
    expect(io.writes['/tmp/keystone-history.apk'], [1, 2, 3]);
    expect(
      _ran(io, 'apk add --allow-untrusted', 'sh /tmp/keystone-history.apk'),
      isTrue,
    );
    expect(io.calls.any((c) => c.endsWith('sh https://x/a.apk')), isFalse);
    expect(io.calls, contains(_reloadCall));
  });

  test('opkg router uses opkg on the phone copy', () async {
    final io = _Io();
    await _make(io).install();
    expect(
      _ran(
        io,
        'opkg install --force-downgrade',
        'sh /tmp/keystone-history.ipk',
      ),
      isTrue,
    );
  });

  test('a refused write falls back to the router url', () async {
    for (final e in const [
      NoobRpcError('Permission denied'),
      NoobRpcError('Not supported'),
    ]) {
      final io = _Io(apk: true, failUrl: false, refuseWrite: e);
      await _make(io).install();
      expect(
        _ran(io, 'apk add --allow-untrusted', 'sh https://x/a.apk'),
        isTrue,
      );
    }
  });

  test('a phone download failure falls back to the router url', () async {
    final io = _Io(failUrl: false);
    await _make(io, download: (_) async => throw Exception('net')).install();
    expect(io.writes, isEmpty);
    expect(
      _ran(io, 'opkg install --force-downgrade', 'sh https://x/a.ipk'),
      isTrue,
    );
  });

  test('throws the router output when both fail', () async {
    await expectLater(
      _make(
        _Io(urlLog: 'no route'),
        download: (_) async => throw Exception('net'),
      ).install(),
      _says('no route · Could not download the package on the phone'),
    );
    await expectLater(
      _make(_Io(refuseWrite: const NoobRpcError('Not supported'))).install(),
      _says('no net'),
    );
  });

  test('a bad package copy is reported', () async {
    await expectLater(
      _make(_Io(failFile: true)).install(),
      _says('Downloading\nbad package'),
    );
  });

  test('remove runs detached, then reloads rpcd', () async {
    final io = _Io(apk: true);
    await _make(io).remove();
    expect(_ran(io, 'apk del', 'sh keystone-history'), isTrue);
    expect(io.calls.last, _reloadCall);
    final o = _Io();
    await _make(o).remove();
    expect(_ran(o, 'opkg remove', 'sh keystone-history'), isTrue);
    expect(o.calls.last, _reloadCall);
  });

  test('latestRelease is null with no release', () async {
    expect(await _make(_Io(), rel: null).latestRelease(), isNull);
  });

  test('a throwing exec on the url fallback is said in words', () async {
    final io = _Io(
      throwUrl: true,
      refuseWrite: const NoobRpcError('Permission denied'),
    );
    await expectLater(_make(io).install(), _says('Could not reach the router'));
  });

  test('install that never finishes says it is still installing', () async {
    await expectLater(
      _make(_Io(never: true)).install(),
      _says('still installing'),
    );
  });

  test('download failure is said in words', () async {
    await expectLater(
      _make(
        _Io(),
        download: (_) async => throw Exception('SocketException'),
      ).install(),
      _says('Could not download the package on the phone'),
    );
  });

  test('refuses a package that is too big to write', () async {
    final io = _Io();
    await expectLater(
      _make(io, bytes: List.filled(46 * 1024, 0)).install(),
      _says('too big'),
    );
    expect(io.writes, isEmpty);
  });

  test('a throwing reload never fails install or remove', () async {
    final io = _Io(failUrl: false, reloadThrows: true);
    await _make(io).install();
    await _make(io).remove();
    expect(io.calls.where((c) => c == '/etc/init.d/rpcd reload'), isEmpty);
    expect(io.calls, contains(_reloadCall));
  });

  test('a short write falls back to the router url', () async {
    final io = _Io(shortWrite: true, failUrl: false);
    await _make(io).install();
    expect(
      _ran(io, 'opkg install --force-downgrade', 'sh https://x/a.ipk'),
      isTrue,
    );
  });

  test('a write that fails some other way falls back to the url', () async {
    final io = _Io(failUrl: false, refuseWrite: const NoobRpcError('Oops'));
    await _make(io).install();
    expect(
      _ran(io, 'opkg install --force-downgrade', 'sh https://x/a.ipk'),
      isTrue,
    );
  });

  test('a write that fills the router says out of space', () async {
    await expectLater(
      _make(
        _Io(refuseWrite: const NoobRpcError('No space left on device')),
      ).install(),
      _says('out of space'),
    );
  });

  test('no lookup and missing package give different messages', () async {
    await expectLater(_make(_Io(), offline: true).install(), _says('GitHub'));
    await expectLater(
      _make(_Io(), rel: null).install(),
      _says("isn't published yet"),
    );
    await expectLater(
      _make(
        _Io(apk: true),
        rel: const HelperRelease(version: '1', ipkUrl: 'u', apkUrl: ''),
      ).install(),
      _says('no package for this router'),
    );
  });

  test('retries the helper check then asks to sign in again', () async {
    var n = 0;
    await _make(
      _Io(failUrl: false),
      version: () async => ++n < 4 ? null : '1.0.0',
    ).install();
    expect(n, 4);
    await expectLater(
      _make(_Io(failUrl: false), version: () async => null).install(),
      _says('Sign in to the router again'),
    );
  });

  test('status reads idle, running and done', () async {
    expect((await _make(_Io()).status()).phase, InstallPhase.idle);
    expect(
      (await _make(_Io(pid: '9', alive: true)).status()).phase,
      InstallPhase.running,
    );
    expect((await _make(_Io(pid: '9')).status()).phase, InstallPhase.idle);
    final s = await _make(_Io(rc: '2')).status();
    expect((s.phase, s.code), (InstallPhase.done, 2));
  });

  test('a running install is resumed, not started twice', () async {
    final io = _Io(pid: '9', alive: true, rc: '0', hide: 2, op: 'install');
    await _make(io).install();
    expect(_launches(io), 0);
    expect(io.calls, contains(_reloadCall));
  });

  test('a finished install is reported and cleared', () async {
    final io = _Io(rc: '0', op: 'install');
    await _make(io).install();
    expect(_launches(io), 0);
    expect(io.rc, isNull);
    final bad = _Io(rc: '1', op: 'install');
    bad.log = 'bad package';
    await expectLater(_make(bad).install(), _says('bad package'));
    expect(bad.rc, isNull);
  });

  test('polls that throw keep polling', () async {
    final io = _Io(failUrl: false, readThrows: 5);
    await _make(io).install();
    expect(_launches(io), 1);
  });

  test('an older helper is updated', () async {
    final io = _Io(failUrl: false);
    await _make(
      io,
      rel: const HelperRelease(
        version: '0.2.0',
        ipkUrl: 'https://x/a.ipk',
        apkUrl: 'https://x/a.apk',
      ),
      version: () async => '0.1.0',
    ).install();
    expect(_launches(io), 1);
  });

  test('a signed out poll ends the wait at once', () async {
    final io = _Io(
      never: true,
      readError: const NoobRpcError('Permission denied'),
    );
    await expectLater(_make(io).install(), _says('Sign in to the router'));
    expect(io._rcReads, lessThan(5));
  });

  test('already installed after a reboot is not repeated', () async {
    final io = _Io();
    await _make(io, version: () async => '1.0.0').install();
    expect(_launches(io), 0);
  });

  test('a locked package manager is said in words', () async {
    final io = _Io(
      urlLog: 'Could not lock /var/lock/opkg.lock',
      refuseWrite: const NoobRpcError('Not supported'),
    );
    await expectLater(_make(io).install(), _says('installing something else'));
  });

  test('the operation name is written in the launch line', () async {
    final io = _Io(failUrl: false);
    await _make(io).install();
    expect(
      io.calls.any((c) => c.contains('echo install >/tmp/keystone-history.op')),
      isTrue,
    );
    final o = _Io();
    await _make(o).remove();
    expect(
      o.calls.any((c) => c.contains('echo remove >/tmp/keystone-history.op')),
      isTrue,
    );
  });

  test('install refuses while a remove is running', () async {
    final io = _Io(pid: '9', alive: true, op: 'remove');
    await expectLater(_make(io).install(), _says('still removing'));
    expect(_launches(io), 0);
  });

  test('remove refuses while an install is running', () async {
    final io = _Io(pid: '9', alive: true, op: 'install');
    await expectLater(_make(io).remove(), _says('still installing'));
    expect(_launches(io), 0);
  });

  test('a finished remove is cleared and the install goes on', () async {
    final io = _Io(rc: '0', op: 'remove', failUrl: false);
    await _make(io).install();
    expect(_launches(io), 1);
    expect(
      _ran(
        io,
        'opkg install --force-downgrade',
        'sh /tmp/keystone-history.ipk',
      ),
      isTrue,
    );
  });

  test('a finished install is cleared and the remove goes on', () async {
    final io = _Io(rc: '0', op: 'install');
    await _make(io).remove();
    expect(_launches(io), 1);
    expect(_ran(io, 'opkg remove', 'sh keystone-history'), isTrue);
  });

  test('a running remove is resumed by remove', () async {
    final io = _Io(pid: '9', alive: true, rc: '0', hide: 2, op: 'remove');
    await _make(io).remove();
    expect(_launches(io), 0);
    expect(io.calls.last, _reloadCall);
  });

  test('a status read that throws never starts a second job', () async {
    final io = _Io(opError: true);
    await expectLater(_make(io).install(), throwsA(anything));
    await expectLater(_make(io).remove(), throwsA(anything));
    expect(_launches(io), 0);
  });

  test('the phone copy is deleted by the detached line', () async {
    final io = _Io(failUrl: false);
    await _make(io).install();
    final launches = io.calls.where((c) => c.contains('echo \$r')).toList();
    expect(launches, hasLength(1));
    expect(launches.single.contains('rm -f "\$1"'), isTrue);
  });

  test('installed and offline is left alone', () async {
    final io = _Io();
    await _make(io, offline: true, version: () async => '1.0.0').install();
    expect(_launches(io), 0);
  });

  test('another package uses its own name and files', () async {
    final io = _Io(failUrl: false);
    await _make(io, package: 'keystone-other').install();
    expect(
      io.calls.any((c) => c.contains('echo install >/tmp/keystone-other.op')),
      isTrue,
    );
    final o = _Io();
    await _make(o, package: 'keystone-other').remove();
    expect(_ran(o, 'opkg remove', 'sh keystone-other'), isTrue);
  });

  test('helperInfo and setKeepDays talk to the helper', () async {
    final seen = <String>[];
    Future<Map<String, dynamic>> call(String m, Map<String, dynamic> p) async {
      seen.add('$m $p');
      return m == 'info' ? {'keep_days': 14} : {'keep_days': 7};
    }

    expect((await helperInfo(_FakeApp(), call: call))?['keep_days'], 14);
    await setKeepDays(_FakeApp(), 7, call: call);
    expect(seen, ['info {}', 'set {keep_days: 7}']);
    await expectLater(
      setKeepDays(_FakeApp(), 7, call: (_, _) async => {'error': 'bad'}),
      _says("couldn't save that"),
    );
    expect(
      await helperInfo(_FakeApp(), call: (_, _) async => throw 'x'),
      isNull,
    );
  });

  test('going back installs the stable file over a newer one', () async {
    final io = _Io();
    final h = HelperInstaller(
      _FakeApp(),
      io: io,
      latest: () async => throw Exception('not used'),
      stable: () async => _rel,
      download: (_) async => [1, 2, 3],
      version: () async => '1.1.0_beta1',
      sleep: (_) async {},
    );
    await h.goBack();
    expect(io.writes.keys.single, startsWith('/tmp/keystone-history.'));
    expect(io.calls.any((c) => c.contains('/tmp/keystone-history.')), isTrue);
  });

  group('packages that need another one', () {
    test('installs what it needs first', () async {
      final io = _Io(failUrl: false);
      final history = _make(io, package: 'keystone-history');
      await _make(io, package: 'keystone-alerts', needs: [history]).install();
      expect(io.writes.keys, [
        '/tmp/keystone-history.ipk',
        '/tmp/keystone-alerts.ipk',
      ]);
    });
    test('skips what is already there', () async {
      final io = _Io(failUrl: false);
      final history = _make(io, version: () async => '1.0.0');
      await _make(io, package: 'keystone-alerts', needs: [history]).install();
      expect(io.writes.keys, ['/tmp/keystone-alerts.ipk']);
    });
    test('stops when what it needs fails', () async {
      final io = _Io(failUrl: false);
      final history = _make(io, rel: null);
      await expectLater(
        _make(io, package: 'keystone-alerts', needs: [history]).install(),
        _says("isn't published"),
      );
      expect(io.writes, isEmpty);
    });
    test('alerts and devices need history by default', () {
      expect(neededPackages('keystone-alerts'), ['keystone-history']);
      expect(neededPackages('keystone-devices'), ['keystone-history']);
      expect(neededPackages('keystone-history'), isEmpty);
    });
    test('other packages read their version from the router', () async {
      final io = _Io();
      final h = HelperInstaller(
        _FakeApp(),
        io: io,
        package: 'keystone-alerts',
        needs: const [],
        latest: () async => null,
      );
      io.versionFiles['/usr/share/keystone-alerts/version'] = '0.1.0\n';
      expect(await h.installed(), '0.1.0');
      io.versionFiles.clear();
      expect(await h.installed(), isNull);
    });
  });

  group('releaseFor', () {
    Map<String, dynamic> rel(List<String> names) => {
      'tag_name': 'v0.1.0',
      'assets': [
        for (final n in names) {'browser_download_url': 'https://gh/d/$n'},
      ],
    };

    test('picks this package out of a shared release', () {
      final r = releaseFor(
        rel([
          'keystone-other-2.0.0.apk',
          'keystone-history-extra-3.0.apk',
          'keystone-history-0.1.0.apk',
          'keystone-history_0.1.0_all.ipk',
          'keystone-other_2.0.0_all.ipk',
        ]),
        'keystone-history',
      )!;
      expect(r.version, '0.1.0');
      expect(r.apkUrl, 'https://gh/d/keystone-history-0.1.0.apk');
      expect(r.ipkUrl, 'https://gh/d/keystone-history_0.1.0_all.ipk');
    });

    test('null when the release has no asset for the package', () {
      expect(
        releaseFor(rel(['keystone-other-2.0.0.apk']), 'keystone-history'),
        isNull,
      );
      expect(releaseFor('nope', 'keystone-history'), isNull);
    });
  });

  group('newestRelease', () {
    final releases = [
      {
        'tag_name': 'keystone-history-v1.2.0_beta1',
        'prerelease': true,
        'assets': [
          {
            'browser_download_url':
                'https://gh/d/keystone-history-1.2.0_beta1.apk',
          },
        ],
      },
      {
        'tag_name': 'keystone-alerts-v1.0.0',
        'assets': [
          {'browser_download_url': 'https://gh/d/keystone-alerts-1.0.0.apk'},
        ],
      },
      {
        'tag_name': 'keystone-history-v1.1.0',
        'assets': [
          {'browser_download_url': 'https://gh/d/keystone-history-1.1.0.apk'},
        ],
      },
      {
        'tag_name': 'v0.2.0',
        'assets': [
          {'browser_download_url': 'https://gh/d/keystone-history-0.2.0.apk'},
        ],
      },
      {
        'tag_name': 'keystone-history-v9.0.0',
        'draft': true,
        'assets': [
          {'browser_download_url': 'https://gh/d/keystone-history-9.0.0.apk'},
        ],
      },
    ];

    test('finds a package whose release is not the newest', () {
      expect(
        newestRelease(releases, 'keystone-history', stable: true)!.version,
        '1.1.0',
      );
      expect(
        newestRelease(releases, 'keystone-alerts', stable: true)!.version,
        '1.0.0',
      );
    });

    test('pre-releases only for the experimental channel', () {
      expect(
        newestRelease(releases, 'keystone-history')!.version,
        '1.2.0_beta1',
      );
    });

    test('nothing for a package that was never released', () {
      expect(newestRelease(releases, 'keystone-devices', stable: true), isNull);
    });
  });
}
