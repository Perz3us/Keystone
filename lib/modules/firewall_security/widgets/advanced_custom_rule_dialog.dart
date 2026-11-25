// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/modules/firewall_security/screens/firewall_security_screen.dart'
    show zoneName;
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/firewall_security/utils/firewall_validator.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';

class AdvancedCustomRuleDialog extends ConsumerStatefulWidget {
  final FirewallCustomRule? initialRule;
  final FirewallOverview overview;

  const AdvancedCustomRuleDialog({
    super.key,
    this.initialRule,
    required this.overview,
  });

  static Future<bool?> show(
    BuildContext context, {
    FirewallCustomRule? initialRule,
    required FirewallOverview overview,
  }) {
    return ksFormRoute<bool>(
      context,
      AdvancedCustomRuleDialog(initialRule: initialRule, overview: overview),
    );
  }

  @override
  ConsumerState<AdvancedCustomRuleDialog> createState() =>
      _AdvancedCustomRuleDialogState();
}

class _AdvancedCustomRuleDialogState
    extends ConsumerState<AdvancedCustomRuleDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _srcIpController;
  late final TextEditingController _srcMacController;
  late final TextEditingController _destIpController;
  late final TextEditingController _destPortController;

  late String _target;
  late String _srcZone;
  late String _destZone;
  late String _proto;
  late String _family;
  late bool _enabled;

  bool _isSubmitting = false;
  String? _validationError;

  bool get _isEditing => widget.initialRule != null;

  @override
  void initState() {
    super.initState();
    final init = widget.initialRule;
    _nameController = TextEditingController(text: init?.name ?? '');
    _srcIpController = TextEditingController(text: init?.srcIp ?? '');
    _srcMacController = TextEditingController(
      text: init?.srcMac.join(', ') ?? '',
    );
    _destIpController = TextEditingController(text: init?.destIp ?? '');
    _destPortController = TextEditingController(text: init?.destPort ?? '');

    final availableZones = widget.overview.zones.map((z) => z.name).toList();
    if (init != null &&
        (init.srcZone == '*' ||
            init.srcZone == 'any' ||
            availableZones.contains(init.srcZone))) {
      _srcZone = init.srcZone;
    } else if (availableZones.contains('wan')) {
      _srcZone = 'wan';
    } else {
      _srcZone = availableZones.isNotEmpty ? availableZones.first : '*';
    }

    if (init != null &&
        (init.destZone == '*' ||
            init.destZone == 'any' ||
            availableZones.contains(init.destZone))) {
      _destZone = init.destZone;
    } else if (availableZones.contains('lan')) {
      _destZone = 'lan';
    } else {
      _destZone = availableZones.isNotEmpty ? availableZones.first : '*';
    }

    _target = init?.target.toUpperCase() ?? 'DROP';
    if (!['ACCEPT', 'REJECT', 'DROP'].contains(_target)) {
      _target = 'DROP';
    }

    _proto = init?.proto.toLowerCase() ?? 'any';
    if (_proto == 'tcpudp') _proto = 'tcp udp';

    _family = init?.family.toLowerCase() ?? 'any';
    _enabled = init?.enabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _srcIpController.dispose();
    _srcMacController.dispose();
    _destIpController.dispose();
    _destPortController.dispose();
    super.dispose();
  }

  bool _isValidPortSpec(String? portSpec) {
    if (portSpec == null || portSpec.trim().isEmpty) return true;
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

  bool _isValidMac(String mac) {
    final reg = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return reg.hasMatch(mac.trim());
  }

  List<String> _parseMacList(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return const [];
    return clean
        .split(',')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .toList();
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
    final srcIp = _srcIpController.text.trim();
    final macList = _parseMacList(_srcMacController.text);
    final destIp = _destIpController.text.trim();
    final destPort = _destPortController.text.trim();

    final isLockoutRisk = await SelfDeviceGuard.isManagementLockoutRisk(
      target: _target,
      srcZone: _srcZone,
      destZone: _destZone,
      srcMac: macList,
      srcIp: srcIp,
      destPort: destPort,
      proto: _proto,
      routerId:
          appState.selectedRouter?.id ?? appState.selectedRouter?.ipAddress,
    );
    if (isLockoutRisk) {
      setState(() {
        _validationError =
            'Safety guard blocked rule: This DROP/REJECT rule affects the managing device or router management path and would cause network lockout.';
      });
      return;
    }

    final preservedRawValues = Map<String, dynamic>.from(
      widget.initialRule?.rawUciValues ?? const {},
    );

    final candidate = FirewallCustomRule(
      sectionKey: widget.initialRule?.sectionKey ?? '',
      name: name,
      srcZone: _srcZone,
      destZone: _destZone,
      target: _target,
      enabled: _enabled,
      isUnrecognizedTarget: false,
      proto: _proto,
      srcMac: macList,
      srcIp: srcIp.isNotEmpty ? srcIp : null,
      destIp: destIp.isNotEmpty ? destIp : null,
      destPort: destPort.isNotEmpty ? destPort : null,
      family: _family,
      position: widget.initialRule?.position,
      rawUciValues: preservedRawValues,
    );

    setState(() => _isSubmitting = true);
    try {
      final bool success;
      if (_isEditing) {
        success = await appState.updateFirewallCustomRule(
          candidate,
          context: mounted ? context : null,
        );
      } else {
        success = await appState.addFirewallCustomRule(
          candidate,
          context: mounted ? context : null,
        );
      }

      if (!mounted) return;

      if (success) {
        ksSay(
          context,
          _isEditing
              ? 'Security rule "$name" updated.'
              : 'Security rule "$name" created.',
        );
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isSubmitting = false;
          _validationError = 'Failed to save security rule configuration.';
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
    final appState = ref.watch(appStateProvider);
    final supportsIpv6 =
        appState.capabilities?.supportsIpv6InternetFirewall ?? false;
    final zones = widget.overview.zones.map((z) => z.name).toList();
    final zoneValues = ['*', ...zones];
    if (_srcZone == 'any') _srcZone = '*';
    if (_destZone == 'any') _destZone = '*';
    if (!zoneValues.contains(_srcZone)) _srcZone = zoneValues.first;
    if (!zoneValues.contains(_destZone)) _destZone = zoneValues.first;
    String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
    final zoneOptions = [for (final z in zoneValues) (z, cap(zoneName(z)))];

    return KsFormPage(
      title: _isEditing ? 'Change the rule' : 'Write a rule',
      subtitle: 'What to do with traffic that matches',
      action: _isEditing ? 'Save' : 'Add',
      busy: _isSubmitting,
      formKey: _formKey,
      onAction: _handleSubmit,
      children: [
        KsField(
          label: 'Name',
          controller: _nameController,
          hint: 'For example Block old camera',
          validator: (v) => (v ?? '').trim().isEmpty ? 'Give it a name.' : null,
        ),
        KsChoice<String>(
          label: 'Do this',
          value: _target,
          options: const [
            ('ACCEPT', 'Let it through'),
            ('REJECT', 'Block it and say so'),
            ('DROP', 'Block it silently'),
          ],
          onChanged: (v) => setState(() => _target = v),
        ),
        const KsSection('When it comes from'),
        KsChoice<String>(
          label: 'Zone',
          value: _srcZone,
          options: zoneOptions,
          onChanged: (v) => setState(() => _srcZone = v),
        ),
        KsField(
          label: 'Address (optional)',
          controller: _srcIpController,
          hint: '203.0.113.50 or 203.0.113.0/24',
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty || FirewallValidator.isValidIpOrCidr(t)) return null;
            return 'Use an address like 203.0.113.50.';
          },
        ),
        KsField(
          label: 'Device addresses (optional)',
          controller: _srcMacController,
          hint: 'AA:BB:CC:DD:EE:FF',
          help: 'Separate several with commas',
          validator: (v) {
            for (final m in _parseMacList(v ?? '')) {
              if (!_isValidMac(m)) return '"$m" isn\'t a device address.';
            }
            return null;
          },
        ),
        const KsSection('And goes to'),
        KsChoice<String>(
          label: 'Zone',
          value: _destZone,
          options: zoneOptions,
          onChanged: (v) => setState(() => _destZone = v),
        ),
        KsField(
          label: 'Address (optional)',
          controller: _destIpController,
          hint: '192.168.1.100 or 192.168.1.0/24',
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty || FirewallValidator.isValidIpOrCidr(t)) return null;
            return 'Use an address like 192.168.1.100.';
          },
        ),
        KsField(
          label: 'Port (optional)',
          controller: _destPortController,
          hint: '80, 443 or 8000-8080',
          validator: (v) =>
              _isValidPortSpec(v) ? null : 'Use ports from 1 to 65535.',
        ),
        const KsSection('Details'),
        KsChoice<String>(
          label: 'Kind of traffic',
          value: _proto,
          options: const [
            ('any', 'Any'),
            ('tcp', 'TCP'),
            ('udp', 'UDP'),
            ('tcp udp', 'TCP and UDP'),
            ('icmp', 'Ping (ICMP)'),
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
