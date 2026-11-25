// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

import '../../core/luci_module.dart';
import '../noob_rpc.dart';
import '../noob_widgets.dart';

class ToolsModule extends LuciModule {
  @override
  String get id => 'noobwrt_tools';

  @override
  String get name => 'Router Tools';

  @override
  String get description => 'Wake a device, lights at night, free up memory';

  @override
  IconData get icon => Icons.handyman_outlined;

  @override
  IconData get selectedIcon => Icons.handyman;

  @override
  LuciModuleCategory get category => LuciModuleCategory.tools;

  @override
  int get priority => 16;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const ToolsScreen();
}

class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  bool? _night;
  String? _nightWindow;
  String? _governor;
  bool _wol = false;
  List<Map<String, dynamic>> _leases = const [];
  bool _loading = true;

  AppState get _app => ref.read(appStateProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<T?> _try<T>(Future<T> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final led = await _try(noobUciSections(_app, 'ledstatus'));
    final cpu = await _try(noobUciSections(_app, 'cpufreq'));
    final wol = await _try(noobCall(_app, 'luci.wol', 'stat'));
    final leases = await _try(noobCall(_app, 'luci-rpc', 'getDHCPLeases'));
    if (!mounted) return;
    final ls = led?.where((s) => s['.name'] == 'settings').firstOrNull;
    setState(() {
      _night = ls == null ? null : ls['night_enabled'] == '1';
      _nightWindow = ls == null
          ? null
          : '${ls['night_start'] ?? '-'} to ${ls['night_end'] ?? '-'}';
      _governor = cpu?.firstOrNull?['governor0']?.toString();
      _wol = wol?['etherwake'] == true || wol?['wakeonlan'] == true;
      final l = leases?['dhcp_leases'];
      _leases = [
        if (l is List)
          for (final x in l)
            if (x is Map && x['macaddr'] != null) Map<String, dynamic>.from(x),
      ];
      _loading = false;
    });
  }

  Future<void> _do(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) ksSay(context, done);
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const NoobPage(
        title: 'Router Tools',
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return NoobPage(
      title: 'Router Tools',
      onRefresh: _load,
      children: [
        if (_wol) _wolSection(),
        if (_night != null)
          NoobSection(
            title: 'Lights at night',
            icon: Icons.nightlight_outlined,
            children: [
              KsSwitchRow(
                title: 'Turn the lights off at night',
                subtitle: _nightWindow,
                value: _night!,
                onChanged: (v) => _do(
                  () => noobCall(
                    _app,
                    'luci.aw1k-led',
                    v ? 'night_enable' : 'night_disable',
                  ),
                  v ? 'Lights off at night' : 'Lights stay on',
                ),
              ),
            ],
          ),
        NoobSection(
          title: 'Memory',
          icon: Icons.memory,
          children: [
            KsRow(
              title: 'Free up memory',
              subtitle: 'Clears cached files. Nothing you saved is lost.',
              onTap: () => _do(() async {
                await noobCall(_app, 'file', 'exec', {'command': '/bin/sync'});
                await noobCall(_app, 'file', 'exec', {
                  'command': '/sbin/sysctl',
                  'params': ['-w', 'vm.drop_caches=3'],
                });
              }, 'Memory freed'),
            ),
          ],
        ),
        if (_governor != null)
          NoobSection(
            title: 'Processor',
            icon: Icons.developer_board,
            children: [
              NoobRow('Speed mode', switch (_governor) {
                'performance' => 'Always full speed',
                'ondemand' ||
                'schedutil' ||
                'conservative' => 'Speeds up when busy',
                'powersave' => 'Saves power',
                final g => g,
              }),
            ],
          ),
      ],
    );
  }

  Widget _wolSection() {
    return NoobSection(
      title: 'Wake a device',
      icon: Icons.power_settings_new,
      children: [
        if (_leases.isEmpty)
          const KsNote('No devices have asked the router for an address.'),
        for (final l in _leases)
          KsRow(
            title: noobValue(l['hostname']) ?? l['macaddr'].toString(),
            subtitle: '${l['ipaddr'] ?? ''} · ${l['macaddr']}',
            trailing: TextButton(
              onPressed: () => _do(
                () => noobCall(_app, 'luci.wol', 'exec', {
                  'name': '/usr/bin/etherwake',
                  'args': ['-D', '-i', 'br-lan', l['macaddr'].toString()],
                }),
                'Wake-up sent',
              ),
              child: const Text('Wake'),
            ),
          ),
      ],
    );
  }
}
