import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class WifiNetworkRow {
  const WifiNetworkRow({
    required this.id,
    required this.name,
    required this.band,
    required this.security,
    required this.devices,
    required this.enabled,
    this.hidden = false,
    this.guest = false,
  });
  final String id;
  final String name;
  final String band;
  final String security;
  final int devices;
  final bool enabled;
  final bool hidden;
  final bool guest;
}

class WifiRadioRow {
  const WifiRadioRow({
    required this.id,
    required this.band,
    required this.line,
    required this.enabled,
  });
  final String id;
  final String band;

  final String line;
  final bool enabled;
}

enum WifiNetworkAction { share, remove }

class WifiSettingsView extends StatelessWidget {
  const WifiSettingsView({
    super.key,
    required this.networks,
    required this.radios,
    required this.onNetwork,
    required this.onToggleNetwork,
    required this.onNetworkAction,
    required this.onAddNetwork,
    required this.onRadio,
    this.onAccessControl,
    this.onGuest,
    this.pending = const {},
    this.canEdit = true,
  });

  final List<WifiNetworkRow> networks;
  final List<WifiRadioRow> radios;
  final ValueChanged<String> onNetwork;
  final void Function(String id, bool on) onToggleNetwork;
  final void Function(String id, WifiNetworkAction action) onNetworkAction;
  final VoidCallback onAddNetwork;
  final ValueChanged<String> onRadio;
  final VoidCallback? onAccessControl;
  final VoidCallback? onGuest;

  final Set<String> pending;

  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text('Wi-Fi settings', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'Each network, the radios behind them, and who may join.',
          style: KeystoneType.secondary(ks.mu),
        ),
        if (!canEdit) ...[
          const SizedBox(height: 12),
          Text(
            'This sign-in can only look. Sign in as root to change things.',
            style: KeystoneType.secondary(ks.warnTx),
          ),
        ],
        _heading(ks, 'Networks'),
        for (final n in networks) _network(ks, n),
        if (canEdit)
          _link(
            ks,
            Icons.add_rounded,
            'Add a network',
            'Another name, for example for smart-home devices',
            onAddNetwork,
          ),
        _heading(ks, 'Radios'),
        for (final r in radios)
          _link(
            ks,
            Icons.settings_input_antenna_rounded,
            r.band,
            r.enabled ? r.line : 'Off',
            canEdit ? () => onRadio(r.id) : null,
          ),
        if (onAccessControl != null || onGuest != null)
          _heading(ks, 'Who can join'),
        if (onAccessControl != null)
          _link(
            ks,
            Icons.block_rounded,
            'Allow or block devices',
            'A list of devices that may, or may not, join',
            onAccessControl,
          ),
        if (onGuest != null)
          _link(
            ks,
            Icons.badge_outlined,
            'Guest network settings',
            'Its name, password, and what guests can reach',
            onGuest,
          ),
      ],
    );
  }

  Widget _heading(KeystoneColors ks, String t) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 4),
    child: Text(t, style: KeystoneType.secondary(ks.mu)),
  );

  Widget _network(KeystoneColors ks, WifiNetworkRow n) {
    final line = [
      n.band,
      n.security,
      if (n.hidden) 'hidden',
      if (n.guest) 'guest',
      n.devices == 0
          ? 'no devices'
          : '${n.devices} device${n.devices == 1 ? '' : 's'}',
    ].join(' · ');
    return InkWell(
      onTap: canEdit ? () => onNetwork(n.id) : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ks.line)),
        ),
        child: Row(
          children: [
            Icon(
              n.enabled ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: n.enabled ? ks.tx2 : ks.mu,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.name,
                    style: KeystoneType.body(n.enabled ? ks.tx : ks.mu),
                  ),
                  Text(line, style: KeystoneType.caption(ks.mu)),
                ],
              ),
            ),
            if (pending.contains(n.id))
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Switch(
                value: n.enabled,
                onChanged: canEdit ? (v) => onToggleNetwork(n.id, v) : null,
              ),
            PopupMenuButton<WifiNetworkAction>(
              tooltip: 'Options for ${n.name}',
              icon: Icon(Icons.more_vert_rounded, color: ks.mu),
              color: ks.sheet,
              onSelected: (a) => onNetworkAction(n.id, a),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: WifiNetworkAction.share,
                  child: Text('Share', style: KeystoneType.body(ks.tx)),
                ),
                if (canEdit)
                  PopupMenuItem(
                    value: WifiNetworkAction.remove,
                    child: Text('Remove', style: KeystoneType.body(ks.bad)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _link(
    KeystoneColors ks,
    IconData icon,
    String title,
    String sub,
    VoidCallback? onTap,
  ) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: ks.tx2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KeystoneType.body(ks.tx)),
                Text(sub, style: KeystoneType.caption(ks.mu)),
              ],
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right_rounded, color: ks.mu),
        ],
      ),
    ),
  );
}
