// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

enum BlockTargetType { externalIp, portOrService, commonApp }

class CommonThreatPreset {
  final String name;
  final String port;
  final String proto;

  const CommonThreatPreset({
    required this.name,
    required this.port,
    required this.proto,
  });
}

const List<CommonThreatPreset> commonThreatPresets = [
  CommonThreatPreset(name: 'Telnet (Insecure Shell)', port: '23', proto: 'tcp'),
  CommonThreatPreset(name: 'SMB / Windows Sharing', port: '445', proto: 'tcp'),
  CommonThreatPreset(name: 'NetBIOS', port: '137-139', proto: 'tcp udp'),
  CommonThreatPreset(name: 'RDP (Remote Desktop)', port: '3389', proto: 'tcp'),
];

class BlockIncomingTrafficDialog extends ConsumerStatefulWidget {
  const BlockIncomingTrafficDialog({super.key});

  static Future<bool?> show(BuildContext context) =>
      ksFormRoute<bool>(context, const BlockIncomingTrafficDialog());

  @override
  ConsumerState<BlockIncomingTrafficDialog> createState() =>
      _BlockIncomingTrafficDialogState();
}

class _BlockIncomingTrafficDialogState
    extends ConsumerState<BlockIncomingTrafficDialog> {
  final _formKey = GlobalKey<FormState>();

  BlockTargetType _targetType = BlockTargetType.externalIp;
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  String _portProto = 'tcp';
  CommonThreatPreset _selectedCommonThreat = commonThreatPresets.first;

  IncomingTrafficPreflightResult? _preflightResult;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluatePreflight();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _onTargetTypeChanged(BlockTargetType newType) {
    setState(() {
      _targetType = newType;
      _errorMessage = null;
    });
    _evaluatePreflight();
  }

  void _evaluatePreflight() {
    final appState = ref.read(appStateProvider);
    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    String? port;
    String? proto = 'any';
    String? ip;

    switch (_targetType) {
      case BlockTargetType.externalIp:
        final rawIp = _ipController.text.trim();
        if (rawIp.isNotEmpty && FirewallValidator.isValidIpOrCidr(rawIp)) {
          ip = rawIp;
        }
        break;
      case BlockTargetType.portOrService:
        final rawPort = _portController.text.trim();
        if (rawPort.isNotEmpty) {
          port = rawPort;
          proto = _portProto;
        }
        break;
      case BlockTargetType.commonApp:
        port = _selectedCommonThreat.port;
        proto = _selectedCommonThreat.proto;
        break;
    }

    final result = FirewallValidator.evaluateIncomingTrafficPreflight(
      overview: overview,
      incomingPort: port,
      proto: proto,
      srcIp: ip,
    );

    setState(() {
      _preflightResult = result;
    });
  }

  Future<void> _handleBlock({bool forceExplicit = false}) async {
    final loc = AppLocalizations.of(context);
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final appState = ref.read(appStateProvider);
    final canModify = appState.capabilities?.canModifyFirewall ?? true;
    if (!canModify) {
      setState(() {
        _errorMessage =
            loc?.firewallReadOnlyNotice ??
            'Read-only access: Changes cannot be applied on this router account.';
      });
      return;
    }

    final overview = FirewallOverview.fromUciData(
      appState.dashboardData?['uciFirewallConfig'],
      backend: appState.capabilities?.firewallBackend ?? FirewallBackend.fw4,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    final resolvedDest =
        _preflightResult?.resolvedDestZone ?? overview.primaryLanZoneName;

    if (resolvedDest == null || resolvedDest.isEmpty) {
      setState(() {
        _errorMessage =
            loc?.firewallBlockUnableToDetermineDesc ??
            'Unable to determine safe destination zone for incoming block rule.';
      });
      return;
    }

    String ruleName;
    String? srcIp;
    String? destPort;
    String proto = 'any';

    switch (_targetType) {
      case BlockTargetType.externalIp:
        final targetIp = _ipController.text.trim();
        if (!FirewallValidator.isValidIpOrCidr(targetIp)) {
          setState(
            () => _errorMessage = 'Please enter a valid IP address or CIDR.',
          );
          return;
        }

        final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
          context,
          actionName: 'Block Incoming Connection',
          targetIp: targetIp,
        );
        if (!safe || !mounted) return;

        ruleName =
            'Block_Incoming_${targetIp.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        srcIp = targetIp;
        break;

      case BlockTargetType.portOrService:
        final rawPort = _portController.text.trim();
        if (rawPort.isEmpty) {
          setState(() => _errorMessage = 'Please enter a port or port range.');
          return;
        }
        ruleName =
            'Block_Incoming_Port_${rawPort.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        destPort = rawPort;
        proto = _portProto;
        break;

      case BlockTargetType.commonApp:
        ruleName =
            'Block_Incoming_${_selectedCommonThreat.name.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
        destPort = _selectedCommonThreat.port;
        proto = _selectedCommonThreat.proto;
        break;
    }

    final candidate = FirewallCustomRule(
      sectionKey: '',
      name: ruleName,
      srcZone: 'wan',
      destZone: resolvedDest,
      target: 'DROP',
      enabled: true,
      proto: proto,
      srcIp: srcIp,
      destPort: destPort,
    );

    setState(() => _isSubmitting = true);
    try {
      final success = await appState.addFirewallCustomRule(candidate);
      if (!mounted) return;

      if (success) {
        ksSay(
          context,
          'Incoming connection block rule created for "$ruleName".',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to create firewall block rule.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final typed = switch (_targetType) {
      BlockTargetType.externalIp => _ipController.text.trim().isNotEmpty,
      BlockTargetType.portOrService => _portController.text.trim().isNotEmpty,
      BlockTargetType.commonApp => true,
    };
    final pre = typed ? _preflightResult : null;
    final already = pre?.isAlreadyBlocked == true;

    return KsFormPage(
      title: 'Block something',
      subtitle: 'Stop a connection coming in from the internet',
      action: already ? 'Add a rule anyway' : 'Block',
      busy: _isSubmitting,
      formKey: _formKey,
      onAction: pre?.isUnableToDetermine == true
          ? null
          : () => _handleBlock(forceExplicit: already),
      children: [
        KsChips<BlockTargetType>(
          options: const [
            (BlockTargetType.externalIp, 'An address'),
            (BlockTargetType.portOrService, 'A port'),
            (BlockTargetType.commonApp, 'A risky service'),
          ],
          selected: _targetType,
          onSelected: _onTargetTypeChanged,
        ),
        const SizedBox(height: 16),
        switch (_targetType) {
          BlockTargetType.externalIp => KsField(
            label: 'Internet address',
            controller: _ipController,
            hint: '198.51.100.25 or 198.51.100.0/24',
            help: 'One address, or a whole range',
            keyboardType: TextInputType.text,
            onChanged: (_) => _evaluatePreflight(),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return 'Enter an address.';
              return FirewallValidator.isValidIpOrCidr(t)
                  ? null
                  : 'Use an address like 198.51.100.25.';
            },
          ),
          BlockTargetType.portOrService => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KsField(
                label: 'Port',
                controller: _portController,
                hint: '8080 or 8000-8080',
                keyboardType: TextInputType.number,
                onChanged: (_) => _evaluatePreflight(),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'Enter a port.';
                  return FirewallValidator.parsePortRanges(t).isNotEmpty
                      ? null
                      : 'Use a port like 8080.';
                },
              ),
              KsChoice<String>(
                label: 'Kind of traffic',
                value: _portProto,
                options: const [
                  ('tcp', 'TCP'),
                  ('udp', 'UDP'),
                  ('tcp udp', 'TCP and UDP'),
                ],
                onChanged: (v) {
                  setState(() => _portProto = v);
                  _evaluatePreflight();
                },
              ),
            ],
          ),
          BlockTargetType.commonApp => KsChoice<CommonThreatPreset>(
            label: 'Service',
            value: _selectedCommonThreat,
            help: 'Old services that attackers often look for',
            options: [
              for (final p in commonThreatPresets)
                (p, '${p.name} · port ${p.port}'),
            ],
            onChanged: (v) {
              setState(() => _selectedCommonThreat = v);
              _evaluatePreflight();
            },
          ),
        },
        if (pre != null) ...[
          const SizedBox(height: 8),
          if (already)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: KsDot(ks.ok),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Already blocked. The firewall turns this away by '
                    "default, so there's nothing to add.",
                    style: KeystoneType.body(ks.tx2),
                  ),
                ),
              ],
            )
          else if (pre.isCurrentlyAllowed)
            KsBanner(
              'This is let in right now'
              '${pre.conflictingRuleName == null ? '' : ' by "${pre.conflictingRuleName}"'}. '
              'Blocking it overrides that.',
            )
          else if (pre.isUnableToDetermine)
            const KsBanner(
              "Keystone can't tell whether this is let in, so it won't add a "
              'rule that might clash. Check the firewall rules first.',
              bad: true,
            ),
        ],
        if (_errorMessage != null) KsBanner(_errorMessage!, bad: true),
      ],
    );
  }
}
