import 'dart:async';

import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/devices_usage/device_usage_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_installer.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/screens/home/home_data.dart';
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

String? installNote({required bool calendarTotals, int? billingDay}) {
  if (!calendarTotals) {
    return 'See the data each device uses, per billing period';
  }
  if (billingDay == null || billingDay == 1) return null;
  return 'Totals follow the calendar month, not your billing day. '
      'Install Data per device to match your bill.';
}

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
  String? _monthLabel;
  String? _note;
  bool _offerInstall = false;
  int? _billingDay;

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
    final keystone = DeviceUsageClient.of(app);
    try {
      final info = await keystone.info();
      final u = info == null ? null : await keystone.usage();
      if (!mounted) return;
      if (u != null) {
        setState(() {
          _month = {for (final d in u.byMac.values) d.mac: d.total};
          _monthLabel = u.start.day == 1
              ? 'This month'
              : 'Since ${dayMonth(u.start)}';
          _offerInstall = false;
          _note = info!.offload
              ? 'Offloading is on, so some traffic skips the counters and '
                    'totals may read low.'
              : null;
        });
        return;
      }
      if (info == null && !app.reviewerModeEnabled) {
        setState(() => _offerInstall = true);
      }
    } catch (_) {}
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
    if (!_offerInstall) return;
    try {
      final day = (await DataPlanClient.of(app).load())?.active?.billingDay;
      if (mounted) setState(() => _billingDay = day);
    } catch (_) {}
  }

  Future<void> _install() async {
    final app = ref.read(appStateProvider);
    setState(() => _note = 'Installing on the router. This can take a minute.');
    try {
      await HelperInstaller(app, package: 'keystone-devices').install();
      _offerInstall = false;
      _note = null;
      await _loadMonth();
    } catch (e) {
      _note = e is NoobRpcError ? e.message : "Couldn't reach the router.";
    }
    if (mounted) setState(() {});
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
    final offer = _offerInstall
        ? installNote(calendarTotals: _month != null, billingDay: _billingDay)
        : null;
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
          usageLabel: _month != null
              ? (_monthLabel ?? 'This month')
              : 'Since it connected',
          note: offer ?? _note,
          noteAction: offer != null ? 'Install' : null,
          onNote: offer != null ? _install : null,
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
