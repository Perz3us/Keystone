// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

import '../history/helper_installer.dart';
import '../noob_rpc.dart';
import '../noob_widgets.dart';

typedef GuardCall =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

@immutable
class GuardEvent {
  const GuardEvent(this.time, this.reason, this.pci);
  final int time;
  final String reason, pci;

  static GuardEvent? parse(Object? j) {
    if (j is! Map || j['time'] is! int) return null;
    return GuardEvent(j['time'] as int, '${j['reason']}', '${j['pci']}');
  }

  String get text {
    final why = switch (reason) {
      'no_service' => "The modem couldn't connect to PCI $pci",
      'unstable' => 'PCI $pci kept dropping',
      'slow' => 'PCI $pci was much slower than the cell before it',
      'weak' => 'PCI $pci had a much weaker signal than the cell before it',
      'lost' => 'The internet was down for 5 minutes on PCI $pci',
      _ => 'PCI $pci stopped working',
    };
    return '$why, so Cell guard removed the lock (${noobAgo(time)}).';
  }
}

@immutable
class GuardState {
  const GuardState({this.phase, this.last});
  final String? phase;
  final GuardEvent? last;

  static GuardState parse(Map<String, dynamic> j) => GuardState(
    phase: j['lock'] is Map ? '${(j['lock'] as Map)['phase']}' : null,
    last: GuardEvent.parse(j['last']),
  );

  String? get line => switch (phase) {
    'trial' => 'Checking the new cell',
    'watch' => 'Watching the lock',
    'removing' => 'Removing the lock',
    _ => null,
  };
}

class CellGuard {
  CellGuard(AppState app, {GuardCall? call})
    : _app = app,
      _call = call ?? ((m, p) => noobCall(app, 'keystone.cellguard', m, p));
  final AppState _app;
  final GuardCall _call;

  static const package = 'keystone-cellguard';

  HelperInstaller get helper => HelperInstaller(_app, package: package);

  Future<GuardState?> info() async {
    try {
      return GuardState.parse(await _call('info', {}));
    } on NoobRpcError catch (e) {
      if (e.message == 'Not found' || e.message == 'Method not found') {
        return null;
      }
      rethrow;
    }
  }

  Future<GuardState> _do(String method, [Map<String, dynamic>? p]) async {
    final r = await _call(method, p ?? {});
    if (r['error'] != null) throw NoobRpcError('${r['error']}');
    return GuardState.parse(r);
  }

  Future<GuardState> arm({
    required bool nr,
    required String pci,
    required String arfcn,
  }) => _do('arm', {'pci': pci, 'arfcn': arfcn, 'nr': nr});

  Future<GuardState> disarm() => _do('disarm');

  Future<GuardState> ack() => _do('ack');
}
