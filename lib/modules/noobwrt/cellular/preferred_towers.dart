// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/state/app_state.dart';

import '../noob_rpc.dart';

const _config = 'auto-pci-cell';

class Tower {
  final String section;
  final String pci;
  final String earfcn;
  final bool enabled;
  const Tower({
    required this.section,
    required this.pci,
    required this.earfcn,
    required this.enabled,
  });
}

bool firmwareSamples(List<Tower> list) {
  const samples = {'175/400', '175/525', '115/1725'};
  return list.length == samples.length &&
      list.every((t) => samples.contains('${t.pci}/${t.earfcn}'));
}

abstract class UciIo {
  Future<List<Map<String, dynamic>>> sections(String config);
  Future<void> set(String config, String section, Map<String, String> v);
  Future<String> add(String config, String type);
  Future<void> delete(String config, String section);
  Future<void> commit(String config);
}

class _RouterUciIo implements UciIo {
  final AppState app;
  _RouterUciIo(this.app);

  @override
  Future<List<Map<String, dynamic>>> sections(String config) =>
      noobUciSections(app, config);

  @override
  Future<void> set(String config, String section, Map<String, String> v) =>
      noobCall(app, 'uci', 'set', {
        'config': config,
        'section': section,
        'values': v,
      });

  @override
  Future<String> add(String config, String type) async {
    final r = await noobCall(app, 'uci', 'add', {
      'config': config,
      'type': type,
    });
    return r['section'].toString();
  }

  @override
  Future<void> delete(String config, String section) =>
      noobCall(app, 'uci', 'delete', {'config': config, 'section': section});

  @override
  Future<void> commit(String config) => noobUciCommit(app, config);
}

class PreferredTowers {
  final UciIo _io;
  PreferredTowers(AppState app, {UciIo? io}) : _io = io ?? _RouterUciIo(app);

  (bool, List<Tower>) _parse(List<Map<String, dynamic>> all) {
    var on = false;
    final towers = <Tower>[];
    for (final s in all) {
      if (s['.name'] == 'main') {
        on = '${s['enabled']}' == '1';
      } else if (s['.type'] == 'cell') {
        towers.add(
          Tower(
            section: '${s['.name']}',
            pci: '${s['pci'] ?? ''}'.trim(),
            earfcn: '${s['earfcn'] ?? ''}'.trim(),
            enabled: '${s['enabled']}' != '0',
          ),
        );
      }
    }
    return (on, towers);
  }

  Future<(bool on, List<Tower>)?> load() async {
    try {
      return _parse(await _io.sections(_config));
    } catch (_) {
      return null;
    }
  }

  Future<void> _setCommit(String section, Map<String, String> v) async {
    await _io.set(_config, section, v);
    await _io.commit(_config);
  }

  Future<void> setOn(bool on) =>
      _setCommit('main', {'enabled': on ? '1' : '0'});

  Future<void> setEnabled(Tower t, bool on) =>
      _setCommit(t.section, {'enabled': on ? '1' : '0'});

  Future<void> add(String earfcn, String pci) async {
    final e = earfcn.trim();
    final p = pci.trim();
    if (e.isEmpty || p.isEmpty) {
      throw ArgumentError('earfcn and pci are required');
    }
    final towers = _parse(await _io.sections(_config)).$2;
    for (final t in towers) {
      if (t.earfcn == e && t.pci == p) {
        return _setCommit(t.section, {'enabled': '1'});
      }
    }
    final section = await _io.add(_config, 'cell');
    try {
      await _io.set(_config, section, {'pci': p, 'earfcn': e, 'enabled': '1'});
    } catch (_) {
      await _io.delete(_config, section);
      rethrow;
    }
    await _io.commit(_config);
  }

  Future<void> remove(Tower t) async {
    await _io.delete(_config, t.section);
    await _io.commit(_config);
  }

  Future<void> removeAll(List<Tower> list) async {
    for (final t in list) {
      await _io.delete(_config, t.section);
    }
    await _io.commit(_config);
  }
}
