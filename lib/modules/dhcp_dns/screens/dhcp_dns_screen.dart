// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/screens/devices/device_screen.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/dhcp_dns_info.dart';
import '../models/dnsmasq_service_result.dart';

class DhcpDnsScreen extends ConsumerStatefulWidget {
  const DhcpDnsScreen({super.key});

  @override
  ConsumerState<DhcpDnsScreen> createState() => _DhcpDnsScreenState();
}

class _DhcpDnsScreenState extends ConsumerState<DhcpDnsScreen> {
  bool _restarting = false;

  Future<void> _refresh() async {
    final app = ref.read(appStateProvider);
    await Future.wait([
      app.fetchDashboardData(),
      app.fetchClientsForSelectedRouter(),
    ]);
  }

  Future<void> _restart() async {
    if (!await ksConfirm(
      context,
      title: 'Restart the address service?',
      body:
          'Names stop working for a second or two. Devices keep their '
          'addresses.',
      action: 'Restart',
    )) {
      return;
    }
    final app = ref.read(appStateProvider);
    final r = app.selectedRouter;
    final api = app.apiService;
    if (r == null || api == null || !mounted) return;
    setState(() => _restarting = true);
    String msg;
    try {
      final res = await api.reloadDnsmasq(
        r.ipAddress,
        app.sysauth ?? '',
        r.useHttps,
        context: context,
      );
      msg = res.isSuccess
          ? 'Restarted.'
          : res.status == DnsmasqServiceStatus.notRunning
          ? "The address service isn't running on this router."
          : "That didn't work: ${res.message}";
    } catch (e) {
      msg = "That didn't work: $e";
    }
    if (!mounted) return;
    setState(() => _restarting = false);
    ksSay(context, msg);
  }

  void _addFixed({DhcpStaticMapping? existing}) {
    final app = ref.read(appStateProvider);
    ksFormRoute<void>(
      context,
      AddStaticLeaseDialog(
        macAddress: existing?.macAddress,
        initialIp: existing?.ipAddress,
        initialHostname: existing?.hostname,
        existingMapping: existing,
        allClients: app.clients,
        onSaved: _refresh,
      ),
    );
  }

  void _openDevice(String mac, String name, String ip) {
    final c = Client(
      ipAddress: ip,
      macAddress: mac,
      hostname: name,
      isConnected: false,
      connectionType: ConnectionType.unknown,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceScreen(mac: mac, fallback: c),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final data = Map<String, dynamic>.from(app.dashboardData ?? {});
    data['clients'] = [
      for (final c in app.clients)
        {
          'macAddress': c.macAddress,
          'ipAddress': c.ipAddress,
          'name': c.displayName,
          'isStaticLease': c.isStaticLease,
          'isConnected': c.isConnected,
        },
    ];
    final o = DhcpDnsOverview.fromDashboardData(
      data,
      isReviewerMode: app.reviewerModeEnabled,
    );
    return DhcpDnsView(
      overview: o,
      nameFor: (mac) {
        final m = ClientNamingHelper.normalizeMac(mac);
        return app.clients
            .where((c) => ClientNamingHelper.normalizeMac(c.macAddress) == m)
            .firstOrNull
            ?.displayName;
      },
      restarting: _restarting,
      onRefresh: _refresh,
      onRestart: _restart,
      onAddFixed: () => _addFixed(),
      onFixed: (m) => _addFixed(existing: m),
      onLease: (l) => _openDevice(l.macAddress, l.hostname, l.ipAddress),
    );
  }
}

class DhcpDnsView extends StatelessWidget {
  const DhcpDnsView({
    super.key,
    required this.overview,
    this.nameFor,
    this.restarting = false,
    this.onRefresh,
    this.onRestart,
    this.onAddFixed,
    this.onFixed,
    this.onLease,
  });

  final DhcpDnsOverview overview;

  final String? Function(String mac)? nameFor;
  final bool restarting;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onRestart;
  final VoidCallback? onAddFixed;
  final ValueChanged<DhcpStaticMapping>? onFixed;
  final ValueChanged<DhcpLease>? onLease;

  static String _ends(int s) => s <= 0
      ? 'Fixed'
      : s >= 86400
      ? 'Ends in ${s ~/ 86400} d ${s % 86400 ~/ 3600} h'
      : s >= 3600
      ? 'Ends in ${s ~/ 3600} h ${s % 3600 ~/ 60} min'
      : 'Ends in ${(s / 60).ceil()} min';

  String _name(String mac, String hostname) {
    final n = nameFor?.call(mac);
    if (n != null && n.isNotEmpty) return n;
    return hostname.isEmpty || hostname == '*' ? mac : hostname;
  }

  @override
  Widget build(BuildContext context) {
    final c = overview.dnsConfig;
    final summary = overview.resolvedDnsSummary;
    final upstream = summary != null && summary.startsWith('ISP')
        ? 'Your internet provider'
        : summary ??
              (c.upstreamDnsServers.isEmpty
                  ? 'Your internet provider'
                  : c.upstreamDnsServers.join(', '));
    final leases = overview.activeLeases.where((l) => !l.isStatic).toList()
      ..sort((a, b) => a.ipAddress.compareTo(b.ipAddress));
    return KsPage(
      title: 'Addresses and DNS',
      subtitle: 'How devices get an address, and who looks up names',
      onRefresh: onRefresh,
      children: [
        const KsSection('Names'),
        KsRow(title: 'Looked up by', subtitle: upstream),
        if (overview.realDnsEndpoint?.isNotEmpty ?? false)
          KsRow(title: 'Encrypted through', subtitle: overview.realDnsEndpoint),
        if (c.localDomain.isNotEmpty)
          KsRow(title: 'Home names end in', subtitle: '.${c.localDomain}'),
        KsRow(
          title: 'Protection from rebinding',
          subtitle: c.rebindProtection
              ? 'On: websites can\'t point names at your home network'
              : 'Off',
        ),
        KsRow(
          title: restarting
              ? 'Restarting the address service…'
              : 'Restart the address service',
          subtitle: 'Try this when names stop working',
          onTap: restarting ? null : onRestart,
        ),
        KsSection(
          'Fixed addresses',
          trailing: onAddFixed == null
              ? null
              : TextButton(onPressed: onAddFixed, child: const Text('Add')),
        ),
        if (overview.staticMappings.isEmpty)
          const KsNote(
            'No device has a fixed address. Give one from the device\'s '
            'page, or tap Add.',
          )
        else
          for (final m in overview.staticMappings)
            KsRow(
              title: _name(m.macAddress, m.hostname),
              subtitle: '${m.ipAddress} · ${m.macAddress}',
              onTap: onFixed == null ? null : () => onFixed!(m),
            ),
        KsSection('Given out now · ${leases.length}'),
        if (leases.isEmpty)
          const KsNote('No device has asked for an address yet.')
        else
          for (final l in leases)
            KsRow(
              title: _name(l.macAddress, l.hostname),
              subtitle: '${l.ipAddress} · ${_ends(l.expirySeconds)}',
              onTap: onLease == null ? null : () => onLease!(l),
            ),
      ],
    );
  }
}
