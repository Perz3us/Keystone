// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yet_another_luci_app/state/app_state.dart';

import '../../../services/app_update.dart';
import '../noob_rpc.dart';
import '../addons/experimental.dart';
import 'helper_history.dart';

@immutable
class HelperRelease {
  const HelperRelease({
    required this.version,
    required this.ipkUrl,
    required this.apkUrl,
  });
  final String version;
  final String ipkUrl;
  final String apkUrl;
}

abstract class RouterIo {
  Future<(int code, String out)> exec(String cmd, List<String> args);
  Future<void> write(String path, List<int> bytes);
  Future<String?> read(String path);
}

class _UbusIo implements RouterIo {
  _UbusIo(this.app);
  final AppState app;

  @override
  Future<(int, String)> exec(String cmd, List<String> args) async {
    final r = await noobCall(app, 'file', 'exec', {
      'command': cmd,
      'params': args,
    });
    final code = r['code'];
    return (
      code is int ? code : 0,
      '${r['stdout'] ?? ''}${r['stderr'] ?? ''}'.trim(),
    );
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    await noobCall(app, 'file', 'write', {
      'path': path,
      'data': base64Encode(bytes),
      'base64': true,
    });
  }

  @override
  Future<String?> read(String path) async {
    try {
      final r = await noobCall(app, 'file', 'read', {'path': path});
      return r['data']?.toString();
    } on NoobRpcError catch (e) {
      if (e.message == 'Not found') return null;
      rethrow;
    }
  }
}

HelperRelease? releaseFor(Object? json, String package) {
  if (json is! Map) return null;
  final name = RegExp(
    '^${RegExp.escape(package)}'
    r'[-_](\d[^_/]*?(?:_(?:alpha|beta|pre|rc)\d*)?)(?:_[^_/]+)?\.(apk|ipk)$',
  );
  var ipk = '', apk = '', version = '';
  for (final a in json['assets'] is List ? json['assets'] as List : const []) {
    final url = a is Map ? a['browser_download_url']?.toString() : null;
    final m = url == null ? null : name.firstMatch(url.split('/').last);
    if (m == null) continue;
    version = m[1]!;
    if (m[2] == 'ipk') ipk = url!;
    if (m[2] == 'apk') apk = url!;
  }
  if (version.isEmpty) return null;
  return HelperRelease(version: version, ipkUrl: ipk, apkUrl: apk);
}

HelperRelease? newestRelease(
  Object? json,
  String package, {
  bool stable = false,
}) {
  HelperRelease? best;
  for (final r in json is List ? json : const []) {
    if (r is Map && r['draft'] == true) continue;
    if (stable && r is Map && r['prerelease'] == true) continue;
    final rel = releaseFor(r, package);
    if (rel != null &&
        (best == null || isNewerVersion(rel.version, best.version))) {
      best = rel;
    }
  }
  return best;
}

(DateTime, Future<Object?>)? _releaseList;

Future<Object?> _fetchReleaseList() {
  final cached = _releaseList;
  if (cached != null &&
      DateTime.now().difference(cached.$1) < const Duration(minutes: 1)) {
    return cached.$2;
  }
  final f = http
      .get(
        Uri.parse(
          'https://api.github.com/repos/Perz3us/keystone-packages/releases?per_page=100',
        ),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 15))
      .then((res) {
        if (res.statusCode == 404) return null;
        if (res.statusCode != 200) {
          throw NoobRpcError('GitHub answered ${res.statusCode}');
        }
        return jsonDecode(res.body);
      });
  _releaseList = (DateTime.now(), f);
  f.then(
    (_) {},
    onError: (_) {
      if (identical(_releaseList?.$2, f)) _releaseList = null;
    },
  );
  return f;
}

Future<HelperRelease?> _fetchRelease(
  String package, {
  required bool experimental,
}) async =>
    newestRelease(await _fetchReleaseList(), package, stable: !experimental);

Future<List<int>> _fetchBytes(String url) async {
  final res = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 60));
  if (res.statusCode != 200) {
    throw NoobRpcError('Download failed (${res.statusCode})');
  }
  return res.bodyBytes;
}

Future<Map<String, dynamic>?> helperInfo(
  AppState app, {
  HelperCall? call,
}) async {
  try {
    return await (call ?? _call(app))('info', {});
  } catch (_) {
    return null;
  }
}

Future<void> setKeepDays(AppState app, int days, {HelperCall? call}) async {
  final r = await (call ?? _call(app))('set', {'keep_days': days});
  final err = r['error'];
  if (err != null) {
    throw const NoobRpcError("The router couldn't save that. Try again.");
  }
}

HelperCall _call(AppState app) =>
    (method, params) => noobCall(app, 'keystone.history', method, params);

