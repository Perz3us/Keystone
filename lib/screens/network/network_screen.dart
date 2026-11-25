import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/interface.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/screens/dhcp_dns_screen.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

String connectionName(String name, String protocol) {
  final n = name.toLowerCase();
  final p = protocol.toLowerCase();
  if (p == 'wireguard' ||
      p == 'openvpn' ||
      n.startsWith('wg') ||
      n.contains('vpn')) {
    return 'VPN · $name';
  }
  if (n == 'lan') return 'Home network';
  if (n == 'wan') return 'Internet';
  if (n == 'wan6') return 'Internet, IPv6';
  if (n.contains('guest')) return 'Guest network';
  if (const [
        'qmi',
        'qmiraw',
        'modemmanager',
        'ncm',
        'mbim',
        '3g',
      ].contains(p) ||
      n.contains('modem') ||
      n.contains('wwan')) {
    return n.endsWith('6') ? 'Mobile internet, IPv6' : 'Mobile internet';
  }
  return name;
}

String protocolWords(String protocol) => switch (protocol.toLowerCase()) {
  'dhcp' => 'Gets its address automatically',
  'dhcpv6' => 'Gets an IPv6 address automatically',
  'static' => 'Fixed address',
  'pppoe' => 'Dial-up login (PPPoE)',
  'qmi' ||
  'qmiraw' ||
  'modemmanager' ||
  'ncm' ||
  'mbim' ||
  '3g' => 'Mobile data',
  'wireguard' => 'WireGuard tunnel',
  'none' => 'No address of its own',
  '' => 'Not set up',
  final p => p,
};

List<NetworkInterface> readConnections(Map<String, dynamic>? data) {
  final dump = data?['interfaceDump'];
  final devices = data?['networkDevices'];
  final stats = devices is Map ? devices : const {};
  final list = <NetworkInterface>[
    if (dump is Map && dump['interface'] is List)
      for (final m in (dump['interface'] as List).whereType<Map>())
        NetworkInterface.fromJson({
          ...Map<String, dynamic>.from(m),
          if ((m['stats'] as Map?)?.isNotEmpty != true &&
              stats[m['l3_device'] ?? m['device']] is Map)
            'stats': (stats[m['l3_device'] ?? m['device']] as Map)['stats'],
        }),
  ]..removeWhere((i) => i.name == 'loopback');
  int rank(NetworkInterface i) {
    final n = connectionName(i.name, i.protocol);
    if (n.startsWith('Internet') || n.startsWith('Mobile')) return 0;
    if (n == 'Home network') return 1;
    return 2;
  }

  return list..sort((a, b) {
    if (a.isUp != b.isUp) return a.isUp ? -1 : 1;
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.name.compareTo(b.name);
  });
}

class NetworkScreen extends ConsumerWidget {
  const NetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final list = readConnections(app.dashboardData);
    return NetworkView(
      connections: list,
      loading: app.isDashboardLoading && list.isEmpty,
      onRefresh: app.fetchDashboardData,
      onOpen: (i) => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ConnectionScreen(name: i.name))),
      onAddresses: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DhcpDnsScreen())),
    );
  }
}

class NetworkView extends StatelessWidget {
  const NetworkView({
    super.key,
    required this.connections,
    required this.onOpen,
    this.onAddresses,
    this.onRefresh,
    this.loading = false,
  });

  final List<NetworkInterface> connections;
  final ValueChanged<NetworkInterface> onOpen;
  final VoidCallback? onAddresses;
  final Future<void> Function()? onRefresh;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return KsPage(
      title: 'Network',
      subtitle: 'Internet and home network connections',
      onRefresh: onRefresh,
      children: [
        const KsSection('Connections'),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (connections.isEmpty)
          const KsNote("The router didn't list its connections.")
        else
          for (final i in connections)
            KsRow(
              leading: KsDot(i.isUp ? ks.ok : ks.line),
              title: connectionName(i.name, i.protocol),
              subtitle: i.isUp
                  ? [
                      if (i.uptime > 0) 'Up ${onlineFor(i.uptime)}',
                      ?i.ipAddress,
                    ].join(' · ')
                  : 'Off',
              onTap: () => onOpen(i),
            ),
        if (onAddresses != null) ...[
          const KsSection('Also here'),
          KsRow(
            title: 'Addresses and DNS',
            subtitle: 'Fixed addresses, and who looks up names',
            onTap: onAddresses,
          ),
        ],
      ],
    );
  }
}

