// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/firewall_security/screens/firewall_security_screen.dart'
    show zoneName;
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

class AdvancedPortForwardDialog extends ConsumerStatefulWidget {
  final FirewallPortForwarding? initialPortForward;
  final FirewallOverview overview;

  const AdvancedPortForwardDialog({
    super.key,
    this.initialPortForward,
    required this.overview,
  });

  static Future<bool?> show(
    BuildContext context, {
    FirewallPortForwarding? initialPortForward,
    required FirewallOverview overview,
  }) {
    return ksFormRoute<bool>(
      context,
      AdvancedPortForwardDialog(
        initialPortForward: initialPortForward,
        overview: overview,
      ),
    );
  }

  @override
  ConsumerState<AdvancedPortForwardDialog> createState() =>
      _AdvancedPortForwardDialogState();
}

class _AdvancedPortForwardDialogState
    extends ConsumerState<AdvancedPortForwardDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _srcPortController;
  late final TextEditingController _destIpController;
  late final TextEditingController _destPortController;
  late final TextEditingController _srcIpController;

  late String _srcZone;
  late String _destZone;
  late String _proto;
  late String _family;
  late bool _enabled;
  late bool _reflection;

  bool _isSubmitting = false;
  String? _validationError;

  bool get _isEditing => widget.initialPortForward != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialPortForward;
    _nameController = TextEditingController(text: init?.name ?? '');
    _srcPortController = TextEditingController(text: init?.srcPort ?? '');
    _destIpController = TextEditingController(text: init?.destIp ?? '');
    _destPortController = TextEditingController(text: init?.destPort ?? '');
    _srcIpController = TextEditingController(text: init?.srcIp ?? '');

    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    if (init != null && availableZones.contains(init.srcZone)) {
      _srcZone = init.srcZone;
    } else if (availableZones.contains('wan')) {
      _srcZone = 'wan';
    } else {
      _srcZone = availableZones.isNotEmpty ? availableZones.first : 'wan';
    }

    final lanCandidate = widget.overview.primaryLanZoneName ?? 'lan';
    if (init != null && availableZones.contains(init.destZone)) {
      _destZone = init.destZone;
    } else if (availableZones.contains(lanCandidate)) {
      _destZone = lanCandidate;
    } else if (availableZones.contains('lan')) {
      _destZone = 'lan';
    } else {
      _destZone = availableZones.isNotEmpty ? availableZones.first : 'lan';
    }

    _proto = init?.proto.toLowerCase() ?? 'tcp';
    if (_proto == 'tcpudp') _proto = 'tcp udp';

    _family = init?.family.toLowerCase() ?? 'any';
    _enabled = init?.enabled ?? true;
    _reflection = init?.reflection ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _srcPortController.dispose();
    _destIpController.dispose();
    _destPortController.dispose();
    _srcIpController.dispose();
    super.dispose();
  }

  bool _isValidPortSpec(String? portSpec) {
    if (portSpec == null || portSpec.trim().isEmpty) return false;
    final clean = portSpec.trim().toLowerCase();
    if (clean == 'any' || clean == 'all' || clean == '*') return true;
    final parts = clean.split(',');
    for (final part in parts) {
      final token = part.trim();
      if (token.isEmpty) return false;
      if (token.contains('-')) {
        final bounds = token.split('-');
        if (bounds.length != 2) return false;
        final s = int.tryParse(bounds[0].trim());
        final e = int.tryParse(bounds[1].trim());
        if (s == null || e == null || s < 1 || e > 65535 || s > e) return false;
      } else if (token.contains(':')) {
        final bounds = token.split(':');
        if (bounds.length != 2) return false;
        final s = int.tryParse(bounds[0].trim());
        final e = int.tryParse(bounds[1].trim());
        if (s == null || e == null || s < 1 || e > 65535 || s > e) return false;
      } else {
        final p = int.tryParse(token);
        if (p == null || p < 1 || p > 65535) return false;
      }
    }
    return true;
  }

  NatReflectionCapabilityResult _evaluateReflection() {
    final appState = ref.read(appStateProvider);
    final rawDump = appState.dashboardData?['interfaceDump'];
    final rawDevices = appState.dashboardData?['networkDevices'];
    FirewallTopologyFacts? topologyFacts;
    if (rawDump is Map<String, dynamic>) {
      topologyFacts = FirewallTopologyFacts.fromNetworkDump(
        rawDump,
        networkDevices: rawDevices is Map<String, dynamic> ? rawDevices : null,
      );
    }

    final rawUci = widget.initialPortForward?.rawUciValues;
    final rawRz = rawUci?['reflection_zone'];
    final List<String> rzList = [];
    if (rawRz is List) {
      rzList.addAll(rawRz.map((e) => e.toString()));
    } else if (rawRz is String && rawRz.trim().isNotEmpty) {
      rzList.addAll(rawRz.trim().split(RegExp(r'\s+')));
    }

    final redirectCtx = NatReflectionRedirectContext(
      srcZone: _srcZone,
      destZone: _destZone,
      destIp: _destIpController.text.trim(),
      family: _family,
      existingReflection: widget.initialPortForward?.rawUciValues['reflection']
          ?.toString(),
      existingReflectionSrc: rawUci?['reflection_src']?.toString(),
      existingReflectionZones: rzList,
    );

    return FirewallValidator.evaluateNatReflectionCapability(
      overview: widget.overview,
      capabilities: appState.capabilities,
      redirectContext: redirectCtx,
      topologyFacts: topologyFacts,
    );
  }

  void _pickClientIp(List<Client> clients) async {
    final validClients = clients
        .where((c) => c.ipAddress.trim().isNotEmpty && c.ipAddress != 'N/A')
        .toList();
    if (validClients.isEmpty) return;

    final selected = await ksSheet<Client>(context, (c) {
      final ks = c.ks;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pick a device', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final cl in validClients)
                  KsRow(
                    title: cl.displayName,
                    subtitle: cl.ipAddress,
                    chevron: false,
                    onTap: () => Navigator.pop(c, cl),
                  ),
              ],
            ),
          ),
        ],
      );
    });

    if (selected != null) {
      setState(() {
        _destIpController.text = selected.ipAddress;
      });
    }
  }

  Future<void> _handleSubmit() async {
    final loc = AppLocalizations.of(context);
    setState(() => _validationError = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;
    if (!canModify) {
      setState(() {
        _validationError =
            loc?.firewallReadOnlyNotice ??
            'Read-only access: Changes cannot be applied on this router account.';
      });
      return;
    }

    final name = _nameController.text.trim();
    final srcPort = _srcPortController.text.trim();
    final destIp = _destIpController.text.trim();
    final destPort = _destPortController.text.trim().isNotEmpty
        ? _destPortController.text.trim()
        : srcPort;
    final srcIp = _srcIpController.text.trim();

    final reflectionEval = _evaluateReflection();
    final effectiveReflection =
        reflectionEval.status == NatReflectionStatus.supported
        ? _reflection
        : false;

    final preservedRawValues = Map<String, dynamic>.from(
      widget.initialPortForward?.rawUciValues ?? const {},
    );

    final candidate = FirewallPortForwarding(
      sectionKey: widget.initialPortForward?.sectionKey ?? '',
      name: name,
      srcZone: _srcZone,
      srcPort: srcPort,
      destZone: _destZone,
      destIp: destIp,
      destPort: destPort,
      proto: _proto,
      srcIp: srcIp.isNotEmpty ? srcIp : null,
      reflection: effectiveReflection,
      enabled: _enabled,
      family: _family,
      target: 'DNAT',
      rawUciValues: preservedRawValues,
    );

    final conflict = FirewallValidator.checkPortForwardConflict(
      candidate,
      widget.overview.portForwards,
    );
    if (conflict.hasConflict) {
      setState(() {
        _validationError = loc?.firewallConflictPortInUse ?? conflict.reason;
      });
      return;
    }

    final customMgmtPorts = SelfDeviceGuard.getDiscoveredManagementPorts(
      appState.selectedRouter?.id ?? appState.selectedRouter?.ipAddress,
    );
    final safety = FirewallValidator.checkManagementPortSafety(
      candidate,
      routerLanIp: appState.selectedRouter?.ipAddress,
      customManagementPorts: customMgmtPorts,
    );
    if (safety.isUnsafe) {
      setState(() {
        _validationError =
            loc?.firewallConflictManagementPort ??
            'This port is reserved for router administration. Exposing it externally is not permitted.';
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final bool success;
      if (_isEditing) {
        success = await appState.updateFirewallPortForward(
          candidate,
          context: mounted ? context : null,
        );
      } else {
        success = await appState.addFirewallPortForward(
          candidate,
          context: mounted ? context : null,
        );
      }

      if (!mounted) return;

      if (success) {
        ksSay(
          context,
          _isEditing
              ? 'Port forward "$name" updated.'
              : 'Port forward "$name" created.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to save port forwarding configuration.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _validationError = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final appState = ref.watch(appStateProvider);
    final supportsIpv6 =
        appState.capabilities?.supportsIpv6InternetFirewall ?? false;
    final zones = widget.overview.zones.map((z) => z.name).toList();
    if (!zones.contains(_srcZone) && zones.isNotEmpty) _srcZone = zones.first;
    if (!zones.contains(_destZone) && zones.isNotEmpty) {
      _destZone = zones.first;
    }
    final reflection = _evaluateReflection();
    final canReflect = reflection.status == NatReflectionStatus.supported;
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    final zoneOptions = [for (final z in zones) (z, cap(zoneName(z)))];

    return KsFormPage(
      title: _isEditing ? 'Change the open port' : 'Open a port by hand',
      subtitle: 'Every detail of one port forward',
      action: _isEditing ? 'Save' : 'Add',
      busy: _isSubmitting,
      formKey: _formKey,
      onAction: _handleSubmit,
      children: [
        KsField(
          label: 'Name',
          controller: _nameController,
          hint: 'For example Camera',
          validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
        ),
        const KsSection('From'),
        KsChoice<String>(
          label: 'Comes in from',
          value: _srcZone,
          options: zoneOptions,
          onChanged: (v) => setState(() => _srcZone = v),
        ),
        KsField(
          label: 'Outside port',
          controller: _srcPortController,
          hint: '80, or 80,443, or 8000-8010',
          keyboardType: TextInputType.text,
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return 'Enter a port.';
            return _isValidPortSpec(v) ? null : 'Use ports from 1 to 65535.';
          },
        ),
        KsField(
          label: 'Only from this address (optional)',
          controller: _srcIpController,
          hint: '203.0.113.50 or 203.0.113.0/24',
          help: 'Empty lets in anyone on the internet',
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty || FirewallValidator.isValidIpOrCidr(t)) return null;
            return 'Use an address like 203.0.113.50.';
          },
        ),
        const KsSection('To'),
        KsChoice<String>(
          label: 'Goes to',
          value: _destZone,
          options: zoneOptions,
          onChanged: (v) => setState(() => _destZone = v),
        ),
        KsField(
          label: 'Device address',
          controller: _destIpController,
          hint: '192.168.1.100',
          onChanged: (_) => setState(() {}),
          suffix: appState.clients.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Pick a device',
                  icon: Icon(Icons.devices_rounded, color: ks.mu),
                  onPressed: () => _pickClientIp(appState.clients),
                ),
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'Enter the device address.';
            final v4 = FirewallValidator.isValidIpv4(t);
            final v6 = Ipv6AddressUtil.tryParse(t) != null;
            if (!v4 && !v6) return 'Use an address like 192.168.1.100.';
            if (_family == 'ipv4' && !v4) return 'This needs an IPv4 address.';
            if (_family == 'ipv6' && !v6) return 'This needs an IPv6 address.';
            return null;
          },
        ),
        KsField(
          label: 'Device port (optional)',
          controller: _destPortController,
          hint: 'Same as outside',
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            return _isValidPortSpec(v) ? null : 'Use ports from 1 to 65535.';
          },
        ),
        const KsSection('Details'),
        KsChoice<String>(
          label: 'Kind of traffic',
          value: _proto,
          options: const [
            ('tcp', 'TCP'),
            ('udp', 'UDP'),
            ('tcp udp', 'TCP and UDP'),
            ('any', 'Any'),
          ],
          onChanged: (v) => setState(() => _proto = v),
        ),
        KsChoice<String>(
          label: 'Address type',
          value: _family,
          help: supportsIpv6 ? null : "This router's firewall can't do IPv6",
          options: [
            ('any', 'IPv4 and IPv6'),
            ('ipv4', 'IPv4 only'),
            if (supportsIpv6 || _family == 'ipv6') ('ipv6', 'IPv6 only'),
          ],
          onChanged: (v) => setState(() => _family = v),
        ),
        KsSwitchRow(
          title: 'Reach it from home by the outside address',
          subtitle: canReflect
              ? 'Devices at home can use the same address as outsiders'
              : reflection.userFacingReason,
          value: canReflect && _reflection,
          onChanged: canReflect ? (v) => setState(() => _reflection = v) : null,
        ),
        KsSwitchRow(
          title: 'On',
          subtitle: 'Turn off to keep it without using it',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        if (_validationError != null) KsBanner(_validationError!, bad: true),
      ],
    );
  }
}
