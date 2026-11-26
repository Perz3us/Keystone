// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../../core/luci_module.dart';
import '../noob_rpc.dart';
import '../noob_widgets.dart';
import 'cell_guard.dart';
import 'cellular_data.dart';
import '../history/helper_sheet.dart';
import '../modem/modem_actions.dart';
import '../modem/modem_pages.dart';
import '../modem/modem_settings.dart';
import 'lock_controls.dart';
import 'preferred_towers.dart';

class CellularModule extends LuciModule {
  @override
  String get id => 'noobwrt_cellular';

  @override
  Set<String> get requiredConfigs => const {'qmodem'};

  @override
  String get name => 'Mobile network';

  @override
  String get description => '4G and 5G signal, carriers, band and cell lock';

  @override
  IconData get icon => Icons.signal_cellular_alt_outlined;

  @override
  IconData get selectedIcon => Icons.signal_cellular_alt;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 11;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const CellularScreen();
}

// Older QModem has no ubus object, only a LuCI page that runs this script.
// The page rejects ubus login sessions with 403, so run the script directly.
Future<Map<String, dynamic>> qmodemViaScript(
  AppState app,
  String cfg,
  String action, [
  Object? params,
]) async {
  final r = await noobCall(app, 'file', 'exec', {
    'command': '/bin/sh',
    'params': [
      '/usr/share/qmodem/modem_ctrl.sh',
      action,
      cfg,
      if (params != null) jsonEncode(params),
    ],
  });
  try {
    final data = jsonDecode('${r['stdout'] ?? ''}');
    if (data is Map) return Map<String, dynamic>.from(data);
  } on FormatException catch (_) {}
  throw const NoobRpcError("QModem didn't answer");
}

class QmodemSession {
  QmodemSession(this.app);
  final AppState app;
  String? modem;
  bool _viaScript = false;

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> extra = const {},
  ]) => _viaScript
      ? qmodemViaScript(app, modem!, method, extra['params'])
      : noobCall(app, 'qmodem', method, {'config_section': modem, ...extra});

  Future<void> _open() async {
    final sections = await noobUciSections(app, 'qmodem');
    modem = sections
        .where((s) => s['.type'] == 'modem-device')
        .firstOrNull?['.name']
        ?.toString();
    if (modem == null) throw const NoobRpcError('No modem set up');
    _viaScript = false;
    try {
      await call('cell_info');
    } catch (_) {
      _viaScript = true;
      try {
        await call('cell_info');
      } catch (_) {
        _viaScript = false;
        modem = null;
        rethrow;
      }
    }
  }

  Future<(List<CellEntry>, String?, List<Carrier>)> read() async {
    if (modem == null) await _open();
    final r = await Future.wait([
      call('cell_info'),
      call('get_current_band').catchError((_) => <String, dynamic>{}),
    ]);
    final (mode, carriers) = Carrier.parse(r[1]);
    return (CellEntry.parse(r[0]), mode, carriers);
  }
}

String _modeName(String? m) => switch (m) {
  'EN-DC' => '4G + 5G (NSA)',
  'NR5G-SA' => '5G SA',
  'LTE' => '4G',
  'WCDMA' => '3G',
  null => 'No service',
  _ => m,
};

class CellularScreen extends ConsumerStatefulWidget {
  const CellularScreen({super.key});

  @override
  ConsumerState<CellularScreen> createState() => _CellularScreenState();
}

