// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/noobwrt/passwall/passwall_module.dart';
import 'package:yet_another_luci_app/screens/network/network_screen.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/vpn_info.dart';

enum VpnKind { wireguard, openvpn, tailscale, nextdns, cloudflared }

class VpnItem {
  const VpnItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.line,
    this.on,
  });
  final VpnKind kind;
  final String id;
  final String title;
  final String line;

  final bool? on;
}

const _openVpnExamples = {'custom_config', 'sample_client', 'sample_server'};

List<VpnItem> vpnItems(VpnConnectivityOverview o) {
  String n(int c, String one) => '$c $one${c == 1 ? '' : 's'}';
  final ts = o.tailscale;
  final dns = o.nextdns;
  final cf = o.cloudflared;
  return [
    for (final w in o.wireguardInterfaces)
      VpnItem(
        kind: VpnKind.wireguard,
        id: w.name,
        title: 'WireGuard · ${w.name}',
        line: [
          w.isUp ? 'On' : 'Off',
          if (w.peers.isNotEmpty) n(w.peers.length, 'peer'),
        ].join(' · '),
      ),
    for (final v in o.openvpnInstances)
      if (v.isEnabled || v.isRunning || !_openVpnExamples.contains(v.name))
        VpnItem(
          kind: VpnKind.openvpn,
          id: v.name,
          title: 'OpenVPN · ${v.name}',
          line: v.isRunning
              ? 'Connected'
              : v.isEnabled
              ? 'On, not connected yet'
              : 'Off',
          on: v.isEnabled || v.isRunning,
        ),
    if (ts.isConfigured)
      VpnItem(
        kind: VpnKind.tailscale,
        id: 'tailscale',
        title: 'Tailscale${ts.nodeName.isEmpty ? '' : ' · ${ts.nodeName}'}',
        line: ts.backendState.toLowerCase() == 'needslogin'
            ? 'Needs signing in. Run "tailscale up" on the router.'
            : ts.isRunning
            ? [
                'Connected',
                if (ts.tailscaleIp.isNotEmpty) ts.tailscaleIp,
                if (ts.peersCount > 0) n(ts.peersCount, 'device'),
              ].join(' · ')
            : 'Off',
        on: ts.isRunning || ts.backendState.toLowerCase() == 'needslogin',
      ),
    if (dns.isConfigured)
      VpnItem(
        kind: VpnKind.nextdns,
        id: 'nextdns',
        title: 'NextDNS',
        line: dns.isRunning
            ? 'Filtering names${dns.profileId.isEmpty ? '' : ' · ${dns.profileId}'}'
            : 'Off',
        on: dns.isEnabled || dns.isRunning,
      ),
    if (cf.isConfigured)
      VpnItem(
        kind: VpnKind.cloudflared,
        id: 'cloudflared',
        title:
            'Cloudflare Tunnel${cf.tunnelName.isEmpty ? '' : ' · ${cf.tunnelName}'}',
        line: cf.isRunning
            ? [
                'Up',
                if (cf.connectionsCount > 0) n(cf.connectionsCount, 'link'),
              ].join(' · ')
            : 'Off',
        on: cf.isEnabled || cf.isRunning,
      ),
  ];
}

class VpnView extends StatelessWidget {
  const VpnView({
    super.key,
    required this.items,
    required this.onToggle,
    required this.onOpen,
    this.pending = const {},
    this.top = const [],
  });

  final List<VpnItem> items;
  final void Function(VpnItem, bool) onToggle;
  final ValueChanged<VpnItem> onOpen;
  final Set<String> pending;

  final List<Widget> top;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...top,
        for (final i in items)
          i.on == null
              ? KsRow(title: i.title, subtitle: i.line, onTap: () => onOpen(i))
              : KsSwitchRow(
                  title: i.title,
                  subtitle: i.line,
                  value: i.on!,
                  busy: pending.contains('${i.kind.name}/${i.id}'),
                  onChanged: (v) => onToggle(i, v),
                ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'No other VPN is set up on this router. WireGuard, OpenVPN, '
              'Tailscale, NextDNS and Cloudflare Tunnel show up here once '
              'they are installed and set up.',
              style: KeystoneType.body(ks.mu),
            ),
          ),
      ],
    );
  }
}

class VpnConnectivityScreen extends ConsumerStatefulWidget {
  const VpnConnectivityScreen({super.key});

  @override
  ConsumerState<VpnConnectivityScreen> createState() =>
      _VpnConnectivityScreenState();
}

class _VpnConnectivityScreenState extends ConsumerState<VpnConnectivityScreen> {
  final _pending = <String>{};

  Future<void> _toggle(VpnItem i, bool on) async {
    final app = ref.read(appStateProvider);
    if (!on) {
      final ok = await ksConfirm(
        context,
        title: 'Turn off ${i.title}?',
        body: i.kind == VpnKind.nextdns
            ? 'Names go back to the normal lookup service, unfiltered.'
            : 'Anything that goes through it stops until you turn it back on.',
        action: 'Turn off',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final key = '${i.kind.name}/${i.id}';
    setState(() => _pending.add(key));
    bool good;
    try {
      good = await switch (i.kind) {
        VpnKind.openvpn => app.toggleOpenVpnInstance(i.id, on),
        VpnKind.tailscale => app.toggleTailscale(on),
        VpnKind.nextdns => app.toggleNextDns(on),
        VpnKind.cloudflared => app.toggleCloudflared(on),
        VpnKind.wireguard => app.toggleWireguardInterface(i.id, on),
      };
    } catch (_) {
      good = false;
    }
    if (good) await app.fetchDashboardData(force: true);
    if (!mounted) return;
    setState(() => _pending.remove(key));
    if (!good) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final o = VpnConnectivityOverview.fromDashboardData(
      app.dashboardData,
      isReviewerMode: app.reviewerModeEnabled,
    );
    return KsPage(
      title: 'VPN',
      subtitle: 'Tunnels and private name lookups on this router',
      onRefresh: () => app.fetchDashboardData(force: true),
      children: [
        VpnView(
          items: vpnItems(o),
          pending: _pending,
          top: [for (final k in PasswallKind.all) PasswallVpnCard(kind: k)],
          onToggle: _toggle,
          onOpen: (i) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ConnectionScreen(name: i.id),
            ),
          ),
        ),
      ],
    );
  }
}
