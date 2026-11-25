import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/bandix/bandix_rates.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/devices/all_devices.dart';
import 'package:yet_another_luci_app/screens/devices/device_screen.dart';
import 'package:yet_another_luci_app/screens/devices/devices_view.dart';
import 'package:yet_another_luci_app/screens/routers/routers_sheet.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/services/device_discovery.dart';

List<Client> withBandix(List<Client> clients, Map<String, BandixRate>? rates) {
  if (rates == null || rates.isEmpty) return clients;
  return [
    for (final c in clients)
      if (rates[c.macAddress.toLowerCase()] case final r?)
        c.copyWith(
          rxSpeed: r.down.toDouble(),
          txSpeed: r.up.toDouble(),
          rxBytes: r.usedDown.toInt(),
          txBytes: r.usedUp.toInt(),
        )
      else
        c,
  ];
}

class DevicesTab extends ConsumerWidget {
  const DevicesTab({super.key, this.isTabActive = true});

  final bool isTabActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final rates = isTabActive
        ? ref.watch(bandixRatesProvider).valueOrNull
        : null;
    final online = withBandix(
      app.clients.where((c) => c.isConnected).toList(),
      rates,
    );
    void open(Widget s) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

    return DevicesView(
      routerName: routerDisplayName(app.selectedRouter),
      clients: online,
      pausedMacs: app.pausedInternetMacs,
      loading: app.isClientsLoading || !app.hasFetchedClients,
      onRouterMenu: () => showRoutersSheet(context),
      onOpen: (c) => open(DeviceScreen(mac: c.macAddress)),
      onResume: (c) =>
          app.pauseClientInternet(c.macAddress, pause: false, context: context),
      onAllDetails: () => open(const AllDevicesScreen()),
      onRefresh: () => app.fetchClientsForSelectedRouter(),
    );
  }
}

class AllDevicesScreen extends ConsumerStatefulWidget {
  const AllDevicesScreen({super.key, this.byData = false});

  final bool byData;

  @override
  ConsumerState<AllDevicesScreen> createState() => _AllDevicesState();
}

class _AllDevicesState extends ConsumerState<AllDevicesScreen> {
  List<Client>? _aggregated;

  Map<String, int>? _month;

  @override
  void initState() {
    super.initState();
    _load();
    DeviceDiscovery.instance.maybeScan();
  }

  Future<void> _load() async {
    final app = ref.read(appStateProvider);
    unawaited(_loadMonth());
    await app.fetchClientsForSelectedRouter();
    if (app.hasDumbAp || app.routers.length > 1) {
      try {
        final all = await app.fetchAggregatedClients();
        if (mounted) setState(() => _aggregated = all);
      } catch (_) {}
    }
  }

  Future<void> _loadMonth() async {
    final app = ref.read(appStateProvider);
    final r = app.selectedRouter;
    final api = app.apiService;
    if (r == null || api == null || app.sysauth == null) return;
    try {
      final report = await api.fetchNlbwmonData(
        r.ipAddress,
        app.sysauth!,
        r.useHttps,
      );
      if (report == null || !mounted) return;
      final m = <String, int>{};
      for (final h in report.records) {
        final mac = h.mac.toUpperCase().replaceAll('-', ':');
        m[mac] = (m[mac] ?? 0) + h.rxBytes + h.txBytes;
      }
      setState(() => _month = m);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final blocked = app.bannedWirelessMacs;
    final paused = app.pausedInternetMacs;
    final devices = withBlocked(_aggregated ?? app.clients, {
      ...blocked,
      ...paused,
    });
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Devices', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(
        top: false,
        child: AllDevicesView(
          devices: devices,
          blocked: blocked,
          paused: paused,
          limited: {
            for (final l in app.getActiveSpeedLimitsForRouter()) l.targetMac,
          },
          usage:
              _month ??
              {
                for (final c in devices)
                  if ((c.rxBytes ?? 0) + (c.txBytes ?? 0) > 0)
                    c.normalizedMac: (c.rxBytes ?? 0) + (c.txBytes ?? 0),
              },
          usageLabel: _month != null ? 'This month' : 'Since it connected',
          startByData: widget.byData,
          loading: app.isClientsLoading,
          onRefresh: _load,
          onOpen: (c) => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceScreen(mac: c.macAddress, fallback: c),
            ),
          ),
        ),
      ),
    );
  }
}