const _maxWrite = 45 * 1024;
const _polls = 60;
const _busy = 'The router is installing something else, try again in a minute';

enum InstallPhase { idle, running, done }

const _checkSh = r'''for p in "$@"; do
echo "== $p"
echo "op=$(cat "/tmp/$p.op" 2>/dev/null)"
echo "rc=$(cat "/tmp/$p.rc" 2>/dev/null)"
i=$(cat "/tmp/$p.pid" 2>/dev/null)
case "$i" in ''|*[!0-9]*) ;; *) kill -0 "$i" 2>/dev/null && echo alive=1 ;; esac
command -v apk >/dev/null && echo apk=1
echo "version=$(cat "/usr/share/$p/version" 2>/dev/null)"
[ -s "/tmp/$p.rc" ] && { echo ---; tail -n 4 "/tmp/$p.log" 2>/dev/null; }
done
true''';

Map<String, String> _sections(String out) {
  final r = <String, String>{};
  String? key;
  final buf = StringBuffer();
  void flush() {
    final k = key;
    if (k != null) r[k] = buf.toString().trim();
    buf.clear();
  }

  for (final l in out.split('\n')) {
    if (l.startsWith('== ')) {
      flush();
      key = l.substring(3).trim();
    } else {
      buf.writeln(l);
    }
  }
  flush();
  return r;
}

const _waitSh = r'''i=0
while [ ! -s "$1" ] && [ $i -lt 4 ]; do sleep 1; i=$((i+1)); done
[ -s "$1" ] && {
  echo "rc=$(cat "$1")"
  echo "version=$(cat "$3" 2>/dev/null)"
  echo ---
  tail -n 4 "$2" 2>/dev/null
}
true''';

const _badCopy = 97;

class _Check {
  _Check(String out) {
    final parts = out.split('\n---\n');
    for (final l in parts.first.split('\n')) {
      final i = l.indexOf('=');
      if (i > 0) _v[l.substring(0, i).trim()] = l.substring(i + 1).trim();
    }
    log = parts.length > 1 ? parts.sublist(1).join('\n---\n') : '';
  }
  final _v = <String, String>{};
  late final String log;
  String get op => _v['op'] ?? '';
  int? get rc => int.tryParse(_v['rc'] ?? '');
  bool get alive => _v['alive'] == '1';
  bool get apk => _v['apk'] == '1';
  String? get version => (_v['version'] ?? '').isEmpty ? null : _v['version'];
  InstallPhase get phase => rc != null
      ? InstallPhase.done
      : alive
      ? InstallPhase.running
      : InstallPhase.idle;
}

class InstallState {
  const InstallState(this.phase, {this.op = '', this.code = 0, this.log = ''});
  final InstallPhase phase;
  final String op;
  final int code;
  final String log;
}

String _say(Object e) =>
    e is NoobRpcError ? e.message : 'Could not reach the router';

bool _signedOut(Object e) =>
    e is NoobRpcError &&
    (e.message == NoobRpcError.refused.message ||
        e.message.contains('Permission denied'));

final _full = RegExp(r'space', caseSensitive: false);

final _lockText = RegExp(r'(could not|unable to) lock', caseSensitive: false);

String _fail(String log) => _lockText.hasMatch(log) ? _busy : log;

String _tail(String log) {
  final lines = log
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return lines.skip(lines.length > 4 ? lines.length - 4 : 0).join('\n');
}

List<String> neededPackages(String package) => switch (package) {
  'keystone-alerts' ||
  'keystone-devices' ||
  'keystone-cellguard' => const ['keystone-history'],
  _ => const [],
};

class HelperInstaller {
  HelperInstaller(
    AppState app, {
    this.package = 'keystone-history',
    List<HelperInstaller>? needs,
    RouterIo? io,
    Future<HelperRelease?> Function()? latest,
    Future<HelperRelease?> Function()? stable,
    Future<List<int>> Function(String url)? download,
    Future<String?> Function()? version,
    Future<Map<String, dynamic>?> Function()? info,
    Future<void> Function(int days)? setKeep,
    Future<void> Function(Duration)? sleep,
  }) : _io = io ?? _UbusIo(app),
       _needs =
           needs ??
           [
             for (final p in neededPackages(package))
               HelperInstaller(app, package: p, io: io, sleep: sleep),
           ],
       _latest =
           latest ??
           (() async =>
               _fetchRelease(package, experimental: await loadExperimental())),
       _stable = stable ?? (() => _fetchRelease(package, experimental: false)),
       _download = download ?? _fetchBytes,
       _version =
           version ??
           (package == 'keystone-history'
               ? () => helperVersion(app)
               : () async => (await (io ?? _UbusIo(app)).read(
                   '/usr/share/$package/version',
                 ))?.trim()),
       _info = info ?? (() => helperInfo(app)),
       _setKeep = setKeep ?? ((d) => setKeepDays(app, d)),
       _sleep = sleep ?? Future.delayed;

