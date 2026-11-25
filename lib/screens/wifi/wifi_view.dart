import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';

class WifiView extends StatefulWidget {
  const WifiView({
    super.key,
    required this.routerName,
    required this.home,
    required this.bands,
    this.guest,
    this.loading = false,
    this.onRouterMenu,
    this.onSettings,
    required this.onEditName,
    required this.onEditPassword,
    required this.onBand,
    required this.onGuest,
    required this.onSetUpGuest,
    required this.onShare,
    required this.onMoreOptions,
    this.onRefresh,
  });

  final String routerName;
  final WifiNet? home;
  final List<WifiBand> bands;
  final WifiNet? guest;
  final bool loading;
  final VoidCallback? onRouterMenu;
  final VoidCallback? onSettings;
  final VoidCallback onEditName;
  final VoidCallback onEditPassword;
  final void Function(WifiBand band, bool on) onBand;
  final ValueChanged<bool> onGuest;
  final VoidCallback onSetUpGuest;
  final VoidCallback onShare;
  final VoidCallback onMoreOptions;
  final Future<void> Function()? onRefresh;

  @override
  State<WifiView> createState() => _WifiViewState();
}

class _WifiViewState extends State<WifiView> {
  bool _reveal = false;

  Future<void> _confirmOff(String what, int devices, VoidCallback off) async {
    final ks = context.ks;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text('Turn off $what?', style: KeystoneType.sheetTitle(ks.tx)),
        content: Text(
          offWarning(what, devices),
          style: KeystoneType.body(ks.tx2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Keep on', style: KeystoneType.body(ks.tx)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Turn off', style: KeystoneType.body(ks.bad)),
          ),
        ],
      ),
    );
    if (ok == true) off();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final home = widget.home;
    final guest = widget.guest;
    final onWifi = widget.bands.fold<int>(0, (s, b) => s + b.devices);

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onRouterMenu,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.routerName,
                          overflow: TextOverflow.ellipsis,
                          style: KeystoneType.bodyStrong(
                            ks.tx,
                          ).copyWith(fontSize: 18),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, size: 20, color: ks.mu),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.onSettings != null)
              IconButton(
                tooltip: 'Settings',
                onPressed: widget.onSettings,
                icon: Icon(Icons.settings_outlined, color: ks.mu),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Wi-Fi', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Text(
          [
            '$onWifi device${onWifi == 1 ? '' : 's'} on Wi-Fi',
            if (guest != null) '${guest.devices} on guest',
          ].join(' · '),
          style: KeystoneType.secondary(ks.mu),
        ),
        if (home == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              widget.loading
                  ? 'Reading the Wi-Fi settings…'
                  : "This router doesn't have a Wi-Fi network set up.",
              style: KeystoneType.body(ks.mu),
            ),
          )
        else ...[
          _heading(ks, 'Home network'),
          _row(
            ks,
            title: 'Name',
            sub: Text(home.ssid, style: KeystoneType.caption(ks.mu)),
            onTap: widget.onEditName,
          ),
          if (!home.open)
            _row(
              ks,
              title: 'Password',
              sub: Row(
                children: [
                  Flexible(
                    child: Text(
                      _reveal ? (home.key ?? '') : '••••••••••',
                      overflow: TextOverflow.ellipsis,
                      style: KeystoneType.caption(ks.mu),
                    ),
                  ),
                  if (home.key != null)
                    IconButton(
                      tooltip: _reveal ? 'Hide password' : 'Show password',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _reveal = !_reveal),
                      icon: Icon(
                        _reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: ks.mu,
                      ),
                    ),
                ],
              ),
              onTap: widget.onEditPassword,
            ),
          for (final b in widget.bands)
            _switch(
              ks,
              title: b.label,
              line: bandLine(b.label, b.devices),
              value: b.on,
              onChanged: (on) => on
                  ? widget.onBand(b, true)
                  : _confirmOff(
                      b.label,
                      b.devices,
                      () => widget.onBand(b, false),
                    ),
            ),
          if (widget.bands.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Keystone asks first before anything that would disconnect '
                'devices, like turning a band off.',
                style: KeystoneType.secondary(ks.mu),
              ),
            ),
          _heading(ks, 'Guest network'),
          if (guest != null)
            _switch(
              ks,
              title: 'Guest Wi-Fi',
              line: "Visitors get internet but can't see your devices",
              value: guest.enabled,
              onChanged: (on) => on
                  ? widget.onGuest(true)
                  : _confirmOff(
                      'Guest Wi-Fi',
                      guest.devices,
                      () => widget.onGuest(false),
                    ),
            )
          else
            _row(
              ks,
              title: 'Set up guest Wi-Fi',
              sub: Text(
                "Visitors get internet but can't see your devices",
                style: KeystoneType.caption(ks.mu),
              ),
              onTap: widget.onSetUpGuest,
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: widget.onShare,
            style: FilledButton.styleFrom(
              backgroundColor: ks.tx,
              foregroundColor: ks.bg,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.qr_code_rounded, size: 20),
            label: Text('Share Wi-Fi', style: KeystoneType.bodyStrong(ks.bg)),
          ),
        ],
        const SizedBox(height: 8),
        _row(
          ks,
          title: 'More options',
          sub: Text(
            'Every network, channels, who can join',
            style: KeystoneType.caption(ks.mu),
          ),
          onTap: widget.onMoreOptions,
          last: true,
        ),
      ],
    );
    return SafeArea(
      bottom: false,
      child: widget.onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: widget.onRefresh!, child: list),
    );
  }

  Widget _heading(KeystoneColors ks, String text) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 4),
    child: Text(text, style: KeystoneType.secondary(ks.mu)),
  );

  Widget _row(
    KeystoneColors ks, {
    required String title,
    required Widget sub,
    required VoidCallback onTap,
    bool last = false,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KeystoneType.body(ks.tx)),
                sub,
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: ks.mu),
        ],
      ),
    ),
  );

  Widget _switch(
    KeystoneColors ks, {
    required String title,
    required String line,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: ks.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: KeystoneType.body(ks.tx)),
              Text(line, style: KeystoneType.caption(ks.mu)),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged, activeTrackColor: ks.ac),
      ],
    ),
  );
}
