import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/guest_wifi_management_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wifi_access_control_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/add_ssid_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/edit_radio_dialog.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/edit_ssid_dialog.dart';
import 'package:yet_another_luci_app/screens/wifi/share_wifi_sheet.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_settings_view.dart';

String securityWord(WifiSecurityMode m) => switch (m) {
  WifiSecurityMode.saeOnly => 'WPA3',
  WifiSecurityMode.saeMixed => 'WPA2/WPA3',
  WifiSecurityMode.wpa2Psk => 'WPA2',
  WifiSecurityMode.wpaPsk => 'WPA (old)',
  WifiSecurityMode.owe => 'Enhanced Open',
  WifiSecurityMode.wep => 'WEP (unsafe)',
  WifiSecurityMode.open => 'No password',
  WifiSecurityMode.enterprise => 'Enterprise',
  WifiSecurityMode.unknown => 'Secured',
};

String radioLine(WirelessRadio r) => [
  r.channel.isEmpty || r.channel == 'auto'
      ? 'Channel auto'
      : 'Channel ${r.channel}',
  if ((r.htMode ?? '').isNotEmpty) r.htMode!,
  if (r.txPowerDbm != null) '${r.txPowerDbm} dBm',
  if (r.country.isNotEmpty) r.country,
].join(' · ');

class WifiSettingsScreen extends ConsumerStatefulWidget {
  const WifiSettingsScreen({super.key});

  @override
  ConsumerState<WifiSettingsScreen> createState() => _WifiSettingsScreenState();
}

class _WifiSettingsScreenState extends ConsumerState<WifiSettingsScreen> {
  final _pending = <String>{};

  WirelessOverview _overview() {
    final app = ref.read(appStateProvider);
    return WirelessOverview.fromDashboardData(
      app.dashboardData,
      isReviewerMode: app.reviewerModeEnabled,
    );
  }

  (WirelessRadio, WirelessInterface)? _find(String section) {
    for (final r in _overview().radios) {
      for (final i in r.interfaces) {
        if (i.sectionName == section) return (r, i);
      }
    }
    return null;
  }

  Future<bool?> _confirm(String title, String body, String yes) {
    final ks = context.ks;
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text(title, style: KeystoneType.sheetTitle(ks.tx)),
        content: Text(body, style: KeystoneType.body(ks.tx2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes, style: TextStyle(color: ks.bad)),
          ),
        ],
      ),
    );
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggle(String id, bool on) async {
    final hit = _find(id);
    if (hit == null) return;
    final (_, i) = hit;
    if (!on) {
      final ok = await _confirm(
        'Turn off ${i.ssid}?',
        i.stations.isEmpty
            ? 'Nothing is using it right now.'
            : '${i.stations.length} device${i.stations.length == 1 ? '' : 's'} '
                  'will lose Wi-Fi, maybe this phone too.',
        'Turn off',
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _pending.add(id));
    final app = ref.read(appStateProvider);
    final good = await app.setSsidEnabled(id, on, context: context);
    if (!mounted) return;
    setState(() => _pending.remove(id));
    if (!good) _say("The router didn't take that. Nothing was changed.");
  }

  Future<void> _action(String id, WifiNetworkAction a) async {
    final hit = _find(id);
    if (hit == null) return;
    final (_, i) = hit;
    switch (a) {
      case WifiNetworkAction.share:
        await shareNetwork(context, ref, i);
      case WifiNetworkAction.remove:
        final ok = await _confirm(
          'Remove ${i.ssid}?',
          'Devices on it lose Wi-Fi. The router forgets its name and '
              'password.',
          'Remove',
        );
        if (ok != true || !mounted) return;
        final good = await ref
            .read(appStateProvider)
            .deleteWirelessInterface(sectionName: id);
        if (mounted && !good) {
          _say("The router didn't remove it. Nothing was changed.");
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final overview = _overview();
    final canEdit =
        (app.capabilities?.hasUciWriteAccess ?? true) &&
        app.isAdministrativeUser;
    const ap = {'ap', 'master'};

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Wi-Fi', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => app.fetchDashboardData(force: true),
          child: WifiSettingsView(
            canEdit: canEdit,
            pending: _pending,
            networks: [
              for (final r in overview.radios)
                for (final i in r.interfaces)
                  if (ap.contains(i.mode.toLowerCase()))
                    WifiNetworkRow(
                      id: i.sectionName,
                      name: i.ssid.isEmpty ? '(no name)' : i.ssid,
                      band: r.bandLabel,
                      security: securityWord(i.securityMode),
                      devices: i.stations.length,
                      enabled: i.isEnabled && !r.isDisabled,
                      hidden: i.isHidden,
                      guest: i.isGuest,
                    ),
            ],
            radios: [
              for (final r in overview.radios)
                WifiRadioRow(
                  id: r.name,
                  band: r.bandLabel,
                  line: radioLine(r),
                  enabled: !r.isDisabled,
                ),
            ],
            onNetwork: (id) {
              final hit = _find(id);
              if (hit == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) =>
                      EditSsidDialog(radio: hit.$1, interface: hit.$2),
                ),
              );
            },
            onToggleNetwork: _toggle,
            onNetworkAction: _action,
            onAddNetwork: () {
              if (overview.radios.isEmpty) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => AddSsidDialog(
                    radios: overview.radios,
                    targetRadio: overview.radios.first,
                  ),
                ),
              );
            },
            onRadio: (id) {
              final r = overview.radios.where((r) => r.name == id).firstOrNull;
              if (r == null) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => EditRadioDialog(radio: r),
                ),
              );
            },
            onAccessControl: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const WifiAccessControlScreen(),
              ),
            ),
            onGuest: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const GuestWifiManagementScreen(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> shareNetwork(
  BuildContext context,
  WidgetRef ref,
  WirelessInterface i,
) async {
  var key = i.key;
  if ((key ?? '').isEmpty) {
    try {
      final v = await ref
          .read(appStateProvider)
          .fetchWirelessSectionConfig(i.sectionName);
      key = v?['key']?.toString() ?? v?['sae_password']?.toString();
    } catch (_) {}
  }
  if (!context.mounted) return;
  await showShareWifi(
    context,
    home: WifiNet(
      ssid: i.ssid,
      key: (key ?? '').isEmpty ? null : key,
      security: switch (i.securityMode) {
        WifiSecurityMode.open => 'nopass',
        WifiSecurityMode.saeOnly => 'SAE',
        WifiSecurityMode.wep => 'WEP',
        _ => 'WPA',
      },
      hidden: i.isHidden,
    ),
  );
}
