// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../history/helper_sheet.dart';
import '../modem/modem_controls.dart';
import '../noob_rpc.dart';
import '../noob_widgets.dart';
import 'cell_guard.dart';
import 'cellular_data.dart';
import 'preferred_towers.dart';

class LockPending implements Exception {
  const LockPending();
}

const lockPartnersSh = r'''partners() {
  s=$(uci -q show 5gmodem | sed -n "s/^5gmodem\.\([^.]*\)\.active_modem='\{0,1\}\([^']*\)'\{0,1\}$/\1 \2/p" | head -n 1)
  [ -n "$s" ] || return 0
  m=m_$(printf '%s' "${s#* }" | sed 's/[^A-Za-z0-9]/_/g')
  s=${s%% *}
  port=$(uci -q get "5gmodem.$m.at_port" || uci -q get "5gmodem.$s.at_port" || uci -q get "5gmodem.$s.device")
  [ -n "$port" ] || return 0
  c=$(cat "/etc/auto-pci-cell/ca_$1_$2" 2>/dev/null)
  case $c in *[!0-9,]*) c= ;; esac
  [ -n "$c" ] || c=$(/usr/share/5gmodem/atcmd.sh "$port" AT+QCAINFO 2>/dev/null | tr -d '\r" ' | awk -F, -v e="$1" -v q="$2" '
    /^\+QCAINFO:PCC,/ { on = ($2 == e && $6 == q) }
    /^\+QCAINFO:SCC,/ && on && $4 ~ /^LTEBAND/ && $2 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ && !($2 == e && $6 == q) && !seen[$2 "," $6]++ { o = o (o == "" ? "" : ",") $2 "," $6 }
    END { print o }')
  c=$(printf '%s' "$c" | cut -d, -f1-18)
  [ -n "$c" ] && echo "$port $(( ($(printf '%s' "$c" | tr -cd , | wc -c) + 1) / 2 + 1 )),$1,$2,$c"
}
''';

const _lockSh =
    '$lockPartnersSh'
    r'''rc=/tmp/keystone-celllock.rc
out=/tmp/keystone-celllock.out
job=/tmp/keystone-celllock.job
rm -f "$rc" "$out"
echo $$ >"$job"
me=$$
( ca=
  [ "$1 $2" = "setcelllock cell" ] && ca=$(partners "$3" "$4")
  n=0
  while :; do
    /usr/share/5gmodem/bands.sh "$@" >"$out" 2>&1
    r=$?
    [ "$r" = 0 ] || [ $n -ge 3 ] || ! grep -qi busy "$out" && break
    sleep 5
    [ "$(cat "$job" 2>/dev/null)" = "$me" ] || exit 0
    n=$((n+1))
  done
  [ "$1 $2" = "setcelllock off" ] &&
    /usr/share/5gmodem/bands.sh setcelllock5g off >/dev/null 2>&1
  [ "$(cat "$job" 2>/dev/null)" = "$me" ] || exit 0
  echo $r >"$rc"
  [ "$r" = 0 ] && [ -n "$ca" ] || exit 0
  j=0
  while [ $j -lt 6 ] && [ "$(cat "$job" 2>/dev/null)" = "$me" ]; do
    sleep 5
    if /usr/share/5gmodem/atcmd.sh "${ca%% *}" AT+QCAINFO 2>/dev/null | tr -d '\r" ' |
      grep -q "^+QCAINFO:PCC,$3,[^,]*,[^,]*,[^,]*,$4,"; then
      [ "$(cat "$job" 2>/dev/null)" = "$me" ] &&
        /usr/share/5gmodem/atcmd.sh "${ca%% *}" "AT+QNWLOCK=\"common/4g\",${ca#* }" >/dev/null 2>&1
      break
    fi
    j=$((j+1))
  done ) </dev/null >/dev/null 2>&1 &
i=0
while [ ! -s "$rc" ] && [ $i -lt 5 ]; do sleep 1; i=$((i+1)); done
[ -s "$rc" ] && { echo "rc=$(cat "$rc")"; cat "$out"; }
true''';

