// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/state/app_state.dart';

import '../history/helper_history.dart';
import '../history/history_data.dart';
import '../noob_rpc.dart';
import 'data_plan.dart';

bool keystoneMissing(Object e) =>
    historyMissing(e, denied: true) ||
    (e is NoobRpcError && e.message == NoobRpcError.refused.message);

class DataPlanClient {
  DataPlanClient(this._call);
  DataPlanClient.of(AppState app)
    : this((m, p) => noobCall(app, 'keystone.history', m, p));

  final HelperCall _call;

  Future<DataPlans?> load() async {
    final Map<String, dynamic> r;
    try {
      r = await _call('info', {});
    } catch (e) {
      if (keystoneMissing(e)) return null;
      rethrow;
    }
    final rows = r['plans'], sim = r['active_sim'];
    if (rows is! List || sim is! String) return null;
    return DataPlans(
      activeSim: sim,
      plans: rows.map(SimPlan.from).nonNulls.toList(),
    );
  }

  Future<SimPlan> save({
    required String sim,
    required PlanKind kind,
    int? allowanceGb,
    required int billingDay,
  }) async {
    final r = await _call('set_plan', {
      'sim': sim,
      'plan': kind.name,
      if (kind == PlanKind.capped || kind == PlanKind.fairuse)
        'allowance_gb': allowanceGb,
      'billing_day': billingDay,
    });
    if (r['error'] != null) throw NoobRpcError('${r['error']}');
    return SimPlan.from(r) ??
        (throw const NoobRpcError("The router's reply made no sense"));
  }
}
