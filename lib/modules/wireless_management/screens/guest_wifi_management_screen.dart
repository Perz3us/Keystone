// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';
import 'package:yet_another_luci_app/screens/devices/device_screen.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_settings_screen.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../models/wireless_info.dart';
import '../widgets/edit_ssid_dialog.dart';
import '../widgets/provision_guest_network_dialog.dart';
import '../widgets/wireless_rollback_banner.dart';

class GuestNet {
  const GuestNet({
    required this.id,
    required this.name,
    required this.line,
    required this.enabled,
  });
  final String id;
  final String name;

  final String line;
  final bool enabled;
}

class GuestOnline {
  const GuestOnline({
    required this.mac,
    required this.name,
    required this.line,
    required this.paused,
  });
  final String mac;
  final String name;
  final String line;
  final bool paused;
}

class GuestWifiView extends StatelessWidget {
  const GuestWifiView({
    super.key,
    required this.networks,
    required this.guests,
    required this.canEdit,
    required this.onToggle,
    required this.onEdit,
    required this.onShare,
    required this.onSetUp,
    required this.onGuest,
    required this.onPause,
    this.pending = const {},
  });

  final List<GuestNet> networks;
  final List<GuestOnline> guests;
  final bool canEdit;
  final void Function(String id, bool on) onToggle;
  final ValueChanged<String> onEdit;
  final VoidCallback onShare;
  final VoidCallback onSetUp;
  final ValueChanged<String> onGuest;
  final void Function(String mac, bool pause) onPause;

  final Set<String> pending;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    if (networks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "There's no guest network yet. Visitors would get their own "
            "Wi-Fi name and password, and couldn't see your devices.",
            style: KeystoneType.body(ks.tx2),
          ),
          const SizedBox(height: 20),
          if (canEdit)
            FilledButton(
              onPressed: onSetUp,
              child: const Text('Set up guest Wi-Fi'),
            )
          else
            const KsBanner(
              "This sign-in can't change Wi-Fi. Sign in as root to set it up.",
            ),
        ],
      );
    }
    final anyOn = networks.any((n) => n.enabled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KsSection('Guest networks'),
        for (final n in networks)
          KsRow(
            title: n.name,
            subtitle: n.line,
            chevron: false,
            onTap: canEdit ? () => onEdit(n.id) : null,
            trailing: pending.contains(n.id)
                ? const SizedBox(
                    width: 48,
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : Switch(
                    value: n.enabled,
                    onChanged: canEdit ? (v) => onToggle(n.id, v) : null,
                  ),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: anyOn ? onShare : null,
          icon: const Icon(Icons.qr_code_2_rounded),
          label: const Text('Share guest Wi-Fi'),
        ),
        if (!anyOn)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Turn a guest network on to share it.',
              textAlign: TextAlign.center,
              style: KeystoneType.caption(ks.mu),
            ),
          ),
        KsSection(
          'Guests online${guests.isEmpty ? '' : ' · ${guests.length}'}',
        ),
        if (guests.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nobody is on guest Wi-Fi right now.',
              style: KeystoneType.body(ks.mu),
            ),
          )
        else
          for (final g in guests)
            KsRow(
              title: g.name,
              subtitle: g.paused ? 'Paused · ${g.line}' : g.line,
              onTap: () => onGuest(g.mac),
              chevron: false,
              trailing: pending.contains(g.mac)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: canEdit
                          ? () => onPause(g.mac, !g.paused)
                          : null,
                      child: Text(g.paused ? 'Resume' : 'Pause'),
                    ),
            ),
        if (canEdit)
          KsRow(
            title: 'Add another guest network',
            subtitle: 'For example one on each band',
            leading: Icon(Icons.add_rounded, color: ks.mu),
            onTap: onSetUp,
          ),
        const SizedBox(height: 16),
        Text(
          "Guests get the internet only. They can't reach your devices, "
          "this router's settings, or each other.",
          style: KeystoneType.caption(ks.mu),
        ),
      ],
    );
  }
}

class GuestWifiManagementScreen extends ConsumerStatefulWidget {
  const GuestWifiManagementScreen({super.key});

