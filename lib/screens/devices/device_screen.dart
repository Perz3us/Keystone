import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/noobwrt/bandix/bandix_rates.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';
import 'package:yet_another_luci_app/screens/devices/device_view.dart';
import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';
import 'package:yet_another_luci_app/widgets/ban_wireless_client_dialog.dart';
import 'package:yet_another_luci_app/widgets/client_speed_limit_dialog.dart';
import 'package:yet_another_luci_app/widgets/device_network_access_card.dart';
import 'package:yet_another_luci_app/services/device_discovery.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key, required this.mac, this.fallback});

  final String mac;

  final Client? fallback;

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  final _samples = <double>[];
  Timer? _sampler;
  ControlState _pause = ControlState.idle;
  ControlState _limit = ControlState.idle;
  bool _pauseTarget = false;

  Future<void> _apply(
    Future<bool> Function() send,
    void Function(ControlState) set,
  ) async {
    setState(() => set(ControlState.applying));
    var ok = false;
    try {
      ok = await send();
    } catch (_) {}
    if (!mounted) return;
    setState(() => set(ok ? ControlState.idle : ControlState.failed));
  }

  @override
  void initState() {
    super.initState();
    _sampler = Timer.periodic(const Duration(seconds: 2), (_) {
      final c = _client();
      if (c == null || !mounted) return;
      setState(() {
        _samples.add(deviceMbps(c));
        if (_samples.length > 30) _samples.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _sampler?.cancel();
    super.dispose();
  }

  Client? _client() {
    final app = ref.read(appStateProvider);
    final mac = ClientNamingHelper.normalizeMac(widget.mac);
    final c = app.clients
        .where((c) => ClientNamingHelper.normalizeMac(c.macAddress) == mac)
        .firstOrNull;
    if (c == null) return widget.fallback;
    final rates = ref.read(bandixRatesProvider).valueOrNull;
    return withBandix([c], rates).first;
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    ref.watch(bandixRatesProvider);
    final c = _client();
    final mac = ClientNamingHelper.normalizeMac(widget.mac);

    final limit = c == null ? null : app.getClientSpeedLimit(c.macAddress);
    final limitLine = limit != null && limit.isEffectivelyRestricted
        ? '${_num(limit.downloadValue)} ${limit.downloadUnit} down · '
              '${_num(limit.uploadValue)} up'
        : null;

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Devices', style: KeystoneType.body(ks.mu)),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Device type',
              icon: Icon(ClientNamingHelper.getDeviceIcon(c), color: ks.mu),
              onPressed: () => _pickKind(c),
            ),
          if (c != null)
            TextButton(
              onPressed: () => _rename(c),
              child: Text('Rename', style: KeystoneType.body(ks.mu)),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: c == null
            ? Center(
                child: Text(
                  'This device has left the network.',
                  style: KeystoneType.body(ks.mu),
                ),
              )
            : DeviceView(
                name: c.displayName,
                line: deviceLine(c),
                weak: isWeak(c),
                wifi: c.connectionType == ConnectionType.wireless,
                mbps: deviceMbps(c),
                usedBytes: (c.rxBytes ?? 0) + (c.txBytes ?? 0),
                samples: List.of(_samples),
                paused: app.pausedInternetMacs
                    .map(ClientNamingHelper.normalizeMac)
                    .contains(mac),
                limitLine: limitLine,
                ip: c.ipAddress,
                mac: c.macAddress,
                pauseState: _pause,
                limitState: _limit,
                onPause: (v) {
                  _pauseTarget = v;
                  _apply(
                    () => app.pauseClientInternet(c.macAddress, pause: v),
                    (s) => _pause = s,
                  );
                },
                onRetryPause: () => _apply(
                  () => app.pauseClientInternet(
                    c.macAddress,
                    pause: _pauseTarget,
                  ),
                  (s) => _pause = s,
                ),
                onLimit: (v) => v
                    ? ClientSpeedLimitDialog.show(
                        context,
                        client: c,
                        initialLimit: limit,
                      )
                    : _apply(
                        () => app.removeClientSpeedLimit(c.macAddress),
                        (s) => _limit = s,
                      ),
                onRetryLimit: () => _apply(
                  () => app.removeClientSpeedLimit(c.macAddress),
                  (s) => _limit = s,
                ),
                onSchedule: () => DeviceNetworkAccessCard.showAsBottomSheet(
                  context,
                  client: c,
                ),
                onBlock: () => _block(c),
                blocked: app.isWirelessBanned(c.macAddress),
                extraDetails: _details(c),
                onForgetAddress: c.isStaticLease ? () => _forget(c) : null,
                onWhy: () => _why(ks),
              ),
      ),
    );
  }

  static String _span(int seconds) {
    if (seconds >= 86400) {
      return '${seconds ~/ 86400} d ${seconds % 86400 ~/ 3600} h';
    }
    if (seconds >= 3600) {
      return '${seconds ~/ 3600} h ${seconds % 3600 ~/ 60} min';
    }
    return '${(seconds / 60).ceil()} min';
  }

  List<(String, String)> _details(Client c) {
    String? v(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    return [
      if (v(c.vendor) case final s?) ('Maker', s),
      if (DeviceDiscovery.instance.kindFor(c.ipAddress) case final k?)
        ('Identifies as', k.label),
      if (v(c.dnsName) case final s? when s != c.displayName)
        ('Name on the network', s),
      if (c.ipv6Addresses
              ?.where((a) => !a.toLowerCase().startsWith('fe80'))
              .toList()
          case final l? when l.isNotEmpty)
        ('IPv6', l.join('\n')),
      if (v(c.ssid) case final s?) ('Wi-Fi network', s),
      if (c.isDumbApClient && v(c.apName) != null)
        ('Connected through', c.apName!),
      if (c.signalDbm case final d?) ('Signal', '$d dBm'),
      if (c.connectedTime case final t? when t > 0) ('Connected for', _span(t)),
      if (c.rxBytes != null || c.txBytes != null)
        ('Data', '${_size(c.rxBytes ?? 0)} down · ${_size(c.txBytes ?? 0)} up'),
      (
        'Lease',
        c.isStaticLease
            ? 'Fixed${v(c.staticLeaseName) == null ? '' : ' as ${c.staticLeaseName}'}'
            : c.leaseTime != null && c.leaseTime! > 0
            ? 'Lease ends in ${_span(c.leaseTime!)}'
            : 'Given by the router',
      ),
    ];
  }

  static String _size(int b) => b >= 1e9
      ? '${(b / 1e9).toStringAsFixed(1)} GB'
      : b >= 1e6
      ? '${(b / 1e6).toStringAsFixed(0)} MB'
      : '${(b / 1e3).toStringAsFixed(0)} KB';

  Future<void> _forget(Client c) async {
    final ks = context.ks;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text(
          'Forget the fixed address?',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        content: Text(
          '${c.displayName} keeps working and gets whatever address is free '
          'next time it connects. Its name here goes back to what the device '
          'calls itself.',
          style: KeystoneType.body(ks.tx2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text('Forget', style: TextStyle(color: ks.bad)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final app = ref.read(appStateProvider);
    final mapping = app.findStaticLeaseByMac(c.macAddress);
    final good = await app.deleteStaticLease(
      macAddress: c.macAddress,
      targetIp: (mapping?.ipAddress ?? c.ipAddress) == 'N/A'
          ? null
          : mapping?.ipAddress ?? c.ipAddress,
      hostname: mapping?.hostname ?? c.staticLeaseName,
      duid: (mapping?.duid ?? '').isEmpty || mapping?.duid == 'N/A'
          ? null
          : mapping!.duid,
      context: context,
    );
    if (good) {
      app.invalidateStaticLeasesCache();
      await app.fetchClientsForSelectedRouter();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The router didn't save that. Nothing was changed."),
        ),
      );
    }
  }

  void _rename(Client c) {
    final app = ref.read(appStateProvider);
    final mappings = DhcpDnsOverview.fromDashboardData(
      app.dashboardData,
      isReviewerMode: app.reviewerModeEnabled,
    ).staticMappings;
    final mac = ClientNamingHelper.normalizeMac(c.macAddress);
    ksFormRoute<void>(
      context,
      AddStaticLeaseDialog(
        client: c,
        allClients: app.clients,
        existingMapping: mappings
            .where((m) => ClientNamingHelper.normalizeMac(m.macAddress) == mac)
            .firstOrNull,
        onSaved: app.fetchClientsForSelectedRouter,
      ),
    );
  }

  void _block(Client c) {
    final app = ref.read(appStateProvider);
    ksSheet<void>(
      context,
      (_) => BanWirelessClientDialog(
        macAddress: c.macAddress,
        displayName: c.displayName,
        ipAddress: c.ipAddress,
        ssid: c.ssid,
        iface: c.wirelessIface,
        isAlreadyBanned: app.isWirelessBanned(c.macAddress),
        onUnbanConfirmed: () async {
          await app.unbanWirelessClient(c.macAddress, context: context);
        },
        onBanConfirmed: (seconds) async {
          await app.banWirelessClient(
            c.macAddress,
            iface: c.wirelessIface,
            banTimeSeconds: seconds,
            context: context,
          );
        },
      ),
    );
  }

  void _pickKind(Client c) {
    final ks = context.ks;
    final picked = DeviceKindStore.instance.kindOf(c.macAddress);
    ksSheet<void>(
      context,
      (s) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'What is ${c.displayName}?',
            style: KeystoneType.sheetTitle(ks.tx),
          ),
          const SizedBox(height: 8),
          KsRow(
            title: 'Work it out',
            subtitle: 'From its name and what it says about itself',
            trailing: picked == null ? Icon(Icons.check, color: ks.ac) : null,
            onTap: () {
              DeviceKindStore.instance.set(c.macAddress, null);
              Navigator.pop(s);
            },
          ),
          for (final k in DeviceKind.values)
            KsRow(
              leading: Icon(k.icon, color: ks.tx2),
              title: k.label,
              trailing: picked == k ? Icon(Icons.check, color: ks.ac) : null,
              onTap: () {
                DeviceKindStore.instance.set(c.macAddress, k);
                Navigator.pop(s);
              },
            ),
        ],
      ),
    );
  }

  void _why(KeystoneColors ks) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: ks.sheet,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Why the signal is weak', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 10),
          Text(
            'The device is far from the router, or walls and appliances are '
            'in the way. Moving either closer, or keeping the router up high '
            'and out in the open, usually helps.',
            style: KeystoneType.body(ks.tx2),
          ),
        ],
      ),
    ),
  );
}
