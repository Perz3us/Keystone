// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/firewall_info.dart';
import '../widgets/add_port_forward_dialog.dart';
import '../widgets/advanced_custom_rule_dialog.dart';
import '../widgets/advanced_port_forward_dialog.dart';
import '../widgets/block_incoming_traffic_dialog.dart';

String _plain(String v) => v.replaceAll(RegExp(r'[\[\]]'), '').trim();

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

bool _blocks(String policy) {
  final p = policy.toUpperCase();
  return p == 'REJECT' || p == 'DROP';
}

String zoneName(String zone) => switch (zone.toLowerCase()) {
  'wan' => 'the internet',
  'lan' => 'your home network',
  'guest' => 'guest Wi-Fi',
  '' || '*' => 'anywhere',
  _ => zone,
};

bool isProtected(FirewallOverview o) {
  final wan = o.zones.where((z) => z.name.toLowerCase() == 'wan').firstOrNull;
  return wan == null ? _blocks(o.defaultPolicy.input) : _blocks(wan.input);
}

String forwardLine(FirewallPortForwarding f) {
  final proto = f.proto.isEmpty ? '' : ' (${f.proto.toUpperCase()})';
  final to = f.destPort.isEmpty || f.destPort == f.srcPort
      ? f.destIp
      : '${f.destIp} port ${f.destPort}';
  return 'Port ${f.srcPort}$proto goes to $to';
}

String ruleLine(FirewallCustomRule r) {
  final verb = switch (r.target.toUpperCase()) {
    'ACCEPT' => 'Allows',
    'REJECT' || 'DROP' => 'Blocks',
    _ => r.target,
  };
  final what = r.destPort == null || r.destPort!.isEmpty
      ? 'everything'
      : 'port ${r.destPort}';
  final p = _plain(r.proto);
  final proto = p.isEmpty || p == 'all' ? '' : ' (${p.toUpperCase()})';
  final from = [
    'from ${zoneName(r.srcZone)}',
    if (r.srcIp case final ip? when _plain(ip).isNotEmpty)
      'address ${_plain(ip)}',
    if (r.srcMac.isNotEmpty) r.srcMac.join(', '),
  ].join(' ');
  return '$verb $what$proto $from';
}

String zoneLine(FirewallZone z) {
  String w(String p) => _blocks(p) ? 'blocked' : 'allowed';
  return [
    'Incoming ${w(z.input)}',
    'passing through ${w(z.forward)}',
    if (z.masquerade) 'shares one address',
  ].join(' · ');
}

class FirewallView extends StatelessWidget {
  const FirewallView({
    super.key,
    required this.overview,
    required this.canEdit,
    required this.onOpenPort,
    required this.onBlock,
    required this.onForward,
    required this.onDeleteForward,
    required this.onRule,
    required this.onToggleRule,
    required this.onDeleteRule,
    required this.onMoveRule,
    required this.onNewRule,
    required this.onOffload,
    this.pending = const {},
  });

  final FirewallOverview overview;
  final bool canEdit;
  final VoidCallback onOpenPort;
  final VoidCallback onBlock;
  final ValueChanged<FirewallPortForwarding> onForward;
  final ValueChanged<FirewallPortForwarding> onDeleteForward;
  final ValueChanged<FirewallCustomRule> onRule;
  final void Function(FirewallCustomRule, bool) onToggleRule;
  final ValueChanged<FirewallCustomRule> onDeleteRule;
  final void Function(int index, int delta) onMoveRule;
  final VoidCallback onNewRule;

  final void Function(bool software, bool hardware) onOffload;
  final Set<String> pending;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final o = overview;
    final safe = isProtected(o);
    final rules = o.customRules;
    final d = o.defaultPolicy;