class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key, required this.name});
  final String name;

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() send, String done) async {
    final app = ref.read(appStateProvider);
    setState(() => _busy = true);
    var ok = false;
    try {
      ok = await send();
    } catch (_) {}
    if (ok) {
      app.invalidateInFlightDashboardFetches();
      await app.fetchDashboardData();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ksSay(context, ok ? done : "The router didn't do that. Nothing changed.");
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final i = readConnections(
      app.dashboardData,
    ).where((c) => c.name == widget.name).firstOrNull;
    if (i == null) {
      return const KsPage(
        title: 'Connection',
        children: [KsNote('This connection is gone.')],
      );
    }
    final routerIp = app.currentRouterIp;
    final signsIn =
        routerIp != null &&
        routerIp.isNotEmpty &&
        (i.ipAddress == routerIp || i.gateway == routerIp);
    final peers =
        ((app.dashboardData?['wireguard'] as Map?)?[i.name] as Map?)?['peers']
            as Map?;
    return ConnectionView(
      connection: i,
      signsInThrough: signsIn,
      busy: _busy,
      peers: [
        for (final p in (peers?.values ?? const []).whereType<Map>())
          (
            p['name']?.toString() ??
                p['public_key']?.toString().substring(0, 8) ??
                'Peer',
            p['endpoint']?.toString() ?? 'No address',
          ),
      ],
      onReconnect: () => _run(
        () => app.restartWiredInterface(i.name, context: context),
        'Reconnected.',
      ),
      onSwitch: (on) => _run(
        () => app.updateWiredInterfaceStatus(i.name, on, context: context),
        on ? 'Turned on.' : 'Turned off.',
      ),
    );
  }
}

class ConnectionView extends StatelessWidget {
  const ConnectionView({
    super.key,
    required this.connection,
    this.signsInThrough = false,
    this.busy = false,
    this.peers = const [],
    this.onReconnect,
    this.onSwitch,
  });

  final NetworkInterface connection;

  final bool signsInThrough;
  final bool busy;

  final List<(String, String)> peers;
  final VoidCallback? onReconnect;
  final ValueChanged<bool>? onSwitch;

  @override
  Widget build(BuildContext context) {
    final i = connection;
    final rx = (i.stats['rx_bytes'] as num?)?.toInt() ?? 0;
    final tx = (i.stats['tx_bytes'] as num?)?.toInt() ?? 0;
    void copy(String v) {
      Clipboard.setData(ClipboardData(text: v));
      ksSay(context, 'Copied $v');
    }

    KsRow info(String title, String? value) => KsRow(
      title: title,
      subtitle: value,
      onTap: value == null ? null : () => copy(value),
      chevron: false,
    );

    return KsPage(
      title: connectionName(i.name, i.protocol),
      subtitle: protocolWords(i.protocol),
      children: [
        KsSwitchRow(
          title: i.isUp ? 'On' : 'Off',
          subtitle: i.isUp && i.uptime > 0
              ? 'Up for ${onlineFor(i.uptime)}'
              : null,
          value: i.isUp,
          busy: busy,
          onChanged: onSwitch == null
              ? null
              : (on) async {
                  if (!on &&
                      !await ksConfirm(
                        context,
                        title:
                            'Turn off ${connectionName(i.name, i.protocol)}?',
                        body: signsInThrough
                            ? 'Keystone reaches the router through this '
                                  'connection. Turning it off cuts this app '
                                  'off until you turn it back on another '
                                  'way, or restart the router.'
                            : 'Anything using it stops working until you '
                                  'turn it back on.',
                        action: 'Turn off',
                        danger: true,
                      )) {
                    return;
                  }
                  onSwitch!(on);
                },
        ),
        KsRow(
          title: 'Reconnect',
          subtitle: 'Drops and brings it back up, for a stuck connection',
          onTap: busy || onReconnect == null
              ? null
              : () async {
                  if (await ksConfirm(
                    context,
                    title: 'Reconnect?',
                    body: signsInThrough
                        ? 'Keystone loses the router for a moment while it '
                              'comes back.'
                        : 'It drops for a few seconds.',
                    action: 'Reconnect',
                  )) {
                    onReconnect!();
                  }
                },
        ),
        const KsSection('Details'),
        if (i.ipAddress != null)
          info(
            'Address',
            i.netmask == null ? i.ipAddress : '${i.ipAddress} / ${i.netmask}',
          ),
        if (i.gateway != null) info('Gateway', i.gateway),
        if (i.dnsServers.isNotEmpty)
          info('Name servers', i.dnsServers.join(', ')),
        if (i.ipv6Addresses?.isNotEmpty ?? false)
          info('IPv6', i.ipv6Addresses!.join('\n')),
        if (i.device.isNotEmpty) info('Port or device', i.device),
        if (rx + tx > 0)
          info('Data', '${sizeWords(rx)} down · ${sizeWords(tx)} up'),
        if (peers.isNotEmpty) ...[
          const KsSection('Connected to'),
          for (final (name, at) in peers) KsRow(title: name, subtitle: at),
        ],
      ],
    );
  }
}
