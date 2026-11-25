// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import '../models/wireless_info.dart';
import '../widgets/wireless_rollback_banner.dart';

enum JoinRule {
  anyone(''),
  onlyListed('allow'),
  allButListed('deny');

  const JoinRule(this.uci);
  final String uci;

  static JoinRule from(String? v) => switch (v?.toLowerCase()) {
    'allow' => onlyListed,
    'deny' => allButListed,
    _ => anyone,
  };

  String summary(int n) {
    final d = '$n device${n == 1 ? '' : 's'}';
    return switch (this) {
      anyone => 'Anyone with the password',
      onlyListed => n == 0 ? 'Nobody (the list is empty)' : 'Only $d',
      allButListed =>
        n == 0 ? 'Anyone with the password' : 'Everyone except $d',
    };
  }
}

String? parseMac(String input) {
  final hex = input.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
  if (hex.length != 12) return null;
  return [
    for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2),
  ].join(':').toUpperCase();
}

List<String> readMacList(Object? raw) {
  final items = raw is List
      ? raw.map((e) => e.toString())
      : (raw?.toString() ?? '').split(RegExp(r'\s+'));
  return [for (final m in items.map(parseMac).whereType<String>().toSet()) m];
}

class WifiAccessControlScreen extends ConsumerStatefulWidget {
  const WifiAccessControlScreen({super.key});

  @override
  ConsumerState<WifiAccessControlScreen> createState() =>
      _WifiAccessControlScreenState();
}

class _WifiAccessControlScreenState
    extends ConsumerState<WifiAccessControlScreen> {
  final _config = <String, Future<Map<String, dynamic>?>>{};

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final overview = WirelessOverview.fromDashboardData(
      app.dashboardData,
      isReviewerMode: app.reviewerModeEnabled,
    );
    const ap = {'ap', 'master'};
    final nets = [
      for (final r in overview.radios)
        for (final i in r.interfaces)
          if (ap.contains(i.mode.toLowerCase())) (r, i),
    ];
    return KsPage(
      title: 'Allow or block devices',
      subtitle: 'Choose who may join each Wi-Fi network',
      onRefresh: () async {
        setState(_config.clear);
        await app.fetchDashboardData(force: true);
      },
      children: [
        const WirelessRollbackBanner(),
        if (nets.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              "This router doesn't have a Wi-Fi network yet.",
              style: KeystoneType.body(ks.mu),
            ),
          ),
        for (final (r, i) in nets)
          FutureBuilder(
            future: _config[i.sectionName] ??= app.fetchWirelessSectionConfig(
              i.sectionName,
            ),
            builder: (context, snap) {
              final v = snap.data;
              final rule = v == null
                  ? null
                  : JoinRule.from(
                      v['macfilter']?.toString(),
                    ).summary(readMacList(v['maclist']).length);
              return KsRow(
                title: i.ssid.isEmpty ? '(no name)' : i.ssid,
                subtitle: [r.bandLabel, ?rule].join(' · '),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      fullscreenDialog: true,
                      builder: (_) =>
                          NetworkAccessScreen(radio: r, interface: i),
                    ),
                  );
                  if (mounted) setState(() => _config.remove(i.sectionName));
                },
              );
            },
          ),
        const SizedBox(height: 16),
        Text(
          'A device address can be faked, so this keeps out casual '
          "visitors, not someone determined. A good password matters more.",
          style: KeystoneType.caption(ks.mu),
        ),
      ],
    );
  }
}

typedef ListedDevice = ({String mac, String? name});

class NetworkAccessView extends StatelessWidget {
  const NetworkAccessView({
    super.key,
    required this.network,
    required this.rule,
    required this.devices,
    required this.onRule,
    required this.onRemove,
    required this.onAdd,
    this.thisPhone,
  });

  final String network;
  final JoinRule rule;
  final List<ListedDevice> devices;
  final ValueChanged<JoinRule> onRule;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

  final String? thisPhone;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KsSection('Who may join'),
        for (final r in JoinRule.values)
          RadioListTile<JoinRule>(
            value: r,
            // ignore: deprecated_member_use
            groupValue: rule,
            // ignore: deprecated_member_use
            onChanged: (v) => onRule(v!),
            contentPadding: EdgeInsets.zero,
            title: Text(switch (r) {
              JoinRule.anyone => 'Anyone with the password',
              JoinRule.onlyListed => 'Only the devices below',
              JoinRule.allButListed => 'Everyone except the devices below',
            }, style: KeystoneType.body(ks.tx)),
          ),
        if (rule == JoinRule.onlyListed)
          KsBanner(
            'Any device not listed is turned away from $network, '
            'including new phones and guests.',
          ),
        if (rule != JoinRule.anyone) ...[
          KsSection(rule == JoinRule.onlyListed ? 'Allowed' : 'Blocked'),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No devices yet.', style: KeystoneType.body(ks.mu)),
            ),
          for (final d in devices)
            KsRow(
              title: [
                d.name ?? d.mac,
                if (d.mac == thisPhone) '(this phone)',
              ].join(' '),
              subtitle: d.name == null ? null : d.mac,
              chevron: false,
              trailing: IconButton(
                tooltip: 'Take off the list',
                icon: Icon(Icons.close_rounded, color: ks.mu),
                onPressed: () => onRemove(d.mac),
              ),
            ),
          KsRow(
            title: 'Add a device',
            leading: Icon(Icons.add_rounded, color: ks.mu),
            onTap: onAdd,
          ),
        ],
      ],
    );
  }
}

class NetworkAccessScreen extends ConsumerStatefulWidget {
  const NetworkAccessScreen({
    super.key,
    required this.radio,
    required this.interface,
  });
  final WirelessRadio radio;
  final WirelessInterface interface;