    Widget menu(List<(String, VoidCallback)> items) => PopupMenuButton<int>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert_rounded, color: ks.mu),
      color: ks.sheet,
      onSelected: (i) => items[i].$2(),
      itemBuilder: (_) => [
        for (final (i, (label, _)) in items.indexed)
          PopupMenuItem(
            value: i,
            child: Text(
              label,
              style: KeystoneType.body(label == 'Remove' ? ks.bad : ks.tx),
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            KsDot(safe ? ks.ok : ks.bad, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                safe
                    ? "Protected. Nothing from the internet gets in unless "
                          "you open it."
                    : 'The internet can reach this router directly.',
                style: KeystoneType.bodyStrong(ks.tx),
              ),
            ),
          ],
        ),
        KsSection(
          'Open to the internet',
          trailing: canEdit
              ? TextButton(
                  onPressed: onOpenPort,
                  child: const Text('Open a port'),
                )
              : null,
        ),
        if (o.portForwards.isEmpty)
          Text(
            'Nothing. Open a port only for something like a game server or '
            'camera that must be reached from outside.',
            style: KeystoneType.secondary(ks.mu),
          ),
        for (final f in o.portForwards)
          KsRow(
            title: f.name.isEmpty ? 'Port ${f.srcPort}' : f.name,
            subtitle: [forwardLine(f), if (!f.enabled) 'off'].join(' · '),
            chevron: false,
            onTap: canEdit ? () => onForward(f) : null,
            trailing: canEdit
                ? menu([
                    ('Change', () => onForward(f)),
                    ('Remove', () => onDeleteForward(f)),
                  ])
                : null,
          ),
        KsSection(
          'Rules',
          trailing: canEdit
              ? TextButton(
                  onPressed: onBlock,
                  child: const Text('Block something'),
                )
              : null,
        ),
        if (rules.isEmpty)
          Text(
            'No rules of your own. The defaults below already block the '
            'internet from coming in.',
            style: KeystoneType.secondary(ks.mu),
          ),
        for (final (i, r) in rules.indexed)
          KsRow(
            title: r.name.isEmpty ? 'Rule ${i + 1}' : r.name,
            subtitle: ruleLine(r),
            chevron: false,
            onTap: canEdit ? () => onRule(r) : null,
            trailing: pending.contains(r.sectionKey)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: r.enabled,
                        onChanged: canEdit ? (v) => onToggleRule(r, v) : null,
                      ),
                      if (canEdit)
                        menu([
                          ('Change', () => onRule(r)),
                          if (i > 0) ('Move up', () => onMoveRule(i, -1)),
                          if (i < rules.length - 1)
                            ('Move down', () => onMoveRule(i, 1)),
                          ('Remove', () => onDeleteRule(r)),
                        ]),
                    ],
                  ),
          ),
        if (canEdit)
          KsRow(
            title: 'Write a rule by hand',
            subtitle: 'Any zone, address, port and action',
            leading: Icon(Icons.add_rounded, color: ks.mu),
            onTap: onNewRule,
          ),
        const KsSection('Speed'),
        KsSwitchRow(
          title: 'Fast path (software offloading)',
          subtitle:
              'Less work for the router. Smooth connection only works with '
              'this off.',
          value: d.flowOffloading,
          busy: pending.contains('offload'),
          onChanged: canEdit
              ? (v) => onOffload(v, v && d.flowOffloadingHw)
              : null,
        ),
        if (d.flowOffloading)
          KsSwitchRow(
            title: 'Hardware fast path',
            subtitle: 'Needs a router chip that supports it',
            value: d.flowOffloadingHw,
            busy: pending.contains('offload'),
            onChanged: canEdit ? (v) => onOffload(true, v) : null,
          ),
        const KsSection('Zones'),
        for (final z in o.zones)
          KsRow(
            title: _cap(zoneName(z.name)),
            subtitle: zoneLine(z),
            chevron: false,
          ),
        if (o.forwardings.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            [
              for (final f in o.forwardings)
                _cap(
                  '${zoneName(f.srcZone)} can reach ${zoneName(f.destZone)}',
                ),
            ].join('\n'),
            style: KeystoneType.secondary(ks.mu),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'Flood protection is ${d.synFlood ? 'on' : 'off'}.',
            style: KeystoneType.caption(ks.mu),
          ),
        ),
      ],
    );
  }
}