class _CellularScreenState extends ConsumerState<CellularScreen> {
  Timer? _timer;
  bool _polling = false;
  List<CellEntry> _info = const [];
  String? _mode;
  List<Carrier> _carriers = const [];
  bool _loading = true;
  final _live = ValueNotifier<int>(0);
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live.dispose();
    super.dispose();
  }

  late final _session = QmodemSession(ref.read(appStateProvider));
  late final _controls = QmodemControls(_q);

  String? get _modem => _session.modem;

  Future<Map<String, dynamic>> _q(
    String method, [
    Map<String, dynamic> extra = const {},
  ]) => _session.call(method, extra);

  Future<void> _load() async {
    // Calls queue on the modem's one AT port, so never stack polls.
    if (_polling) return;
    _polling = true;
    try {
      final (info, mode, carriers) = await _session.read();
      if (!mounted) return;
      setState(() {
        _info = info;
        _mode = mode;
        _carriers = carriers;
        _error = null;
        _loading = false;
      });
      _live.value++;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      _polling = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const NoobPage(
        title: 'Mobile network',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_info.isEmpty && _error != null) {
      return NoobPage(
        title: 'Mobile network',
        body: NoobProblem(
          title: 'No modem data',
          detail:
              "QModem didn't answer. Check the modem shows under Modem > "
              'QModem in LuCI.',
          error: _error,
          onRetry: () {
            setState(() {
              _loading = true;
              _session.modem = null;
            });
            _load();
          },
        ),
      );
    }
    final ks = context.ks;
    final app = ref.read(appStateProvider);
    return NoobPage(
      title: 'Mobile network',
      subtitle: _mode != null
          ? _modeName(_mode)
          : _info
                .where((e) => e.key.toLowerCase() == 'network_mode')
                .firstOrNull
                ?.value
                .replaceFirst(RegExp(r'\s*Mode$'), ''),
      onRefresh: _load,
      children: [
        if (_modem != null)
          ModemActions(
            key: const ValueKey('modem-network'),
            controls: _controls,
            online: () => routerOnline(app),
            parts: const {ModemPart.network},
          ),
        NoobSection(
          title: 'Signal',
          icon: Icons.signal_cellular_alt,
          children: [
            for (final e in _info)
              if (e.isHeading)
                KsSection(e.key)
              else if (e.isMain)
                _reading(e, ks),
          ],
        ),
        const SizedBox(height: 16),
        HistoryRow(app: app),
        if (_modem != null)
          ModemActions(
            key: const ValueKey('modem-fix'),
            controls: _controls,
            online: () => routerOnline(app),
            parts: const {ModemPart.fix},
          ),
        const SizedBox(height: 16),
        if (_modem != null) ...[
          ModemPageRow(
            title: 'Towers and bands',
            subtitle: _carriers.isEmpty
                ? 'Carriers, bands and cell lock'
                : _carriers.map((c) => c.band).join(' + '),
            live: _live,
            children: (_) => [
              ...valueRows('Carriers', Icons.stacked_bar_chart, [
                for (final c in _carriers) (c.label, c.detail),
              ]),
              LockControls(
                key: const ValueKey('lock-controls'),
                locks: QmodemLocks(_q),
                nrBand: _carriers.where((c) => c.rat == 'NR').firstOrNull?.band,
                towers: PreferredTowers(app),
                guard: CellGuard(app),
              ),
            ],
          ),
          ModemPageRow(
            title: 'SIM and APN',
            subtitle: 'SIM, APN and roaming',
            live: _live,
            children: (_) => [
              SimSettings(
                key: const ValueKey('sim-settings'),
                controls: _controls,
              ),
            ],
          ),
        ],
        ModemPageRow(
          title: 'Modem details',
          subtitle: 'All readings and restart',
          live: _live,
          children: (c) => [
            for (final e in _info)
              if (e.isHeading) KsSection(e.key) else _reading(e, c.ks),
            const SizedBox(height: 24),
            if (_modem != null)
              ModemActions(
                key: const ValueKey('modem-restart'),
                controls: _controls,
                online: () => routerOnline(app),
                parts: const {ModemPart.restart},
              ),
          ],
        ),
      ],
    );
  }

  Widget _reading(CellEntry e, KeystoneColors ks) => NoobRow(
    e.key,
    e.unit == null ? e.value : '${e.value} ${e.unit}',
    color: switch (e.fill) {
      null => null,
      >= 0.6 => ks.ok,
      >= 0.35 => ks.warnTx,
      _ => ks.bad,
    },
  );
}
