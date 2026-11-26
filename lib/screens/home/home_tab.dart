import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/background/widget_data.dart';
import 'package:yet_another_luci_app/screens/home/home_data.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/noobwrt/apps/apps_module.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_sheet.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/cellular_module.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/noobwrt/slow/slow_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/passwall/passwall_module.dart';
import 'package:yet_another_luci_app/modules/noobwrt/phone/phone_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/tools/tools_module.dart';
import 'package:yet_another_luci_app/modules/noobwrt/bandix/bandix_rates.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';
import 'package:yet_another_luci_app/screens/devices/device_screen.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';
import 'package:yet_another_luci_app/screens/home/home_view.dart';
import 'package:yet_another_luci_app/screens/network/network_screen.dart';
import 'package:yet_another_luci_app/screens/home/shortcuts.dart';
import 'package:yet_another_luci_app/screens/routers/routers_sheet.dart';
import 'package:yet_another_luci_app/screens/router/router_screen.dart';
import 'package:yet_another_luci_app/screens/speed/speed_screen.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_tab.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/services/device_discovery.dart';

class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key, this.isTabActive = true});

  final bool isTabActive;

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> with WidgetsBindingObserver {
  Timer? _modemTimer;
  Timer? _lightsTimer;
  ModemMetrics? _modem;
  SignalOverview? _signal;
  final _memory = SignalMemory();
  QmodemSession? _qmodem;
  DateTime? _qmodemAt;
  String? _signalRouter;
  bool _readingModem = false;
  RouterLights _lights = RouterLights.unlit;

  DataPlans? _plans;
  String? _plansRouter;
  DateTime? _plansAt;

  Map<String, dynamic>? _dump;

  Map<String, dynamic>? _netDevices;
  bool _polling = false;
  bool _onTop = true;
  bool _foreground = true;

  List<String>? _savedShortcuts;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomePrefsStore.instance.addListener(_prefsChanged);
    HomePrefsStore.instance.load();
    DeviceKindStore.instance.load();
    DeviceDiscovery.instance.maybeScan();
    loadShortcutIds().then((ids) {
      if (mounted) setState(() => _savedShortcuts = ids);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = ref.read(appStateProvider);
      if (app.dashboardData?['boardInfo'] == null) {
        app.fetchDashboardData(force: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    _sync();
  }

  @override
  void didUpdateWidget(HomeTab old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HomePrefsStore.instance.removeListener(_prefsChanged);
    _stop();
    super.dispose();
  }

  void _prefsChanged() {
    if (mounted) setState(() {});
  }

  void _stop() {
    _modemTimer?.cancel();
    _lightsTimer?.cancel();
    _polling = false;
  }

  void _sync() {
    final want = homeShouldPoll(
      tabActive: widget.isTabActive,
      onTop: _onTop,
      foreground: _foreground,
      rebooting: ref.read(appStateProvider).isRebooting,
    );
    if (want == _polling) return;
    if (!want) return _stop();
    _polling = true;
    _loadModem();
    _loadSlow();
    _modemTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadModem(),
    );
    _lightsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadSlow(),
    );
  }

  Future<void> _loadSlow() =>
      Future.wait([_loadLights(), _loadDump(), _loadPlans()]);

  Future<void> _loadDump() async {
    final app = ref.read(appStateProvider);
    try {
      final d = await noobCall(app, 'network.interface', 'dump');
      if (mounted) setState(() => _dump = d);
    } catch (_) {}
    try {
      final n = await noobCall(app, 'luci-rpc', 'getNetworkDevices');
      if (mounted) setState(() => _netDevices = n);
    } catch (_) {}
  }

  DateTime? _widgetAt;
  Map<String, String>? _widgetKeys;

  void _keepWidget(
    HomeStatus status,
    SignalOverview? signal,
    SimPlan? plan, {
    required bool planKnown,
  }) {
    if (ref.read(appStateProvider).reviewerModeEnabled) return;
    final s = homeSnapshot(
      routerDisplayName(ref.read(appStateProvider).selectedRouter),
      status,
      bars: signal?.bars,
      plan: plan,
      signal: signal,
      now: DateTime.now(),
    );
    if (s == null) return;
    final keys = snapshotKeys(s, signal: signal != null, data: planKnown);
    final same = mapEquals(
      {..._widgetKeys ?? {}}..remove('widget.at'),
      {...keys}..remove('widget.at'),
    );
    final at = _widgetAt;
    if (same &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 1)) {
      return;
    }
    _widgetAt = s.at;
    _widgetKeys = keys;
    SharedPreferences.getInstance()
        .then((p) => saveWidgetKeys(p, keys))
        .catchError((_) {});
  }

  Future<void> _loadPlans() async {
    final app = ref.read(appStateProvider);
    final id = app.selectedRouter?.id;
    if (id != _plansRouter) {
      _plansRouter = id;
      _plansAt = null;
      _plans = null;
    }
    final at = _plansAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 2)) {
      return;
    }
    _plansAt = DateTime.now();
    try {
      final p = await DataPlanClient.of(app).load();
      if (mounted && id == app.selectedRouter?.id) setState(() => _plans = p);
    } catch (_) {}
  }

  Future<void> _editPlan(SimPlan plan) async {
    final saved = await showDataPlanSheet(
      context,
      DataPlanClient.of(ref.read(appStateProvider)),
      sim: plan.sim,
      plan: plan,
    );
    if (saved == null || !mounted) return;
    _plansAt = null;
    await _loadPlans();
  }

  Future<void> _loadModem() async {
    if (_readingModem) return;
    final app = ref.read(appStateProvider);
    final id = app.selectedRouter?.id;
    if (id != _signalRouter) {
      _signalRouter = id;
      _memory.clear();
      _qmodem = null;
      _qmodemAt = null;
      _modem = null;
      _signal = null;
    }
    _readingModem = true;
    try {
      final (read, m) = await _readMetrics();
      var now = m == null ? null : SignalOverview.fromMetrics(m);
      // Each read waits on the modem's one AT port. Just under 30 s, so timer
      // drift can't skip a third 10 s tick.
      final keep =
          now?.hasReadings != true &&
          _qmodemAt != null &&
          DateTime.now().difference(_qmodemAt!) < const Duration(seconds: 25);
      if (now?.hasReadings != true && !keep) now = await _readQmodem() ?? now;
      if (!mounted || id != ref.read(appStateProvider).selectedRouter?.id) {
        return;
      }
      setState(() {
        if (read) _modem = m;
        if (keep) return;
        _signal = _memory.next(
          now,
          at: DateTime.now(),
          mbps: _mbps(app.currentRxRate + app.currentTxRate),
          keepCarriers: HomePrefsStore.instance.value.idleCarriers,
        );
      });
    } finally {
      _readingModem = false;
    }
  }

  Future<(bool, ModemMetrics?)> _readMetrics() async {
    if (!_installed('noobwrt_modem')) return (false, null);
    try {
      final files = await listModemMetrics(ref);
      if (files.isEmpty) return (true, null);
      return (true, await readModemMetrics(ref, files.first));
    } catch (_) {
      return (false, null);
    }
  }

  Future<SignalOverview?> _readQmodem() async {
    final p = HomePrefsStore.instance.value;
    if (!mounted ||
        !_installed('noobwrt_cellular') ||
        !(p.signalBars || p.beside || p.signal)) {
      return null;
    }
    _qmodemAt = DateTime.now();
    try {
      final session = _qmodem ??= QmodemSession(ref.read(appStateProvider));
      final (info, mode, carriers) = await session.read();
      return SignalOverview.fromQmodem(info, mode, carriers);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLights() async {
    final lights = await const AppStateSignInBackend().readLights();
    if (mounted) setState(() => _lights = lights);
  }

  bool _installed(String moduleId) =>
      LuciModuleRegistry.instance
          .getModule(moduleId)
          ?.isAvailableOn(ref.read(appStateProvider).capabilities) ??
      false;

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  static double _mbps(double bytesPerSecond) => bytesPerSecond * 8 / 1e6;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
    final dump = _dump ?? app.dashboardData?['interfaceDump'];
    final m = _modem;
    final status = HomeStatus.from(
      interfaces: dump is Map ? dump['interface'] as List? : null,
      signalPercent: m?.signalPercent,
      operatorName: m?['operator_name'],
      mode: m?['mode']?.split('|').first.trim(),
      modemConnected: m?.connected,
      devices: app.clients.where((c) => c.isConnected).length,
      address: app.currentRouterIp ?? app.selectedRouter?.ipAddress,
      loading: homeStillLoading(
        fetching: app.isDashboardLoading || app.isLoading,
        hasDump: dump != null,
        failed: app.dashboardError != null,
      ),
    );
    final modem = _installed('noobwrt_modem');
    final signal = _signalRouter == app.selectedRouter?.id ? _signal : null;
    final plan = _plansRouter == app.selectedRouter?.id ? _plans?.active : null;
    _keepWidget(
      status,
      signal,
      plan,
      planKnown: _plansRouter == app.selectedRouter?.id && _plans != null,
    );
    final prefs = HomePrefsStore.instance.value;
    final rates = widget.isTabActive && _installed('noobwrt_bandix')
        ? ref.watch(bandixRatesProvider).valueOrNull
        : null;
    final online = withBandix(
      app.clients.where((c) => c.isConnected).toList(),
      rates,
    );
    final mbs = prefs.unit == SpeedUnit.mbs;
    final devices = [
      for (final c in pickFlowDevices(online, prefs))
        FlowDevice(
          name: c.displayName,
          icon: ClientNamingHelper.getDeviceIcon(c),
          mbps: deviceMbps(c),
          line: deviceMbps(c) >= 0.05
              ? '${(mbs ? deviceMbps(c) / 8 : deviceMbps(c)).toStringAsFixed(1)} ${mbs ? 'MB/s' : 'Mbps'}'
              : deviceLine(c),
          onTap: () => _open(DeviceScreen(mac: c.macAddress)),
        ),
    ];

    final available = <_Shortcut>[
      if (!app.reviewerModeEnabled)
        _Shortcut(
          'why_slow',
          'Why slow?',
          Icons.troubleshoot_rounded,
          () => _open(SlowScreen(checks: () => routerSlowChecks(app))),
        ),
      if (WifiSetup(
            WirelessOverview.fromDashboardData(
              app.dashboardData,
              isReviewerMode: app.reviewerModeEnabled,
            ),
          ).home !=
          null)
        _Shortcut(
          'share_wifi',
          'Share Wi-Fi',
          Icons.qr_code_rounded,
          () => shareWifi(context, app),
        ),
      if (_installed('noobwrt_tools'))
        _Shortcut(
          'speed_test',
          'Speed test',
          Icons.speed_rounded,
          () => _open(const SpeedScreen()),
        ),
      for (final (id, icon, label, screen) in [
        ('noobwrt_modem', Icons.cell_tower, 'Modem', const ModemScreen()),
        ('noobwrt_phone', Icons.phone_outlined, 'Phone', const PhoneScreen()),
        (
          'noobwrt_passwall2',
          Icons.vpn_lock_outlined,
          'Passwall2',
          const PasswallScreen(),
        ),
        (
          'noobwrt_passwall',
          Icons.vpn_lock_outlined,
          'Passwall',
          const PasswallScreen(kind: PasswallKind.v1),
        ),
        (
          'noobwrt_bandix',
          Icons.swap_vert,
          'Traffic',
          const AllDevicesScreen(byData: true),
        ),
        (
          'noobwrt_tools',
          Icons.handyman_outlined,
          'Tools',
          const ToolsScreen(),
        ),
        ('noobwrt_apps', Icons.apps_rounded, 'Apps', const AppsScreen()),
      ])
        if (_installed(id)) _Shortcut(id, label, icon, () => _open(screen)),
    ];
    final shortcuts = [
      for (final c in pickShortcuts(available, _savedShortcuts))
        HomeShortcut(c.icon, c.label, c.onTap),
    ];

    return HomeView(
      prefs: prefs,
      devices: devices,
      onEditShortcuts: available.isEmpty
          ? null
          : () => _open(
              ShortcutsView(
                all: available,
                chosen: [
                  for (final c in pickShortcuts(available, _savedShortcuts))
                    c.id,
                ],
                onDone: (ids) {
                  saveShortcutIds(ids);
                  setState(() => _savedShortcuts = ids);
                  Navigator.of(context).pop();
                },
              ),
            ),
      address: app.currentRouterIp ?? app.selectedRouter?.ipAddress,
      onOpenWifiSettings: Platform.isAndroid
          ? () => const MethodChannel(
              'com.perz3us.keystone/app_lifecycle',
            ).invokeMethod<void>('openWifiSettings')
          : null,
      routerName: routerDisplayName(app.selectedRouter),
      model: app.selectedRouter?.lastKnownModel,
      status: status,
      lights: _lights,
      shortcuts: shortcuts,
      downMbps: _mbps(app.currentRxRate),
      upMbps: _mbps(app.currentTxRate),
      downHistory: [for (final v in app.rxHistory) _mbps(v)],
      upHistory: [for (final v in app.txHistory) _mbps(v)],
      onRouterMenu: () => showRoutersSheet(context),
      onSettings: () => app.requestTab(4),
      onInternet: modem
          ? () => _open(const ModemScreen())
          : () => _open(const NetworkScreen()),
      signal: signal,
      onSignal: () => _open(
        _modem == null && _qmodem?.modem != null
            ? const CellularScreen()
            : const ModemScreen(),
      ),
      dataPlan: plan,
      onDataPlan: plan == null ? null : () => _editPlan(plan),
      onDevices: () => app.requestTab(2),
      onRouter: () => _open(const RouterScreen()),
      onAction: modem ? () => _open(const ModemScreen()) : null,
      usage: WanUsage.from(
        dump,
        _netDevices ?? app.dashboardData?['networkDevices'],
      ),
      onRefresh: () async {
        await app.fetchDashboardData(force: true);
        _qmodemAt = null;
        _plansAt = null;
        await Future.wait([_loadModem(), _loadSlow()]);
      },
    );
  }
}

class _Shortcut extends ShortcutChoice {
  const _Shortcut(super.id, super.label, super.icon, this.onTap);
  final VoidCallback onTap;
}