class FirewallSecurityScreen extends ConsumerStatefulWidget {
  const FirewallSecurityScreen({super.key});

  @override
  ConsumerState<FirewallSecurityScreen> createState() =>
      _FirewallSecurityScreenState();
}

class _FirewallSecurityScreenState
    extends ConsumerState<FirewallSecurityScreen> {
  final _pending = <String>{};

  Future<void> _run(String key, Future<bool> Function() work) async {
    setState(() => _pending.add(key));
    bool ok;
    try {
      ok = await work();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _pending.remove(key));
    if (!ok) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  Future<void> _remove(String what, Future<bool> Function() work) async {
    final ok = await ksConfirm(
      context,
      title: 'Remove $what?',
      body:
          'The firewall reloads; connections through it may drop for a '
          'moment.',
      action: 'Remove',
      danger: true,
    );
    if (ok && mounted) await _run(what, work);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final o = FirewallOverview.fromUciData(
      app.dashboardData?['uciFirewallConfig'],
      backend: app.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: app.reviewerModeEnabled,
    );
    final canEdit = app.capabilities?.canModifyFirewall ?? true;

    return KsPage(
      title: 'Firewall',
      subtitle: 'What may come in from the internet',
      onRefresh: app.refreshFirewallState,
      children: [
        if (!o.isAvailable)
          KsNote(
            "Keystone couldn't read the firewall settings."
            '${o.errorMessage == null ? '' : ' ${o.errorMessage}'}',
            action: 'Try again',
            onAction: app.redetectCapabilities,
          )
        else
          FirewallView(
            overview: o,
            canEdit: canEdit,
            pending: _pending,
            onOpenPort: () => AddPortForwardDialog.show(context),
            onBlock: () => BlockIncomingTrafficDialog.show(context),
            onForward: (f) => AdvancedPortForwardDialog.show(
              context,
              initialPortForward: f,
              overview: o,
            ),
            onDeleteForward: (f) => _remove(
              f.name.isEmpty ? 'port ${f.srcPort}' : f.name,
              () =>
                  app.deleteFirewallPortForward(f.sectionKey, context: context),
            ),
            onRule: (r) => AdvancedCustomRuleDialog.show(
              context,
              initialRule: r,
              overview: o,
            ),
            onNewRule: () =>
                AdvancedCustomRuleDialog.show(context, overview: o),
            onToggleRule: (r, on) => _run(
              r.sectionKey,
              () => app.updateFirewallCustomRuleStatus(
                r.sectionKey,
                on,
                context: context,
              ),
            ),
            onDeleteRule: (r) => _remove(
              r.name.isEmpty ? 'this rule' : r.name,
              () =>
                  app.deleteFirewallCustomRule(r.sectionKey, context: context),
            ),
            onMoveRule: (i, delta) => _run(
              'move',
              () => app.reorderFirewallCustomRules(
                targetSectionKey: o.customRules[i].sectionKey,
                siblingSectionKey: o.customRules[i + delta].sectionKey,
                expectedRuleOrder: [
                  for (final r in o.customRules) r.sectionKey,
                ],
                context: context,
              ),
            ),
            onOffload: (sw, hw) => _run(
              'offload',
              () => app.updateFirewallFlowOffloading(
                software: sw,
                hardware: hw,
                sectionKey: o.defaultPolicy.sectionKey,
                context: context,
              ),
            ),
          ),
        if (!canEdit)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              "This sign-in can't change the firewall.",
              style: KeystoneType.caption(ks.mu),
            ),
          ),
      ],
    );
  }
}