  @override
  ConsumerState<NetworkAccessScreen> createState() =>
      _NetworkAccessScreenState();
}

class _NetworkAccessScreenState extends ConsumerState<NetworkAccessScreen> {
  bool _loading = true;
  bool _saving = false;
  JoinRule _rule = JoinRule.anyone;
  JoinRule _rule0 = JoinRule.anyone;
  String _filter0 = '';
  List<String> _macs = [];
  List<String> _macs0 = [];
  Client? _phone;

  String get _id => widget.interface.sectionName;
  bool get _changed =>
      _rule != _rule0 ||
      _macs.toSet().difference(_macs0.toSet()).isNotEmpty ||
      _macs0.toSet().difference(_macs.toSet()).isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = ref.read(appStateProvider);
    final v = await app.fetchWirelessSectionConfig(_id);
    final local = await SelfDeviceGuard.getLocalDeviceAddresses();
    if (!mounted) return;
    setState(() {
      _filter0 = v?['macfilter']?.toString() ?? '';
      _rule = _rule0 = JoinRule.from(_filter0);
      _macs = readMacList(v?['maclist']);
      _macs0 = List.of(_macs);
      _phone = app.clients
          .where(
            (c) =>
                local.contains(c.ipAddress.toLowerCase().trim()) ||
                local.any(
                  (a) =>
                      SelfDeviceGuard.normalizeMac(a) ==
                      SelfDeviceGuard.normalizeMac(c.macAddress),
                ),
          )
          .firstOrNull;
      _loading = false;
    });
  }

  String? get _phoneMac => _phone == null ? null : parseMac(_phone!.macAddress);

  bool get _phoneHere {
    final p = _phone;
    if (p == null || !p.isConnected) return false;
    if (p.connectionType != ConnectionType.wireless) return false;
    final ssid = p.ssid?.trim().toLowerCase();
    if (ssid != null && ssid.isNotEmpty) {
      return ssid == widget.interface.ssid.trim().toLowerCase();
    }
    final ifc = p.wirelessIface?.trim().toLowerCase();
    return ifc == widget.interface.ifName.toLowerCase() || ifc == _id;
  }

  Future<void> _add() async {
    final app = ref.read(appStateProvider);
    final known = [
      for (final c in app.clients)
        if (parseMac(c.macAddress) case final m? when !_macs.contains(m))
          (mac: m, name: c.displayName),
    ];
    final typed = TextEditingController();
    final mac = await ksSheet<String>(context, (c) {
      final ks = c.ks;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Add a device', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 12),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final k in known)
                  KsRow(
                    title: k.name,
                    subtitle: k.mac,
                    chevron: false,
                    onTap: () => Navigator.pop(c, k.mac),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          KsField(
            label: 'Or type its address',
            controller: typed,
            hint: 'AA:BB:CC:DD:EE:FF',
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final m = parseMac(typed.text);
              if (m == null) {
                ksSay(c, "That isn't a device address.");
                return;
              }
              Navigator.pop(c, m);
            },
            child: const Text('Add'),
          ),
        ],
      );
    });
    typed.dispose();
    if (mac != null && mounted && !_macs.contains(mac)) {
      setState(() => _macs = [..._macs, mac]);
    }
  }

  Future<void> _save() async {
    final me = _phoneMac;
    var macs = List.of(_macs);
    if (_phoneHere && me != null) {
      final out =
          (_rule == JoinRule.onlyListed && !macs.contains(me)) ||
          (_rule == JoinRule.allButListed && macs.contains(me));
      if (out) {
        final keep = await ksConfirm(
          context,
          title: 'Keep this phone connected?',
          body:
              'This phone is on ${widget.interface.ssid}. As it stands, '
              'saving would disconnect it and Keystone would lose the router.',
          action: _rule == JoinRule.onlyListed
              ? 'Add this phone'
              : 'Take this phone off',
        );
        if (!keep || !mounted) return;
        macs = _rule == JoinRule.onlyListed
            ? [...macs, me]
            : macs.where((m) => m != me).toList();
      }
    }
    setState(() => _saving = true);
    final ok = await ref
        .read(appStateProvider)
        .applyWifiAccessControl(
          newMaclistByIface: {_id: macs},
          newMacfilterByIface: {_id: _rule.uci},
          priorMaclistSnapshot: {_id: _macs0},
          priorMacfilterSnapshot: {_id: _filter0},
          context: context,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
    } else {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final canEdit =
        (app.capabilities?.hasUciWriteAccess ?? true) &&
        app.isAdministrativeUser;
    String? nameOf(String mac) => app.clients
        .where((c) => parseMac(c.macAddress) == mac)
        .firstOrNull
        ?.displayName;
    final name = widget.interface.ssid;

    return PopScope(
      canPop: !_saving && !app.isAccessControlPendingConfirmation,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _saving) return;
        final canExit = await LuciGuardrail.confirmStagedChangesOrExit(
          context,
          app,
        );
        if (canExit && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: ks.bg,
        appBar: AppBar(
          backgroundColor: ks.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ks.tx,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: (_loading || _saving || !_changed || !canEdit)
                    ? null
                    : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              KsTitle(
                name.isEmpty ? '(no name)' : name,
                subtitle: widget.radio.bandLabel,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                NetworkAccessView(
                  network: name,
                  rule: _rule,
                  devices: [for (final m in _macs) (mac: m, name: nameOf(m))],
                  thisPhone: _phoneMac,
                  onRule: (r) => setState(() => _rule = r),
                  onRemove: (m) => setState(
                    () => _macs = _macs.where((x) => x != m).toList(),
                  ),
                  onAdd: _add,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