String? lockResult(String out) {
  final m = RegExp(r'^rc=(\d+)\s*').firstMatch(out);
  if (m == null) throw const LockPending();
  if (m[1] == '0') return null;
  final said = out.substring(m.end).trim();
  return said.isEmpty ? 'Error ${m[1]}' : said;
}

abstract class ModemLocks {
  Future<List<BandClass>> bands();

  Future<void> saveBands(BandClass c, List<String> picked);

  Future<CellLock> cellLock();

  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  });

  bool get nrNeedsBand;
}

class QmodemLocks implements ModemLocks {
  QmodemLocks(this.q);
  final Future<Map<String, dynamic>> Function(
    String method, [
    Map<String, dynamic> extra,
  ])
  q;

  @override
  bool get nrNeedsBand => true;

  @override
  Future<List<BandClass>> bands() async =>
      BandClass.parse(await q('get_lockband'));

  @override
  Future<void> saveBands(BandClass c, List<String> picked) =>
      q('set_lockband', {
        'params': {'band_class': c.id, 'lock_band': picked.join(',')},
      });

  @override
  Future<CellLock> cellLock() async =>
      CellLock.parse(await q('get_neighborcell'));

  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) => q('set_neighborcell', {
    'params': {
      'rat': nr ? '1' : '0',
      'pci': pci,
      'arfcn': arfcn,
      'band': band,
      'scs': scs,
      'en_boot_hook': '0',
    },
  });
}

class QmodemControls implements ModemControls {
  QmodemControls(this.q);
  final Future<Map<String, dynamic>> Function(
    String method, [
    Map<String, dynamic> extra,
  ])
  q;

