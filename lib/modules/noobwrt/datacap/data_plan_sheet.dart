// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_rpc.dart';
import 'data_plan.dart';
import 'data_plan_client.dart';

Future<SimPlan?> showDataPlanSheet(
  BuildContext context,
  DataPlanClient client, {
  required String sim,
  SimPlan? plan,
}) => ksSheet<SimPlan>(
  context,
  (_) => DataPlanForm(client: client, sim: sim, plan: plan),
);

class DataPlanForm extends StatefulWidget {
  const DataPlanForm({
    super.key,
    required this.client,
    required this.sim,
    this.plan,
  });

  final DataPlanClient client;
  final String sim;
  final SimPlan? plan;

  @override
  State<DataPlanForm> createState() => _DataPlanFormState();
}

class _DataPlanFormState extends State<DataPlanForm> {
  final _form = GlobalKey<FormState>();
  late final _gb = TextEditingController(
    text: widget.plan?.allowanceGb?.toString() ?? '',
  );
  late PlanKind _kind = switch (widget.plan?.kind) {
    null || PlanKind.none => PlanKind.unlimited,
    final k => k,
  };
  late int _day = widget.plan?.billingDay ?? 1;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _gb.dispose();
    super.dispose();
  }

  String? _checkGb(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your allowance';
    final n = int.tryParse(t);
    return n == null || n < 1 || n > 100000 ? 'Whole GB, 1 to 100000' : null;
  }

  Future<void> _save(PlanKind kind) async {
    if (kind != PlanKind.none && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.client.save(
        sim: widget.sim,
        kind: kind,
        allowanceGb: int.tryParse(_gb.text.trim()),
        billingDay: _day,
      );
      if (mounted) await Navigator.of(context).maybePop(saved);
    } catch (e) {
      _error = e is NoobRpcError
          ? "The router couldn't save that: ${e.message}"
          : "Couldn't reach the router. Check you're on its Wi-Fi, then try "
                'again.';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final limited = _kind == PlanKind.capped || _kind == PlanKind.fairuse;
    final set = widget.plan != null && widget.plan!.kind != PlanKind.none;
    return Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Data plan', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 4),
          Text(
            'For the SIM in use now. Saved on the router.',
            style: KeystoneType.secondary(ks.mu),
          ),
          KsSegmented<PlanKind>(
            label: 'Plan',
            value: _kind,
            options: const [
              (PlanKind.unlimited, 'Unlimited'),
              (PlanKind.capped, 'Capped'),
              (PlanKind.fairuse, 'Fair use'),
            ],
            onChanged: (k) => setState(() => _kind = k),
          ),
          if (limited)
            KsField(
              label: _kind == PlanKind.capped
                  ? 'Allowance in GB'
                  : 'Slows down after, in GB',
              controller: _gb,
              keyboardType: TextInputType.number,
              validator: _checkGb,
            ),
          KsChoice<int>(
            label: 'Billing day',
            value: _day,
            options: [for (var d = 1; d <= 31; d++) (d, '$d')],
            onChanged: (d) => setState(() => _day = d),
            help: _day >= 29 ? 'Shorter months use their last day' : null,
          ),
          if (_error != null) KsBanner(_error!, bad: true),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _save(_kind),
            child: const Text('Save'),
          ),
          if (set)
            TextButton(
              onPressed: _busy ? null : () => _save(PlanKind.none),
              child: Text('Remove plan', style: KeystoneType.body(ks.bad)),
            ),
        ],
      ),
    );
  }
}
