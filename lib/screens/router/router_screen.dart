import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/noobwrt/tools/tools_module.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/modules/system_monitoring/models/system_metrics.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/router/light_meanings.dart';
import 'package:yet_another_luci_app/screens/router/logs_screen.dart';
import 'package:yet_another_luci_app/screens/router/power_sheet.dart';
import 'package:yet_another_luci_app/screens/router/router_view.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';
import 'package:yet_another_luci_app/utils/release_utils.dart';

class RouterScreen extends ConsumerStatefulWidget {
  const RouterScreen({super.key});

  @override
  ConsumerState<RouterScreen> createState() => _RouterScreenState();
}

class _RouterScreenState extends ConsumerState<RouterScreen> {
  Timer? _timer;
  RouterLights _lights = RouterLights.unlit;
  ModemMetrics? _modem;
  String? _phone;
  Map<String, dynamic>? _sysInfo;
  final _cpu = <double>[];
  final _mem = <double>[];
  int _tick = 0;
  Map<String, dynamic>? _recorded;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      _tick++;
      _tick.isEven ? _load() : _sample();
    });
  }

  Future<void> _sample() async {
    try {
      final info = await noobCall(ref.read(appStateProvider), 'system', 'info');
      if (mounted) setState(() => _sysInfo = info);
    } catch (_) {}
  }

  void _record(SystemMetrics m) {
    if (m.totalMemoryBytes <= 0) return;
    _cpu.add(m.cpuUsagePercent);
    _mem.add(m.usedMemoryBytes / m.totalMemoryBytes * 100);
    if (_cpu.length > 120) {
      _cpu.removeAt(0);
      _mem.removeAt(0);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final app = ref.read(appStateProvider);
    final lights = await const AppStateSignInBackend().readLights();
    ModemMetrics? modem;
    String? phone;
    Map<String, dynamic>? sysInfo;
    try {
      sysInfo = await noobCall(app, 'system', 'info');
    } catch (_) {}
    try {
      final files = await listModemMetrics(ref);
      if (files.isNotEmpty) modem = await readModemMetrics(ref, files.first);
    } catch (_) {}
    try {
      phone = (await noobCall(app, 'fxs', 'status'))['state']?.toString();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _lights = lights;
      _modem = modem;
      _phone = phone;
      _sysInfo = sysInfo ?? _sysInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final data = app.dashboardData;
    final board = data?['boardInfo'] as Map<String, dynamic>?;
    final model = board?['model']?.toString();
    final release = deriveDistributionInfo(board?['release'], model: model);
    final metrics = SystemMetrics.fromSysInfo(
      _sysInfo ?? data?['sysInfo'] as Map<String, dynamic>?,
      boardInfo: board,
      temperature: data?['temperature'],
    );
    if (!identical(_recorded, _sysInfo) && _sysInfo != null) {
      _recorded = _sysInfo;
      _record(metrics);
    }
    final temp = metrics.temperature?.mainTemperature;
    final upLine = [
      if (metrics.uptimeSeconds > 0) 'Up ${onlineFor(metrics.uptimeSeconds)}',
      if (temp != null) '${temp.round()}°C',
    ].join(' · ');
    final root = (_sysInfo ?? data?['sysInfo'])?['root'];
    final health = [
      if (metrics.cpuUsagePercent > 0)
        RouterGauge(
          'Processor',
          '${metrics.cpuUsagePercent.round()}% busy',
          metrics.cpuUsagePercent / 100,
          detail: metrics.load1m > 0
              ? 'Load ${[metrics.load1m, metrics.load5m, metrics.load15m].map((l) => l.toStringAsFixed(2)).join(' · ')}'
              : null,
        ),
      if (metrics.totalMemoryBytes > 0)
        RouterGauge(
          'Memory',
          '${sizeWords(metrics.usedMemoryBytes)} of '
              '${sizeWords(metrics.totalMemoryBytes)}',
          metrics.usedMemoryBytes / metrics.totalMemoryBytes,
        ),
    ];
    final sensors = metrics.temperature?.sensors ?? const [];
    final temps = sensors.length > 1
        ? temperatureGroups([
            for (final t in sensors) ('${t.name} ${t.rawName}', t.value),
          ])
        : const <(String, String)>[];
    final store = StorageOverview.fromRpcData(
      data?['mountPoints'],
      isReviewerMode: app.reviewerModeEnabled,
    );
    RouterGauge gauge(String label, int used, int total, {String? detail}) =>
        RouterGauge(
          label,
          '${sizeWords(used)} of ${sizeWords(total)}',
          total > 0 ? used / total : 0,
          detail: detail,
        );
    final storage = <RouterGauge>[
      if (store.inbuiltStorageTotalBytes > 0)
        gauge(
          'On the router',
          store.inbuiltStorageUsedBytes,
          store.inbuiltStorageTotalBytes,
        )
      else if (root is Map && (root['total'] as num? ?? 0) > 0)
        gauge(
          'On the router',
          (root['used'] as num? ?? 0).toInt() * 1024,
          (root['total'] as num).toInt() * 1024,
        ),
      for (final m in store.externalMounts)
        gauge('Drive', m.usedBytes, m.sizeBytes, detail: m.mountPath),
    ];
    final wifiOn = WirelessOverview.fromDashboardData(
      data,
      isReviewerMode: app.reviewerModeEnabled,
    ).radios.expand((r) => r.interfaces).where((i) => i.isEnabled).length;

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Home', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(
        top: false,
        child: RouterView(
          name: routerDisplayName(app.selectedRouter),
          model: model ?? app.selectedRouter?.lastKnownModel,
          firmware: release.version == 'N/A'
              ? null
              : '${release.distributionName} ${release.version}',
          upLine: upLine.isEmpty ? null : upLine,
          lights: _lights,
          rows: lightMeanings(
            _lights,
            signalPercent: _modem?.signalPercent,
            mode: _modem?['mode']?.split('|').first.trim(),
            wifiNetworksOn: wifiOn,
            phoneState: _phone,
          ),
          health: health,
          temps: temps,
          storage: storage,
          cpuSamples: List.of(_cpu),
          memSamples: List.of(_mem),
          onLogs: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const LogsScreen())),
          onPowerOptions: () => showPowerSheet(context),
          onReboot: () => app.reboot(context: context),
          onNightLights:
              LuciModuleRegistry.instance
                      .getModule('noobwrt_tools')
                      ?.isAvailableOn(app.capabilities) ==
                  true
              ? () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const ToolsScreen()))
              : null,
        ),
      ),
    );
  }
}