  final String package;
  final List<HelperInstaller> _needs;
  final RouterIo _io;
  final Future<HelperRelease?> Function() _latest;
  final Future<HelperRelease?> Function() _stable;
  final Future<List<int>> Function(String url) _download;
  final Future<String?> Function() _version;
  final Future<Map<String, dynamic>?> Function() _info;
  final Future<void> Function(int days) _setKeep;
  final Future<void> Function(Duration) _sleep;

  String get _rc => '/tmp/$package.rc';
  String get _log => '/tmp/$package.log';
  String get _pid => '/tmp/$package.pid';
  String get _op => '/tmp/$package.op';

  Future<String?> installed() => _version();

  Future<Map<String, dynamic>?> info() => _info();

  Future<void> setKeep(int days) => _setKeep(days);

  Future<HelperRelease?> latestRelease() => _latest();

  Future<HelperRelease?> stableRelease() => _stable();

  String get _ver => '/usr/share/$package/version';

  String? _ranVersion;

  Future<Map<String, _Check>> _checkAll(List<String> packages) async {
    final out = (await _io.exec('/bin/sh', [
      '-c',
      _checkSh,
      'sh',
      ...packages,
    ])).$2;
    final s = _sections(out);
    return {for (final p in packages) p: _Check(s[p] ?? '')};
  }

  Future<_Check> _check() async => (await _checkAll([package]))[package]!;

  Future<InstallState> status() async {
    final c = await _check();
    return InstallState(
      c.phase,
      op: c.phase == InstallPhase.idle ? '' : c.op,
      code: c.rc ?? 0,
      log: _tail(c.log),
    );
  }

  Future<(int, String)?> _resume(String op, _Check st) async {
    if (st.phase == InstallPhase.idle) return null;
    if (st.op != op) {
      if (st.phase == InstallPhase.running) {
        final what = switch (st.op) {
          'install' => 'installing',
          'remove' => 'removing',
          _ => 'working on',
        };
        throw NoobRpcError(
          'The router is still $what the package, try again in a minute',
        );
      }
      await _clear();
      return null;
    }
    final r = st.phase == InstallPhase.running
        ? await _wait()
        : (st.rc!, _tail(st.log));
    if (st.phase == InstallPhase.done) await _clear();
    return r;
  }

  Future<void> _clear() async {
    try {
      await _io.exec('/bin/sh', ['-c', 'rm -f $_rc $_log $_pid $_op']);
    } catch (_) {}
  }

  (int, String)? _finished(String out) {
    final c = _Check(out);
    final rc = c.rc;
    if (rc == null) return null;
    _ranVersion = c.version;
    unawaited(_clear());
    final log = _tail(c.log);
    return (rc, log.isEmpty ? 'Error $rc' : log);
  }

  Future<(int, String)> _wait() async {
    try {
      final done = _finished(
        (await _io.exec('/bin/sh', ['-c', _waitSh, 'sh', _rc, _log, _ver])).$2,
      );
      if (done != null) return done;
    } catch (e) {
      if (_signedOut(e)) {
        throw const NoobRpcError(
          'Lost access to the router. Sign in to the router again and check',
        );
      }
    }
    for (var i = 0; i < _polls; i++) {
      try {
        final rc = int.tryParse((await _io.read(_rc))?.trim() ?? '');
        if (rc != null) {
          final log = _tail(await _io.read(_log) ?? '');
          await _clear();
          return (rc, log.isEmpty ? 'Error $rc' : log);
        }
      } catch (e) {
        if (_signedOut(e)) {
          throw const NoobRpcError(
            'Lost access to the router. Sign in to the router again and check',
          );
        }
      }
      await _sleep(const Duration(seconds: 3));
    }
    throw const NoobRpcError(
      'The router is still installing. It did not finish in 3 minutes',
    );
  }

  Future<(int, String)> _run(
    String op,
    String pm,
    String arg, {
    bool temp = false,
    int? size,
  }) async {
    final drop = temp ? 'rm -f "\$1"; ' : '';
    final check = size == null
        ? ''
        : '[ "\$(wc -c <"\$1")" = $size ] || { rm -f "\$1"; exit $_badCopy; }; ';
    try {
      final r = await _io.exec('/bin/sh', [
        '-c',
        'rm -f $_rc $_log $_pid $_op; $check'
            'echo $op >$_op; '
            '($pm "\$1" >$_log 2>&1; r=\$?; ${drop}echo \$r >$_rc) '
            '</dev/null >/dev/null 2>&1 & echo \$! >$_pid; '
            'set -- $_rc $_log $_ver; $_waitSh',
        'sh',
        arg,
      ]);
      if (r.$1 != 0) return (r.$1, r.$2);
      final done = _finished(r.$2);
      if (done != null) return done;
    } catch (e) {
      if (!identical(e, NoobRpcError.slow)) return (1, _say(e));
    }
    return _wait();
  }

