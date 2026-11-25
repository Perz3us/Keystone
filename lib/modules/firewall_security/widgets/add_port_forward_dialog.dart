// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

enum PortForwardPreset { plex, minecraft, webServer, custom }

class AddPortForwardDialog extends ConsumerStatefulWidget {
  const AddPortForwardDialog({super.key});

  static Future<bool?> show(BuildContext context) =>
      ksFormRoute<bool>(context, const AddPortForwardDialog());

  @override
  ConsumerState<AddPortForwardDialog> createState() =>
      _AddPortForwardDialogState();
}

class _AddPortForwardDialogState extends ConsumerState<AddPortForwardDialog> {
  final _formKey = GlobalKey<FormState>();

  PortForwardPreset _selectedPreset = PortForwardPreset.plex;
  bool _useManualIp = false;

  Client? _selectedClient;
  final _manualIpController = TextEditingController();
  final _customServiceNameController = TextEditingController();
  final _customExternalPortController = TextEditingController();
  final _customInternalPortController = TextEditingController();
  String _customProto = 'tcp';

  bool _isSubmitting = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    final appState = ref.read(appStateProvider);
    final clients = appState.clients;
    final validClients = clients
        .where((c) => FirewallValidator.isValidIpv4(c.ipAddress))
        .toList();

