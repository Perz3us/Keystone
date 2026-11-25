// SPDX-License-Identifier: GPL-3.0-or-later

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

HelperRelease? newestRelease(Object? json, String package) {
  HelperRelease? best;
  for (final r in json is List ? json : const []) {
    if (r is Map && r['draft'] == true) continue;
    final rel = releaseFor(r, package);
    if (rel != null &&
        (best == null || isNewerVersion(rel.version, best.version))) {
      best = rel;
    }
  }
  return best;
}

Future<HelperRelease?> _fetchRelease(
  String package, {
  required bool experimental,
}) async {
  final res = await http
      .get(
        Uri.parse(
          'https://api.github.com/repos/Perz3us/keystone-packages/releases'
          '${experimental ? '?per_page=30' : '/latest'}',
        ),
        headers: {'Accept': 'application/vnd.github+json'},
      )
      .timeout(const Duration(seconds: 15));
  if (res.statusCode == 404) return null;
  if (res.statusCode != 200) {
    throw NoobRpcError('GitHub answered ${res.statusCode}');
  }
  final json = jsonDecode(res.body);
  return experimental
      ? newestRelease(json, package)
      : releaseFor(json, package);
}

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

class HelperInstaller {
  HelperInstaller(
    AppState app, {
    this.package = 'keystone-history',
    RouterIo? io,
    Future<HelperRelease?> Function()? latest,
    Future<HelperRelease?> Function()? stable,
    Future<List<int>> Function(String url)? download,
    Future<String?> Function()? version,
    Future<Map<String, dynamic>?> Function()? info,
    Future<void> Function(int days)? setKeep,
    Future<void> Function(Duration)? sleep,
  }) : _io = io ?? _UbusIo(app),
       _latest =
           latest ??
           (() async =>
               _fetchRelease(package, experimental: await loadExperimental())),
       _stable = stable ?? (() => _fetchRelease(package, experimental: false)),
       _download = download ?? _fetchBytes,
       _version = version ?? (() => helperVersion(app)),
       _info = info ?? (() => helperInfo(app)),
       _setKeep = setKeep ?? ((d) => setKeepDays(app, d)),
       _sleep = sleep ?? Future.delayed;

  final String package;
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

  Future<bool> _isApk() async =>
      (await _io.exec('/bin/sh', ['-c', 'command -v apk'])).$1 == 0;

  Future<InstallState> status() async {
    final op = (await _io.read(_op))?.trim() ?? '';
    final rc = int.tryParse((await _io.read(_rc))?.trim() ?? '');
    if (rc != null) {
      return InstallState(
        InstallPhase.done,
        op: op,
        code: rc,
        log: _tail(await _io.read(_log) ?? ''),
      );
    }
    final pid = (await _io.read(_pid))?.trim() ?? '';
    if (int.tryParse(pid) == null) return const InstallState(InstallPhase.idle);
    final alive = await _io.exec('/bin/sh', ['-c', 'kill -0 "\$1"', 'sh', pid]);
    return InstallState(
      alive.$1 == 0 ? InstallPhase.running : InstallPhase.idle,
      op: op,
    );
  }

  Future<(int, String)?> _resume(String op) async {
    final st = await status();
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
        : (st.code, st.log);
    if (st.phase == InstallPhase.done) await _clear();
    return r;
  }

  Future<void> _clear() async {
    try {
      await _io.exec('/bin/sh', ['-c', 'rm -f $_rc $_log $_pid $_op']);
    } catch (_) {}
  }

  Future<(int, String)> _wait() async {
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
  }) async {
    final drop = temp ? 'rm -f "\$1"; ' : '';
    try {
      final r = await _io.exec('/bin/sh', [
        '-c',
        'rm -f $_rc $_log $_pid $_op; echo $op >$_op; '
            '($pm "\$1" >$_log 2>&1; r=\$?; ${drop}echo \$r >$_rc) '
            '</dev/null >/dev/null 2>&1 & echo \$! >$_pid',
        'sh',
        arg,
      ]);
      if (r.$1 != 0) return (r.$1, r.$2);
    } catch (e) {
      return (1, _say(e));
    }
    return _wait();
  }

  Future<void> install() async {
    final prior = await _resume('install');
    if (prior != null) {
      if (prior.$1 != 0) throw NoobRpcError(_fail(prior.$2));
      return _reload();
    }
    final have = await installed();
    HelperRelease? rel;
    var offline = false;
    try {
      rel = await _latest();
    } catch (_) {
      offline = true;
    }
    if (have != null && (rel == null || !isNewerVersion(rel.version, have))) {
      return;
    }
    if (offline) {
      throw const NoobRpcError("Couldn't reach GitHub to find the package");
    }
    if (rel == null) {
      throw const NoobRpcError("This package isn't published yet");
    }
    await _put(rel);
  }

  Future<void> goBack() async {
    final prior = await _resume('install');
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
    await _put(rel);
  }

  Future<void> _put(HelperRelease rel) async {
    final apk = await _isApk();
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
      var size = '';
      try {
        size = (await _io.exec('/bin/sh', [
          '-c',
          'wc -c < "\$1"',
          'sh',
          path,
        ])).$2;
      } catch (_) {}
      if (int.tryParse(size.trim()) != bytes.length) {
        note = 'The package was not copied intact';
      }
    }
    if (note == null) {
      final r = await _run('install', pm, path, temp: true);
      if (r.$1 != 0) throw NoobRpcError(_fail(r.$2));
    } else {
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
    await _reloadRpcd();
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
    final prior = await _resume('remove');
    final apk = await _isApk();
    final r =
        prior ?? await _run('remove', apk ? 'apk del' : 'opkg remove', package);
    if (r.$1 != 0) throw NoobRpcError(_fail(r.$2));
    await _reloadRpcd();
  }
}
