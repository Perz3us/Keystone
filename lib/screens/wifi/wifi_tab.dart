import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/guest_wifi_management_screen.dart';
import 'package:yet_another_luci_app/modules/wireless_management/widgets/edit_ssid_dialog.dart';
import 'package:yet_another_luci_app/screens/routers/routers_sheet.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/screens/wifi/share_wifi_sheet.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_settings_screen.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_view.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class WifiSetup {
  WifiSetup(this.overview);

  final WirelessOverview overview;

  static bool _ap(WirelessInterface i) =>
      const {'ap', 'master'}.contains(i.mode.toLowerCase());

  Iterable<(WirelessRadio, WirelessInterface)> get _aps => [
    for (final r in overview.radios)
      for (final i in r.interfaces)
        if (_ap(i)) (r, i),
  ];

  (WirelessRadio, WirelessInterface)? get homeAp {
    final home = _aps.where((e) => !e.$2.isGuest).toList()
      ..sort((a, b) => (b.$2.isEnabled ? 1 : 0) - (a.$2.isEnabled ? 1 : 0));
    return home.firstOrNull;
  }

  WirelessInterface? get guestAp =>
      _aps.where((e) => e.$2.isGuest).firstOrNull?.$2;

  static String _security(WirelessInterface i) => switch (i.securityMode) {
    WifiSecurityMode.open => 'nopass',
    WifiSecurityMode.saeOnly => 'SAE',
    WifiSecurityMode.wep => 'WEP',
    _ => 'WPA',
  };

  WifiNet? get home {
    final ap = homeAp?.$2;
    if (ap == null) return null;
    return WifiNet(
      ssid: ap.ssid,
      key: (ap.key ?? '').isEmpty ? null : ap.key,
      security: _security(ap),
      hidden: ap.isHidden,
      enabled: ap.isEnabled,
      devices: bands.fold(0, (s, b) => s + b.devices),
      section: ap.sectionName,
    );
  }

  WifiNet? get guest {
    final g = guestAp;
    if (g == null) return null;
    return WifiNet(
      ssid: g.ssid,
      key: (g.key ?? '').isEmpty ? null : g.key,
      security: _security(g),
      hidden: g.isHidden,
      enabled: g.isEnabled,
      devices: _aps
          .where((e) => e.$2.isGuest)
          .fold(0, (s, e) => s + e.$2.stations.length),
      section: g.sectionName,
    );
  }

  List<WifiBand> get bands => [
    for (final r in overview.radios)
      if (r.interfaces.any((i) => _ap(i) && !i.isGuest))
        WifiBand(
          radio: r.name,
          label: r.bandLabel,
          on: !r.isDisabled,
          devices: r.interfaces
              .where((i) => _ap(i) && !i.isGuest)
              .fold(0, (s, i) => s + i.stations.length),
        ),
  ];
}

WifiSetup _setup(AppState app) => WifiSetup(
  WirelessOverview.fromDashboardData(
    app.dashboardData,
    isReviewerMode: app.reviewerModeEnabled,
  ),
);

Future<WifiNet?> _withKey(AppState app, WifiNet? n) async {
  if (n == null || n.open || n.key != null || n.section == null) return n;
  try {
    final v = await app.fetchWirelessSectionConfig(n.section!);
    final key = v?['key']?.toString() ?? v?['sae_password']?.toString();
    if (key == null || key.isEmpty) return n;
    return WifiNet(
      ssid: n.ssid,
      key: key,
      security: n.security,
      hidden: n.hidden,
      enabled: n.enabled,
      devices: n.devices,
      section: n.section,
    );
  } catch (_) {
    return n;
  }
}

Future<void> shareWifi(BuildContext context, AppState app) async {
  final s = _setup(app);
  final home = await _withKey(app, s.home);
  final guest = await _withKey(app, s.guest);
  if (home == null || !context.mounted) return;
  await showShareWifi(context, home: home, guest: guest);
}

class WifiTab extends ConsumerWidget {
  const WifiTab({super.key, this.isTabActive = true});

  final bool isTabActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final s = _setup(app);
    final homeAp = s.homeAp;
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    void edit() {
      if (homeAp == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              EditSsidDialog(radio: homeAp.$1, interface: homeAp.$2),
        ),
      );
    }

    return WifiView(
      routerName: routerDisplayName(app.selectedRouter),
      home: s.home,
      bands: s.bands,
      guest: s.guest,
      loading: app.isDashboardLoading || app.dashboardData == null,
      onRouterMenu: () => showRoutersSheet(context),
      onSettings: () => app.requestTab(4),
      onEditName: edit,
      onEditPassword: edit,
      onBand: (b, on) => app.toggleWirelessRadio(b.radio, on, context: context),
      onGuest: (on) {
        final section = s.guest?.section;
        if (section != null) {
          app.updateWirelessInterfaceStatus(section, on, context: context);
        }
      },
      onSetUpGuest: () => open(const GuestWifiManagementScreen()),
      onShare: () => shareWifi(context, app),
      onMoreOptions: () => open(const WifiSettingsScreen()),
      onRefresh: () => app.fetchDashboardData(force: true),
    );
  }
}