    if (validClients.isNotEmpty) {
      _selectedClient = validClients.first;
      _useManualIp = false;
    } else {
      _useManualIp = true;
    }
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    _customServiceNameController.dispose();
    _customExternalPortController.dispose();
    _customInternalPortController.dispose();
    super.dispose();
  }

  String _getPresetName(AppLocalizations? loc, PortForwardPreset preset) {
    switch (preset) {
      case PortForwardPreset.plex:
        return loc?.firewallWizardPresetPlex ?? 'Plex Media Server';
      case PortForwardPreset.minecraft:
        return loc?.firewallWizardPresetMinecraft ?? 'Minecraft Server';
      case PortForwardPreset.webServer:
        return loc?.firewallWizardPresetWebServer ?? 'Web Server (HTTP/HTTPS)';
      case PortForwardPreset.custom:
        return loc?.firewallWizardPresetCustom ?? 'Custom Service';
    }
  }

  String _getServiceName(AppLocalizations? loc) {
    if (_selectedPreset == PortForwardPreset.custom) {
      final customName = _customServiceNameController.text.trim();
      return customName.isNotEmpty
          ? customName
          : (loc?.firewallWizardPresetCustom ?? 'Custom Service');
    }
    return _getPresetName(loc, _selectedPreset);
  }

  String _getExternalPort() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return '32400';
      case PortForwardPreset.minecraft:
        return '25565';
      case PortForwardPreset.webServer:
        return '80,443';
      case PortForwardPreset.custom:
        return _customExternalPortController.text.trim();
    }
  }

  String _getInternalPort() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return '32400';
      case PortForwardPreset.minecraft:
        return '25565';
      case PortForwardPreset.webServer:
        return '80,443';
      case PortForwardPreset.custom:
        final internal = _customInternalPortController.text.trim();
        return internal.isNotEmpty
            ? internal
            : _customExternalPortController.text.trim();
    }
  }

  String _getProtocol() {
    switch (_selectedPreset) {
      case PortForwardPreset.plex:
        return 'tcp';
      case PortForwardPreset.minecraft:
        return 'tcp udp';
      case PortForwardPreset.webServer:
        return 'tcp';
      case PortForwardPreset.custom:
        return _customProto;
    }
  }

  String? _getTargetIp() {
    if (_useManualIp) {
      return _manualIpController.text.trim();
    }
    return _selectedClient?.ipAddress.trim();
  }

  String _getTargetDeviceDisplayName() {
    if (_useManualIp) {
      return _manualIpController.text.trim();
    }
    if (_selectedClient != null) {
      return _selectedClient!.displayName;
    }
    return 'Device';
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

    final targetIp = _getTargetIp();
    if (targetIp == null || !FirewallValidator.isValidIpv4(targetIp)) {
      setState(() {
        _validationError = 'Please select or enter a valid IPv4 address.';
      });
      return;
    }

    final externalPort = _getExternalPort();
    final internalPort = _getInternalPort();
    final proto = _getProtocol();
    final serviceName = _getServiceName(loc);

    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final destZone = overview.primaryLanZoneName ?? 'lan';

    final candidate = FirewallPortForwarding(
      name: serviceName,
      srcZone: 'wan',
      srcPort: externalPort,
      destZone: destZone,
      destIp: targetIp,
      destPort: internalPort,
      proto: proto,
      target: 'DNAT',
      enabled: true,
    );

    final conflict = FirewallValidator.checkPortForwardConflict(
      candidate,
      overview.portForwards,
    );
    if (conflict.hasConflict) {
      setState(() {
        _validationError =
            loc?.firewallConflictPortInUse ??
            'This port is already being used by another rule.';
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
      final success = await appState.addFirewallPortForward(candidate);
      if (!mounted) return;

      if (success) {
        final deviceName = _getTargetDeviceDisplayName();
        ksSay(
          context,
          loc?.firewallSuccessPortOpened(
                candidate.srcPort,
                candidate.name,
                deviceName,
              ) ??
              'Port ${candidate.srcPort} is now open for ${candidate.name} on $deviceName.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to apply port forwarding rule.';
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
    final loc = AppLocalizations.of(context);
    final ks = context.ks;
    final appState = ref.watch(appStateProvider);
    final validClients = appState.clients
        .where((c) => FirewallValidator.isValidIpv4(c.ipAddress))
        .toList();
    final custom = _selectedPreset == PortForwardPreset.custom;

    String? port(String? v, {bool optional = false}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return optional ? null : 'Enter a port.';
      return FirewallValidator.parsePortRanges(t).isNotEmpty
          ? null
          : 'Use a port like 8080, or a range like 8000-8010.';
    }

    return KsFormPage(
      title: 'Open a port',
      subtitle: 'Let something on the internet reach one of your devices',
      action: 'Open',
      busy: _isSubmitting,
      formKey: _formKey,
      onAction: _handleSubmit,
      children: [
        KsChoice<PortForwardPreset>(
          label: 'For',
          value: _selectedPreset,
          options: [
            for (final p in PortForwardPreset.values)
              (p, _getPresetName(loc, p)),
          ],
          onChanged: (v) => setState(() {
            _selectedPreset = v;
            _validationError = null;
          }),
        ),
        if (!custom)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Opens port ${_getExternalPort()} '
              '(${_getProtocol().toUpperCase().replaceAll(' ', ' and ')}).',
              style: KeystoneType.secondary(ks.mu),
            ),
          ),
        if (_selectedPreset == PortForwardPreset.webServer)
          const KsBanner(
            'Anyone on the internet will be able to reach this web server.',
          ),
        if (custom) ...[
          KsField(
            label: 'Name',
            controller: _customServiceNameController,
            hint: 'For example Camera',
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KsField(
                  label: 'Outside port',
                  controller: _customExternalPortController,
                  keyboardType: TextInputType.number,
                  validator: port,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: KsField(
                  label: 'Device port',
                  controller: _customInternalPortController,
                  hint: 'Same',
                  keyboardType: TextInputType.number,
                  validator: (v) => port(v, optional: true),
                ),
              ),
            ],
          ),
          KsChoice<String>(
            label: 'Kind of traffic',
            value: _customProto,
            options: const [
              ('tcp', 'TCP'),
              ('udp', 'UDP'),
              ('tcp udp', 'TCP and UDP'),
            ],
            onChanged: (v) => setState(() => _customProto = v),
          ),
        ],
        const KsSection('To which device'),
        if (validClients.isNotEmpty)
          KsChips<bool>(
            options: const [
              (false, 'A device here'),
              (true, 'Type an address'),
            ],
            selected: _useManualIp,
            onSelected: (v) => setState(() => _useManualIp = v),
          ),
        const SizedBox(height: 12),
        if (!_useManualIp && validClients.isNotEmpty)
          KsChoice<Client>(
            label: 'Device',
            value: validClients.contains(_selectedClient)
                ? _selectedClient!
                : validClients.first,
            options: [
              for (final c in validClients)
                (
                  c,
                  '${ClientNamingHelper.getDisplayName(c.macAddress, appState: appState, client: c)} · ${c.ipAddress}',
                ),
            ],
            onChanged: (c) => setState(() => _selectedClient = c),
          )
        else
          KsField(
            label: 'Device address',
            controller: _manualIpController,
            hint: '192.168.1.100',
            keyboardType: TextInputType.number,
            validator: (v) {
              if (!_useManualIp) return null;
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Enter the device address.';
              return FirewallValidator.isValidIpv4(t)
                  ? null
                  : 'Use an address like 192.168.1.100.';
            },
          ),
        if (_validationError != null) KsBanner(_validationError!, bad: true),
      ],
    );
  }
}