  Future<Map<String, dynamic>?> _try(String m) async {
    try {
      return await q(m);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>?> _prefer() async {
    final p = (await _try('get_network_prefer'))?['network_prefer'];
    if (p is! Map || p.length < 2) return null;
    return {for (final e in p.entries) '${e.key}': '${e.value}'};
  }

  @override
  Future<bool> canRestart() async {
    final c = (await _try('get_reboot_caps'))?['reboot_caps'];
    return c is Map && '${c['soft_reboot_caps']}' == '1';
  }

  @override
  Future<void> restart() => q('do_reboot', {
    'params': {'method': 'soft'},
  });

  @override
  Future<bool> canReconnect() async => false;

  @override
  Future<void> reconnect() => throw UnsupportedError('reconnect');

  @override
  Future<bool> canPowerCycle() async => false;

  @override
  Future<void> powerCycle() => throw UnsupportedError('powerCycle');

  @override
  Future<(List<NetMode>, String)?> netModes() async {
    final p = await _prefer();
    if (p == null) return null;
    final on = {
      for (final e in p.entries)
        if (e.value == '1') e.key,
    };
    final both = p.length > 2 && p.containsKey('4G') && p.containsKey('5G');
    return (
      [
        const NetMode('auto', 'Auto'),
        for (final k in p.keys) NetMode(k, '$k only'),
        if (both) const NetMode('4G,5G', '4G+5G'),
      ],
      on.length == p.length
          ? 'auto'
          : both && on.length == 2 && on.containsAll(['4G', '5G'])
          ? '4G,5G'
          : on.length == 1
          ? on.single
          : '',
    );
  }

  @override
  Future<void> setNetMode(String id) async {
    final types = id == 'auto'
        ? (await _prefer())?.keys.toList()
        : id.split(',');
    if (types == null) throw StateError('No network types');
    await q('set_network_prefer', {'params': types});
  }

  @override
  Future<bool?> speed(SpeedOption o) async => null;

  @override
  Future<void> setSpeed(SpeedOption o, bool on) =>
      throw UnsupportedError('setSpeed');

  String _simLabel(String id) {
    final n = int.tryParse(id);
    return 'SIM ${n == null ? id : n + 1}';
  }

  @override
  Future<SimSlots?> sims() async {
    final caps = await _try('get_sim_switch_capabilities');
    final slots = caps?['simSlots'];
    if ('${caps?['supportSwitch']}' != '1' || slots is! List) return null;
    if (slots.length < 2) return null;
    final ids = [for (final s in slots) '$s'];
    final active = '${(await _try('get_sim_slot'))?['sim_slot']}';
    if (!ids.contains(active)) return null;
    return SimSlots([for (final s in ids) (s, _simLabel(s), true)], active);
  }

  @override
  Future<void> setSim(String id) =>
      q('set_sim_slot', {'slot': id, 'params': id});

  @override
  Future<(bool manual, String apn)?> apn() async => null;

  @override
  Future<void> setApn({required bool manual, String apn = ''}) =>
      throw UnsupportedError('setApn');

  @override
  Future<bool?> roaming() async => null;

  @override
  Future<void> setRoaming(bool on) => throw UnsupportedError('setRoaming');
}

class FiveGModemLocks implements ModemLocks {
  FiveGModemLocks(this.app);
  final AppState app;
  static const _dir = '/usr/share/5gmodem/';
  Map<String, dynamic>? _json;

  Future<String> _run(List<String> args, [String script = 'bands.sh']) async {
    final r = await noobCall(app, 'file', 'exec', {
      'command': '$_dir$script',
      'params': args,
    });
    final out = '${r['stdout'] ?? ''}'.trim();
    if (r['code'] is int && r['code'] != 0) {
      throw NoobRpcError(out.isEmpty ? 'Error ${r['code']}' : out);
    }
    return out;
  }

  Future<void> _change(List<String> args) async {
    final Map<String, dynamic> r;
    try {
      r = await noobCall(app, 'file', 'exec', {
        'command': '/bin/sh',
        'params': ['-c', _lockSh, 'sh', ...args],
      });
    } on NoobRpcError catch (e) {
      if (identical(e, NoobRpcError.slow)) throw const LockPending();
      rethrow;
    }
    final err = lockResult('${r['stdout'] ?? ''}'.trim());
    if (err != null) throw NoobRpcError(err);
  }

  Future<Map<String, dynamic>> _read() async => _json ??= await _fresh();

  // Plain `json` may be five minutes old; older scripts have no `jsonrefresh`.
  Future<Map<String, dynamic>> _fresh() async {
    try {
      final j = FiveGBands.decode(await _run(['jsonrefresh']));
      if (j.isNotEmpty) return j;
    } on FormatException catch (_) {
    } on NoobRpcError catch (_) {}
    return FiveGBands.decode(await _run(['json']));
  }

  Future<(String section, String port, String lock)?> _modem() async {
    final all = await noobUciSections(app, '5gmodem');
    final top = all.where((s) => s['active_modem'] != null).firstOrNull;
    if (top == null) return null;
    final name =
        'm_${'${top['active_modem']}'.replaceAll(RegExp('[^A-Za-z0-9]'), '_')}';
    final sec = all.where((s) => s['.name'] == name).firstOrNull;
    return (
      name,
      '${sec?['at_port'] ?? top['at_port'] ?? top['device'] ?? ''}',
      '${sec?['celllock'] ?? ''}',
    );
  }

  // bands.sh refuses to write while ModemManager is not connected, which is
  // what a lock to an unusable cell causes. atcmd.sh has no such check.
  Future<bool> _unlockByAt() async {
    final m = await _modem();
    if (m == null || m.$2.isEmpty) return false;
    Future<bool> at(String cmd) async => RegExp(
      r'^\s*OK\s*$',
      multiLine: true,
    ).hasMatch(await _run([m.$2, cmd], 'atcmd.sh'));
    final ok =
        await at('AT+QNWLOCK="common/4g",0') ||
        await at('AT+QNWLOCK="common/lte",0');
    if (!ok) return false;
    // Otherwise 5gmodem puts the remembered lock back.
    if (m.$3.isNotEmpty) {
      await noobUciSet(app, '5gmodem', m.$1, {'celllock': ''});
    }
    try {
      await at('AT+QNWLOCK="common/5g",0');
      await at('AT+QNWLOCK="save_ctrl",1,1');
      await _run(['reconnect'], 'setopt.sh');
    } catch (_) {}
    return true;
  }

  @override
  bool get nrNeedsBand => false;

  @override
  Future<List<BandClass>> bands() async => FiveGBands.classes(await _read());

  @override
  Future<void> saveBands(BandClass c, List<String> picked) async {
    _json = null;
    await _run([
      switch (c.id) {
        'NR_NSA' => 'setbands5gnsa',
        'NR' => 'setbands5gsa',
        _ => 'setbands',
      },
      picked.isEmpty ? 'default' : picked.join(' '),
    ]);
  }

  @override
  Future<CellLock> cellLock() async {
    _json = null;
    final j = await _read();
    final state = '${j['celllock'] ?? ''}';
    if (state.endsWith('readonly')) throw const CellLockUnsupported();
    if (state.isEmpty || state == 'Unsupported') {
      // Also what a silent modem gives, so trust a lock 5gmodem remembers.
      final kept = FiveGBands.lock({'celllock': (await _modem())?.$3});
      if (!kept.locked) throw const CellLockUnsupported();
      return kept;
    }
    return FiveGBands.lock(j);
  }

  @override
  Future<void> setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) async {
    _json = null;
    if (pci.isEmpty) {
      try {
        await _change(['setcelllock', 'off']);
      } on LockPending {
        rethrow;
      } on NoobRpcError catch (_) {
        if (!await _unlockByAt()) rethrow;
      }
      return;
    }
    await _change([nr ? 'setcelllock5g' : 'setcelllock', 'cell', arfcn, pci]);
  }
}

bool canSee(
  List<NearbyCell> cells, {
  required bool nr,
  required String pci,
  required String arfcn,
}) {
  if (cells.isEmpty) return true;
  final p = int.tryParse(pci.trim()), a = int.tryParse(arfcn.trim());
  return cells.any(
    (c) =>
        (c.rat == 'NR') == nr &&
        int.tryParse(c.pci) == p &&
        int.tryParse(c.arfcn) == a,
  );
}

Future<void> guardedLock(
  ModemLocks locks,
  CellGuard? guard, {
  required bool nr,
  String pci = '',
  String arfcn = '',
  String band = '',
  String scs = '',
}) async {
  final on = pci.isNotEmpty;
  var armed = false;
  if (on && guard != null) {
    try {
      await guard.arm(nr: nr, pci: pci, arfcn: arfcn);
      armed = true;
    } on NoobRpcError catch (e) {
      armed = identical(e, NoobRpcError.slow);
    } catch (_) {}
  }
  Future<void> disarm() async {
    try {
      await guard?.disarm();
    } catch (_) {}
  }

  try {
    await locks.setLock(nr: nr, pci: pci, arfcn: arfcn, band: band, scs: scs);
  } on LockPending {
    if (!on) await disarm();
    rethrow;
  } catch (_) {
    if (armed) await disarm();
    rethrow;
  }
  if (!on) await disarm();
}

bool _unsupported(Object e) =>
    e is CellLockUnsupported ||
    (e is NoobRpcError &&
        const {
          'Method not found',
          'Not found',
          'Not supported',
        }.contains(e.message));

enum _TowerAct { toggle, remove }

class LockControls extends StatefulWidget {
  const LockControls({
    super.key,
    required this.locks,
    this.nearby,
    this.nrBand,
    this.towers,
    this.guard,
  });