  @override
  ConsumerState<GuestWifiManagementScreen> createState() =>
      _GuestWifiManagementScreenState();
}

class _GuestWifiManagementScreenState
    extends ConsumerState<GuestWifiManagementScreen> {
  final _pending = <String>{};

  Future<void> _busy(String key, Future<bool> Function() work) async {
    setState(() => _pending.add(key));
    final ok = await work();
    if (!mounted) return;
    setState(() => _pending.remove(key));
    if (!ok) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  void _page(Widget page) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final overview = WirelessOverview.fromDashboardData(
      app.dashboardData,
      isReviewerMode: app.reviewerModeEnabled,
    );
    final canEdit =
        (app.capabilities?.hasUciWriteAccess ?? true) &&
        app.isAdministrativeUser;
    final found = [
      for (final r in overview.radios)
        for (final i in r.interfaces)
          if (i.isGuestInterface(
            app.customGuestSections,
            app.excludedGuestSections,
          ))
            (r, i),
    ];
    final paused = app.pausedInternetMacs
        .map(ClientNamingHelper.normalizeMac)
        .toSet();

    final networks = [
      for (final (r, i) in found)
        GuestNet(
          id: i.sectionName,
          name: i.ssid.isEmpty ? '(no name)' : i.ssid,
          line: [
            r.bandLabel,
            i.securityMode == WifiSecurityMode.open
                ? 'no password'
                : 'password',
            switch (i.stations.length) {
              0 => 'no guests',
              1 => '1 guest',
              final n => '$n guests',
            },
          ].join(' · '),
          enabled: i.isEnabled && !r.isDisabled,
        ),
    ];
    final guests = [
      for (final (_, i) in found)
        for (final st in i.stations)
          () {
            final mac = ClientNamingHelper.normalizeMac(st.macAddress);
            final c = app.findClientByMac(st.macAddress);
            return GuestOnline(
              mac: mac,
              name: c?.displayName ?? st.macAddress,
              line: [i.ssid, ?signalWord(st.signalDbm)].join(' · '),
              paused: paused.contains(mac),
            );
          }(),
    ];

    return PopScope(
      canPop: !app.isAccessControlPendingConfirmation,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canExit = await LuciGuardrail.confirmStagedChangesOrExit(
          context,
          app,
        );
        if (canExit && context.mounted) Navigator.pop(context);
      },
      child: KsPage(
        title: 'Guest Wi-Fi',
        subtitle: "Visitors get internet but can't see your devices",
        onRefresh: () => app.fetchDashboardData(force: true),
        children: [
          const WirelessRollbackBanner(),
          GuestWifiView(
            networks: networks,
            guests: guests,
            canEdit: canEdit,
            pending: _pending,
            onToggle: (id, on) async {
              final hit = found.where((f) => f.$2.sectionName == id).first;
              if (!on && hit.$2.stations.isNotEmpty) {
                final n = hit.$2.stations.length;
                final ok = await ksConfirm(
                  context,
                  title: 'Turn off ${hit.$2.ssid}?',
                  body: '$n guest${n == 1 ? '' : 's'} will lose Wi-Fi.',
                  action: 'Turn off',
                  danger: true,
                );
                if (!ok || !mounted) return;
              }
              await _busy(
                id,
                () => app.setSsidEnabled(id, on, context: context),
              );
            },
            onEdit: (id) {
              final hit = found.where((f) => f.$2.sectionName == id).first;
              _page(EditSsidDialog(radio: hit.$1, interface: hit.$2));
            },
            onShare: () {
              final on = found.where((f) => f.$2.isEnabled).firstOrNull;
              if (on != null) shareNetwork(context, ref, on.$2);
            },
            onSetUp: () =>
                _page(ProvisionGuestNetworkDialog(radios: overview.radios)),
            onGuest: (mac) => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => DeviceScreen(mac: mac)),
            ),
            onPause: (mac, pause) => _busy(
              mac,
              () =>
                  app.pauseClientInternet(mac, pause: pause, context: context),
            ),
          ),
        ],
      ),
    );
  }
}
