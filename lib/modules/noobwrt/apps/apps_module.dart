// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/main.dart';

import '../../core/luci_module.dart';
import '../noob_rpc.dart';
import '../noob_widgets.dart';

class NoobApp {
  final String name;
  final String about;
  final IconData icon;
  final String? service;
  final String? luciPath;
  final int? webPort;
  const NoobApp(
    this.name,
    this.about,
    this.icon, {
    this.service,
    this.luciPath,
    this.webPort,
  });
}

const noobApps = [
  NoobApp(
    '5G Modem',
    'The full modem page: bands, texts, advanced commands',
    Icons.cell_tower,
    service: '5gmodem-sessionwatch',
    luciPath: 'admin/modem/5gmodem',
  ),
  NoobApp(
    'Phone web',
    'The full phone port settings page',
    Icons.phone,
    service: 'fxsd',
    webPort: 7766,
  ),
  NoobApp(
    'SIP server',
    'Lets phones on Wi-Fi make calls through the router',
    Icons.dialer_sip_outlined,
    service: 'msipd',
  ),
  NoobApp(
    'Preferred towers',
    'Sticks to the towers you prefer',
    Icons.low_priority,
    service: 'auto-pci-cell',
  ),
  NoobApp(
    'Samba',
    'Share USB drives on the network',
    Icons.folder_shared_outlined,
    service: 'samba4',
    luciPath: 'admin/services/samba4',
  ),
  NoobApp(
    'qBittorrent',
    'Downloads torrents to a USB drive',
    Icons.download_outlined,
    service: 'qbittorrent',
    luciPath: 'admin/services/qbittorrent',
    webPort: 8080,
  ),
  NoobApp(
    'Remote access (frpc)',
    'Reach the router from outside through your own server',
    Icons.alt_route,
    service: 'frpc',
    luciPath: 'admin/services/frpc',
  ),
  NoobApp(
    'Terminal',
    'A command line in the browser',
    Icons.terminal,
    service: 'ttyd',
    luciPath: 'admin/services/ttyd',
    webPort: 7681,
  ),
  NoobApp(
    'Disk sleep',
    'Lets USB drives sleep when unused',
    Icons.bedtime_outlined,
    service: 'hd-idle',
    luciPath: 'admin/services/hd_idle',
  ),
  NoobApp(
    'Watchcat',
    'Reboot or restart when the internet drops',
    Icons.pets_outlined,
    service: 'watchcat',
    luciPath: 'admin/services/watchcat',
  ),
  NoobApp(
    'Multi WAN',
    'Switches to a backup connection when one drops',
    Icons.call_split,
    service: 'mwan3',
    luciPath: 'admin/status/mwan3',
  ),
  NoobApp(
    'Disk manager',
    'Partition and format drives',
    Icons.storage_outlined,
    luciPath: 'admin/services/mini-diskmanager',
  ),
  NoobApp(
    'File manager',
    'Browse the files on the router',
    Icons.folder_open_outlined,
    luciPath: 'admin/system/filemanager',
  ),
];

class AppsModule extends LuciModule {
  @override
  String get id => 'noobwrt_apps';

  @override
  String get name => 'Router Apps';

  @override
  String get description =>
      'Start, stop and open the extra apps that come with the firmware';

  @override
  IconData get icon => Icons.apps_outlined;

  @override
  IconData get selectedIcon => Icons.apps;

  @override
  LuciModuleCategory get category => LuciModuleCategory.applications;

  @override
  int get priority => 17;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const AppsScreen();
}

class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  Map<String, dynamic>? _rc;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rc = await noobServices(ref.read(appStateProvider));
      if (mounted) {
        setState(() {
          _rc = rc;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _service(String name, String action) async {
    setState(() => _busy = name);
    try {
      await noobService(ref.read(appStateProvider), name, action);
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
    if (mounted) setState(() => _busy = null);
    await _load();
  }

  void _open(NoobApp a) {
    final router = ref.read(appStateProvider).selectedRouter;
    if (router == null) return;
    final host = router.ipAddress;
    final uri = a.webPort != null
        ? Uri.parse('http://$host:${a.webPort}/')
        : Uri.parse(
            '${router.useHttps ? 'https' : 'http'}://$host/cgi-bin/luci/${a.luciPath}',
          );
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final rc = _rc;
    if (rc == null) {
      return NoobPage(
        title: 'Router Apps',
        body: _error == null
            ? const Center(child: CircularProgressIndicator())
            : NoobProblem(
                title: 'Router Apps',
                detail: "The router didn't send its list of apps.",
                error: _error,
                onRetry: _load,
              ),
      );
    }
    return NoobPage(
      title: 'Router Apps',
      subtitle: 'Tap one to open it; the menu starts or stops it',
      onRefresh: _load,
      children: [
        for (final a in noobApps)
          if (a.service == null || rc.containsKey(a.service))
            _tile(a, rc[a.service]),
      ],
    );
  }

  Widget _tile(NoobApp a, dynamic s) {
    final info = s is Map ? s : const {};
    final running = info['running'] == true;
    final enabled = info['enabled'] == true;
    final busy = _busy == a.service;
    final canOpen = a.luciPath != null || a.webPort != null;
    final ks = context.ks;
    return KsRow(
      leading: a.service == null
          ? Icon(a.icon, size: 20, color: ks.mu)
          : KsDot(running ? ks.ok : ks.line),
      title: a.name,
      subtitle: a.service == null
          ? a.about
          : [
              a.about,
              [
                if (!info.containsKey('running'))
                  'Status unknown'
                else if (!running)
                  'Stopped',
                if (!enabled) 'off at start-up',
              ].join(' · '),
            ].where((l) => l.isNotEmpty).join('\n'),
      onTap: canOpen ? () => _open(a) : null,
      trailing: a.service == null
          ? Icon(Icons.open_in_new_rounded, size: 18, color: ks.mu)
          : busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : PopupMenuButton<String>(
              tooltip: 'More',
              color: ks.sheet,
              icon: Icon(Icons.more_horiz_rounded, color: ks.mu),
              onSelected: (act) =>
                  act == 'open' ? _open(a) : _service(a.service!, act),
              itemBuilder: (_) => [
                if (canOpen)
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(
                  value: running ? 'stop' : 'start',
                  child: Text(running ? 'Stop' : 'Start'),
                ),
                const PopupMenuItem(value: 'restart', child: Text('Restart')),
                PopupMenuItem(
                  value: enabled ? 'disable' : 'enable',
                  child: Text(
                    enabled
                        ? "Don't start it at start-up"
                        : 'Start it at start-up',
                  ),
                ),
              ],
            ),
    );
  }
}