  final ModemLocks locks;

  final CellGuard? guard;

  final List<NearbyCell>? nearby;

  final String? nrBand;

  final PreferredTowers? towers;

  @override
  State<LockControls> createState() => _LockControlsState();
}

class _LockControlsState extends State<LockControls> {
  List<BandClass> _bands = const [];
  CellLock? _lock;
  (bool, List<Tower>)? _towers;
  final Map<String, Set<String>> _picked = {};
  final Set<String> _open = {};
  bool _loaded = false;
  bool _busy = false;
  bool _lockFailed = false;
  GuardState? _guard;
  bool _guardKnown = false;
  Timer? _refresh;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _readGuard() async {
    final g = widget.guard;
    if (g == null) return;
    try {
      final st = await g.info();
      if (mounted) {
        setState(() {
          _guard = st;
          _guardKnown = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    unawaited(_readGuard());
    await _loadTowers();
    if (mounted) await _readModem(5);
  }

  Future<void> _loadTowers() async {
    final towers = await widget.towers?.load();
    if (mounted) setState(() => _towers = towers);
  }

  void _readLater(int tries, Duration wait, [bool? want]) {
    _refresh?.cancel();
    _refresh = Timer(wait, () => _readModem(tries, want));
  }

  // [want] is the lock state just asked for; readings that lag it are retried.
  Future<void> _readModem(int tries, [bool? want]) async {
    final mine = ++_generation;
    bool stale() => !mounted || mine != _generation;
    unawaited(_readGuard());
    CellLock? lock;
    var failed = false;
    try {
      lock = await widget.locks.cellLock();
    } catch (e) {
      // Support seen once does not go away: the modem is just silent.
      failed = _lock != null || !_unsupported(e);
    }
    if (stale()) return;
    final lagging =
        tries > 0 && want != null && lock != null && lock.locked != want;
    setState(() {
      _loaded = true;
      _lockFailed = failed;
      if (!failed && !lagging) _lock = lock;
    });
    List<BandClass>? bands;
    try {
      bands = await widget.locks.bands();
    } catch (_) {}
    if (stale()) return;
    if (bands != null) setState(() => _bands = bands!);
    if (tries > 0 && (failed || lagging || bands == null)) {
      _readLater(tries - 1, const Duration(seconds: 10), want);
    }
  }

  Future<void> _do(
    String what,
    Future<void> Function() action, {
    VoidCallback? applied,
    bool? want,
  }) async {
    _refresh?.cancel();
    _generation++;
    setState(() => _busy = true);
    var ok = false;
    try {
      await action();
      ok = true;
      if (mounted) ksSay(context, what);
    } on LockPending {
      ok = true;
      if (mounted) {
        ksSay(
          context,
          'Sent. The modem is busy, so it can take a minute to change.',
        );
      }
    } catch (e) {
      if (mounted) ksSay(context, "The modem didn't take that: $e");
    }
    if (!mounted) return;
    if (ok && applied != null) setState(applied);
    await _loadTowers();
    if (!mounted) return;
    setState(() => _busy = false);
    _readLater(5, const Duration(seconds: 5), ok ? want : null);
  }

  Future<void> _saveBands(BandClass c) {
    final picked = _picked[c.id]!.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    return _do(
      '${c.title} bands saved.',
      () async {
        await widget.locks.saveBands(c, picked);
      },
      applied: () {
        _picked.remove(c.id);
        _bands = [
          for (final b in _bands)
            b.id == c.id ? BandClass(b.id, b.available, picked.toSet()) : b,
        ];
      },
    );
  }

  Future<void> _setLock({
    required bool nr,
    String pci = '',
    String arfcn = '',
    String band = '',
    String scs = '',
  }) => _do(
    pci.isEmpty ? 'Cell lock removed.' : 'Locked to PCI $pci.',
    () => guardedLock(
      widget.locks,
      _guard == null ? null : widget.guard,
      nr: nr,
      pci: pci,
      arfcn: arfcn,
      band: band,
      scs: scs,
    ),
    want: pci.isNotEmpty,
    applied: () {
      final old = _lock;
      final text = 'PCI $pci · ${nr ? 'ARFCN' : 'EARFCN'} $arfcn';
      _lockFailed = false;
      _lock = pci.isEmpty
          ? CellLock(null, null, old?.nearby ?? const [])
          : CellLock(
              nr ? old?.lte : text,
              nr ? text : old?.nr,
              old?.nearby ?? const [],
            );
    },
  );

  @override
  Widget build(BuildContext context) {
    final lock = _lock;
    final nearby = _nearby;
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_bands.isNotEmpty)
          NoobSection(
            title: 'Bands',
            icon: Icons.tune,
            children: [
              for (final c in _bands) ..._bandClass(c),
              if (_open.isNotEmpty)
                const KsNote(
                  'No bands picked means all of them. Saving makes the '
                  'modem reconnect, which drops the internet for a few '
                  'seconds.',
                ),
            ],
          ),
        if (lock != null || _lockFailed)
          NoobSection(
            title: 'Cell lock',
            icon: Icons.lock_outline,
            trailing: lock == null ? null : Text(lock.locked ? 'On' : 'Off'),
            children: [
              if (lock != null) ...[
                NoobRow('4G', lock.lte ?? 'Not locked'),
                NoobRow('5G', lock.nr ?? 'Not locked'),
              ],
              if (_guard?.line case final l?) NoobRow('Cell guard', l),
              if (_lockFailed)
                const KsNote(
                  "The modem isn't answering. You can still unlock it.",
                ),
              if (_guard?.last case final e?)
                KsNote(
                  e.text,
                  action: 'OK',
                  onAction: () async {
                    try {
                      final st = await widget.guard!.ack();
                      if (mounted) setState(() => _guard = st);
                    } catch (_) {}
                  },
                ),
              if (_guardKnown && _guard == null)
                KsNote(
                  'Add Cell guard so a lock that leaves the router offline '
                  'removes itself.',
                  action: 'Add',
                  onAction: _addGuard,
                ),
              if (_towers != null) ..._towerRows(_towers!),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : () => _lockByHand(),
                    child: const Text('Lock to a cell'),
                  ),
                  // Always offered: the lock reading can lag or be wrong.
                  TextButton(
                    onPressed: _busy ? null : () => _setLock(nr: false),
                    child: const Text('Unlock'),
                  ),
                ],
              ),
            ],
          ),
        if (lock == null && !_lockFailed && _towers != null) ...[
          const KsSection('Preferred towers'),
          ..._towerRows(_towers!),
        ],
        if (nearby.isNotEmpty)
          NoobSection(
            title: 'Cells nearby',
            icon: Icons.radar,
            trailing: lock == null ? null : const Text('Tap to lock'),
            children: [
              for (final c in nearby)
                KsRow(
                  title: _cellTitle(c),
                  subtitle: _cellLine(c),
                  onTap:
                      _busy ||
                          !(lock != null || (_towers != null && c.rat != 'NR'))
                      ? null
                      : () => _cellSheet(c),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _addGuard() async {
    await showHelperSheet(context, widget.guard!.helper, text: cellGuardText);
    await _readGuard();
  }

  List<NearbyCell> get _nearby => widget.nearby ?? _lock?.nearby ?? const [];

  String _cellTitle(NearbyCell c) =>
      '${c.rat == 'NR' ? '5G' : '4G'} PCI ${c.pci} · '
      '${c.rat == 'NR' ? 'ARFCN' : 'EARFCN'} ${c.arfcn}'
      '${c.serving ? ' (serving)' : ''}';

  String _cellLine(NearbyCell c) => [
    if (c.rsrp != null) 'RSRP ${c.rsrp} dBm',
    if (c.rsrq != null) 'RSRQ ${c.rsrq} dB',
  ].join('  ');

  List<Widget> _bandClass(BandClass c) {
    final picked = _picked[c.id] ?? c.locked;
    final open = _open.contains(c.id) || _picked.containsKey(c.id);
    final all = picked.isEmpty || picked.length == c.available.length;
    final names = [
      for (final (id, name) in c.available)
        if (picked.contains(id)) name,
    ];
    return [
      KsRow(
        title: c.title,
        subtitle: all
            ? 'All ${c.available.length}'
            : '${picked.length} of ${c.available.length} · ${names.join(' ')}',
        trailing: Icon(
          open ? Icons.expand_less : Icons.expand_more,
          color: context.ks.mu,
        ),
        onTap: () => setState(
          () => _open.contains(c.id) ? _open.remove(c.id) : _open.add(c.id),
        ),
      ),
      if (open) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, name) in c.available)
              KsChip(
                name,
                many: true,
                selected: picked.contains(id),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        final next = {...picked};
                        next.contains(id) ? next.remove(id) : next.add(id);
                        _picked[c.id] = next;
                      }),
              ),
          ],
        ),
        if (_picked.containsKey(c.id))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _saveBands(c),
                  child: const Text('Save'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _picked.remove(c.id)),
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _towerRows((bool, List<Tower>) t) {
    final ks = context.ks;
    return [
      KsSwitchRow(
        title: 'Preferred towers',
        subtitle: 'Moves to the best tower on this list by itself',
        value: t.$1,
        busy: _busy,
        onChanged: (v) async {
          if (v &&
              !await ksConfirm(
                context,
                title: 'Turn on Preferred towers?',
                body:
                    'The modem may move to another tower. The connection '
                    'drops for a moment.',
                action: 'Turn on',
              )) {
            return;
          }
          if (mounted) {
            await _do(
              v ? 'Preferred towers on.' : 'Preferred towers off.',
              () async {
                await widget.towers!.setOn(v);
                if (v && _guard != null) {
                  try {
                    await widget.guard?.disarm();
                  } catch (_) {}
                }
              },
            );
          }
        },
      ),
      if (firmwareSamples(t.$2))
        KsNote(
          'These three came with the firmware as examples. They are not '
          'towers near you.',
          action: _busy ? null : 'Remove them',
          onAction: () =>
              _do('Examples removed.', () => widget.towers!.removeAll(t.$2)),
        ),
      for (final w in t.$2)
        KsRow(
          title: 'PCI ${w.pci} · EARFCN ${w.earfcn}',
          subtitle: w.enabled ? null : 'Off',
          chevron: false,
          trailing: PopupMenuButton<_TowerAct>(
            tooltip: 'Tower options',
            color: ks.sheet,
            icon: Icon(Icons.more_horiz, color: ks.mu),
            enabled: !_busy,
            onSelected: (a) =>
                a == _TowerAct.remove ? _removeTower(w) : _toggleTower(w),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _TowerAct.toggle,
                child: Text(
                  w.enabled ? 'Turn off' : 'Turn on',
                  style: KeystoneType.body(ks.tx),
                ),
              ),
              PopupMenuItem(
                value: _TowerAct.remove,
                child: Text('Remove', style: KeystoneType.body(ks.bad)),
              ),
            ],
          ),
        ),
    ];
  }

  Future<void> _toggleTower(Tower w) => _do(
    w.enabled ? 'Tower turned off.' : 'Tower turned on.',
    () => widget.towers!.setEnabled(w, !w.enabled),
  );

  Future<void> _removeTower(Tower w) async {
    final ok = await ksConfirm(
      context,
      title: 'Remove this tower?',
      body: 'PCI ${w.pci} · EARFCN ${w.earfcn} leaves the list.',
      action: 'Remove',
      danger: true,
    );
    if (ok) await _do('Tower removed.', () => widget.towers!.remove(w));
  }

  Future<void> _lockByHand([NearbyCell? from]) async {
    if (_towers?.$1 == true) {
      final ok = await ksConfirm(
        context,
        title: 'Turn off Preferred towers?',
        body:
            'Preferred towers is moving the modem between towers. '
            'Turn it off to lock by hand?',
        action: 'Turn off',
      );
      if (!ok || !mounted) return;
      await _do('Preferred towers off.', () => widget.towers!.setOn(false));
      if (!mounted || _towers?.$1 == true) return;
    }
    final cells = _nearby;
    if (from == null && cells.isNotEmpty) {
      final pick = await ksSheet<Object>(
        context,
        (b) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KsSection('Cells your modem can see'),
            for (final c in cells)
              KsRow(
                title: _cellTitle(c),
                subtitle: _cellLine(c),
                onTap: () => Navigator.pop(b, c),
              ),
            KsRow(
              title: 'Enter numbers yourself',
              onTap: () => Navigator.pop(b, false),
            ),
          ],
        ),
      );
      if (pick == null || !mounted) return;
      if (pick is NearbyCell) from = pick;
    }
    await _lockSheet(from);
  }

  Future<void> _cellSheet(NearbyCell c) async {
    final list = _towers?.$2;
    final canAdd = list != null && c.rat != 'NR';
    final known =
        canAdd && list.any((w) => w.pci == c.pci && w.earfcn == c.arfcn);
    final pick = await ksSheet<bool>(
      context,
      (b) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_lock != null)
            KsRow(
              title: 'Lock now',
              chevron: false,
              onTap: () => Navigator.pop(b, true),
            ),
          if (canAdd)
            KsRow(
              title: known
                  ? 'Already in preferred towers'
                  : 'Add to preferred towers',
              chevron: false,
              onTap: known ? null : () => Navigator.pop(b, false),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    if (pick) {
      await _lockByHand(c);
    } else {
      await _do(
        'Added to preferred towers.',
        () => widget.towers!.add(c.arfcn, c.pci),
      );
    }
  }

  Future<void> _lockSheet([NearbyCell? from]) async {
    final ks = context.ks;
    final needBand = widget.locks.nrNeedsBand;
    final pci = TextEditingController(text: from?.pci);
    final arfcn = TextEditingController(text: from?.arfcn);
    final band = TextEditingController(
      text: widget.nrBand?.replaceAll(RegExp(r'\D'), ''),
    );
    var nr = from?.rat == 'NR';
    var scs = '1';
    final form = GlobalKey<FormState>();
    String? need(String? v) =>
        int.tryParse(v?.trim() ?? '') == null ? 'Enter a number' : null;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: ks.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lock to a cell', style: KeystoneType.sheetTitle(ks.tx)),
                const SizedBox(height: 8),
                Text(
                  _guard == null
                      ? 'The modem stays on this cell only. If it loses it, '
                            'the internet stays down until you unlock.'
                      : "The modem stays on this cell only. If it can't "
                            'connect or stops working, Cell guard removes the '
                            'lock.',
                  style: KeystoneType.body(ks.tx2),
                ),
                const SizedBox(height: 12),
                KsChips<bool>(
                  options: const [(false, '4G'), (true, '5G')],
                  selected: nr,
                  onSelected: (v) => set(() => nr = v),
                ),
                KsField(
                  label: nr ? 'ARFCN' : 'EARFCN',
                  controller: arfcn,
                  keyboardType: TextInputType.number,
                  validator: need,
                ),
                KsField(
                  label: 'PCI',
                  controller: pci,
                  keyboardType: TextInputType.number,
                  validator: need,
                ),
                if (nr && needBand) ...[
                  KsField(
                    label: 'Band',
                    hint: '78',
                    controller: band,
                    keyboardType: TextInputType.number,
                    validator: need,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Subcarrier spacing',
                    style: KeystoneType.secondary(ks.tx2),
                  ),
                  const SizedBox(height: 6),
                  KsChips<String>(
                    options: const [('0', '15 kHz'), ('1', '30 kHz')],
                    selected: scs,
                    onSelected: (v) => set(() => scs = v),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    if (form.currentState!.validate()) Navigator.pop(c, true);
                  },
                  child: const Text('Lock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final seen = canSee(_nearby, nr: nr, pci: pci.text, arfcn: arfcn.text);
      if (!seen &&
          !await ksConfirm(
            context,
            title: "Your modem can't see this cell right now",
            body:
                'Check the ${nr ? 'ARFCN' : 'EARFCN'} and PCI. If the modem '
                "can't find this cell, the internet stays down until the "
                'lock is removed.',
            action: 'Lock anyway',
          )) {
        return;
      }
      await _setLock(
        nr: nr,
        pci: pci.text.trim(),
        arfcn: arfcn.text.trim(),
        band: nr ? band.text.trim() : '',
        scs: nr ? scs : '',
      );
    }
    // Not disposed: the sheet still uses the controllers while it closes.
  }
}