  Future<(HelperRelease?, bool)> _lookup() =>
      _latest().then<(HelperRelease?, bool)>(
        (r) => (r, false),
        onError: (_) => (null, true),
      );

  Future<void> install() async {
    final all = [..._needs, this];
    final lookups = [for (final i in all) i._lookup()];
    final checks = await _checkAll([for (final i in all) i.package]);
    for (var k = 0; k < all.length; k++) {
      await all[k]._installWith(checks[all[k].package]!, lookups[k]);
    }
  }

  Future<void> _installWith(
    _Check st,
    Future<(HelperRelease?, bool)> lookup,
  ) async {
    final prior = await _resume('install', st);
    if (prior != null) {
      if (prior.$1 != 0) throw NoobRpcError(_fail(prior.$2));
      return _reload();
    }
    final have = st.version ?? await installed();
    final (rel, offline) = await lookup;
    if (have != null && (rel == null || !isNewerVersion(rel.version, have))) {
      return;
    }
    if (offline) {
      throw const NoobRpcError("Couldn't reach GitHub to find the package");
    }
    if (rel == null) {
      throw const NoobRpcError("This package isn't published yet");
    }
    await _put(rel, st.apk);
  }

  Future<void> goBack() async {
    final st = await _check();
    final prior = await _resume('install', st);
    if (prior != null) {
      if (prior.$1 != 0) throw NoobRpcError(_fail(prior.$2));
      return _reload();
    }
    final HelperRelease? rel;
    try {
      rel = await _stable();
    } catch (_) {
      throw const NoobRpcError("Couldn't reach GitHub to find the package");
    }
    if (rel == null) {
      throw const NoobRpcError('This package has no stable version yet');
    }
    await _put(rel, st.apk);
  }

  Future<void> _put(HelperRelease rel, bool apk) async {
    final url = apk ? rel.apkUrl : rel.ipkUrl;
    if (url.isEmpty) {
      throw const NoobRpcError('This release has no package for this router');
    }
    final pm = apk
        ? 'apk add --allow-untrusted'
        : 'opkg install --force-downgrade';
    final path = '/tmp/$package.${apk ? 'apk' : 'ipk'}';
    String? note;
    List<int> bytes = const [];
    try {
      bytes = await _download(url);
      if (bytes.length > _maxWrite) {
        note = 'The package is too big to send from the phone';
      }
    } catch (_) {
      note = 'Could not download the package on the phone';
    }
    if (note == null) {
      try {
        await _io.write(path, bytes);
      } catch (e) {
        if (_full.hasMatch(_say(e))) {
          throw NoobRpcError(
            'Could not copy the package to the router. '
            'The router may be out of space (${_say(e)})',
          );
        }
        note = "The router wouldn't take the package from the phone";
      }
    }
    if (note == null) {
      final r = await _run('install', pm, path, temp: true, size: bytes.length);
      if (r.$1 == _badCopy) {
        note = 'The package was not copied intact';
      } else if (r.$1 != 0) {
        throw NoobRpcError(_fail(r.$2));
      }
    }
    if (note != null) {
      final r = await _run('install', pm, url);
      if (r.$1 != 0) {
        final why = _fail(r.$2);
        throw NoobRpcError(
          why == _busy
              ? why
              : note.length < 60
              ? '${r.$2} · $note'
              : r.$2,
        );
      }
    }
    await _reload();
  }

  Future<void> _reloadRpcd() async {
    try {
      await _io.exec('/bin/sh', [
        '-c',
        '(sleep 1; /etc/init.d/rpcd reload) </dev/null >/dev/null 2>&1 &',
      ]);
    } catch (_) {}
  }

  Future<void> _reload() async {
    unawaited(_reloadRpcd());
    if (_ranVersion != null && package != 'keystone-history') return;
    for (var i = 0; i < 5; i++) {
      if (await installed() != null) return;
      await _sleep(const Duration(seconds: 2));
    }
    throw const NoobRpcError(
      'Installed, but it is not answering. '
      'Sign in to the router again and check',
    );
  }

  Future<void> remove() async {
    final st = await _check();
    final prior = await _resume('remove', st);
    final r =
        prior ??
        await _run('remove', st.apk ? 'apk del' : 'opkg remove', package);
    if (r.$1 != 0) throw NoobRpcError(_fail(r.$2));
    await _reloadRpcd();
  }
}
