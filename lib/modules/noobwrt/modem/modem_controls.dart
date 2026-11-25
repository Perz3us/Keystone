// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:yet_another_luci_app/state/app_state.dart';

import '../noob_rpc.dart';

typedef ScriptRun = Future<String> Function(String script, List<String> args);

class NetMode {
  const NetMode(this.id, this.label);
  final String id;
  final String label;
}

class SimSlots {
  const SimSlots(this.slots, this.active);
  final List<(String id, String label, bool present)> slots;
  final String active;
}

enum SpeedOption {
  ca('Carrier aggregation', 'caenabled'),
  qam256('256QAM', '256qam'),
  ulca('Uplink aggregation', 'ulca');

  const SpeedOption(this.label, this.key);
  final String label;
  final String key;
}

abstract class ModemControls {
  Future<bool> canRestart();
  Future<void> restart();
  Future<bool> canReconnect();
  Future<void> reconnect();
  Future<bool> canPowerCycle();
  Future<void> powerCycle();
  Future<(List<NetMode>, String)?> netModes();
  Future<void> setNetMode(String id);
  Future<bool?> speed(SpeedOption o);
  Future<void> setSpeed(SpeedOption o, bool on);
  Future<SimSlots?> sims();
  Future<void> setSim(String id);
  Future<(bool manual, String apn)?> apn();
  Future<void> setApn({required bool manual, String apn = ''});
  Future<bool?> roaming();
  Future<void> setRoaming(bool on);
}

typedef _Active = ({String path, String section, String iface, bool manual});

class FiveGModemControls implements ModemControls {
  FiveGModemControls(
    this.app, {
    ScriptRun? run,
    Future<List<Map<String, dynamic>>> Function(String config)? sections,
    Future<void> Function(
      String config,
      String section,
      Map<String, String> values,
    )?
    uciSet,
  }) : _run = run ?? _exec(app),
       _sections = sections ?? ((c) => noobUciSections(app, c)),
       _uciSet = uciSet ?? ((c, s, v) => noobUciSet(app, c, s, v));

  final AppState app;
  final ScriptRun _run;
  final Future<List<Map<String, dynamic>>> Function(String config) _sections;
  final Future<void> Function(
    String config,
    String section,
    Map<String, String> values,
  )
  _uciSet;

  static const _dir = '/usr/share/5gmodem/';
  static const _bands = '${_dir}bands.sh';
  static const _reboot = '${_dir}reboot_modem.sh';
  static const _setopt = '${_dir}setopt.sh';
  static const _simslot = '${_dir}simslot.sh';

  static ScriptRun _exec(AppState app) => (script, args) async {
    final r = await noobCall(app, 'file', 'exec', {
      'command': script,
      'params': args,
    });
    final out = '${r['stdout'] ?? ''}'.trim();
    if (r['code'] is int && r['code'] != 0) {
      throw NoobRpcError(out.isEmpty ? 'Error ${r['code']}' : out);
    }
    return out;
  };

  Future<T?> _try<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _map(String s) {
    final j = jsonDecode(s);
    return j is Map ? Map<String, dynamic>.from(j) : null;
  }

  @override
  Future<bool> canRestart() async =>
      await _try(() async {
        await _run(_reboot, ['haspower']);
        return true;
      }) ??
      false;

  @override
  Future<void> restart() => _run(_reboot, ['soft']);

  @override
  Future<bool> canReconnect() async => true;

  @override
  Future<void> reconnect() => _run(_setopt, ['reconnect']);

  @override
  Future<bool> canPowerCycle() async =>
      await _try(() async {
        final m = _map(await _run(_reboot, ['hasusbpower']));
        return '${m?['method'] ?? ''}'.isNotEmpty;
      }) ??
      false;

  @override
  Future<void> powerCycle() => _run(_reboot, ['usbpower']);

  @override
  Future<(List<NetMode>, String)?> netModes() => _try(() async {
    final j = _map(await _run(_bands, ['json']));
    final modes = j?['modes'];
    if (j == null || modes is! List || modes.isEmpty) return null;
    return (
      [
        for (final m in modes.whereType<Map>())
          NetMode('${m['id']}', '${m['label']}'),
      ],
      '${j['currentmode'] ?? ''}',
    );
  });

  @override
  Future<void> setNetMode(String id) => _run(_bands, ['setmode', id]);

  @override
  Future<bool?> speed(SpeedOption o) => _try(() async {
    return switch (await _run(_bands, ['get${o.key}'])) {
      '1' => true,
      '0' => false,
      _ => null,
    };
  });

  @override
  Future<void> setSpeed(SpeedOption o, bool on) =>
      _run(_bands, ['set${o.key}', on ? '1' : '0']);

  @override
  Future<SimSlots?> sims() => _try(() async {
    final j = _map(await _run(_simslot, const []));
    final slots = j?['slots'];
    if (j == null || slots is! List || slots.length < 2) return null;
    return SimSlots([
      for (final s in slots.whereType<Map>())
        ('${s['id']}', '${s['label']}', '${s['present']}' == '1'),
    ], '${j['active'] ?? ''}');
  });

  @override
  Future<void> setSim(String id) => _run(_simslot, ['set', id]);

  Future<_Active?> _active() => _try(() async {
    final all = await _sections('5gmodem');
    final top = all.firstOrNull;
    final path = '${top?['active_modem'] ?? ''}';
    if (path.isEmpty) return null;
    final name = 'm_${path.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
    final sec = all.where((s) => s['.name'] == name).firstOrNull;
    final iface = '${sec?['network'] ?? top?['network'] ?? ''}';
    if (iface.isEmpty) return null;
    return (
      path: path,
      section: name,
      iface: iface,
      manual: sec?['apn_mode'] == 'manual',
    );
  });

  Future<Map<String, dynamic>?> _iface(String name) async =>
      (await _sections('network')).where((s) => s['.name'] == name).firstOrNull;

  @override
  Future<(bool manual, String apn)?> apn() => _try(() async {
    final a = await _active();
    if (a == null) return null;
    return (a.manual, '${(await _iface(a.iface))?['apn'] ?? ''}');
  });

  @override
  Future<void> setApn({required bool manual, String apn = ''}) async {
    final a = await _active();
    if (a == null) throw const NoobRpcError('No active modem');
    await _uciSet('5gmodem', a.section, {
      'apn_mode': manual ? 'manual' : 'auto',
    });
    await _uciSet('network', a.iface, {'apn': manual ? apn : ''});
    await _run(_setopt, ['reconnect']);
  }

  @override
  Future<bool?> roaming() => _try(() async {
    final a = await _active();
    if (a == null) return null;
    final v = (await _iface(a.iface))?['allow_roaming'];
    return v == null ? null : '$v' == '1';
  });

  @override
  Future<void> setRoaming(bool on) async {
    final a = await _active();
    if (a == null) throw const NoobRpcError('No active modem');
    await _run(_setopt, ['roaming', a.path, on ? '1' : '0']);
  }
}
