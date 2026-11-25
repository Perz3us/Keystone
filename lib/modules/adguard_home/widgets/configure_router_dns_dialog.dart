// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

class ConfigureRouterDnsDialog extends StatefulWidget {
  final AdGuardController controller;
  final String routerId;
  final AdGuardDnsPreflightResult? initialPreflight;

  const ConfigureRouterDnsDialog({
    super.key,
    required this.controller,
    required this.routerId,
    this.initialPreflight,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    required String routerId,
    AdGuardDnsPreflightResult? initialPreflight,
  }) {
    return ksSheet<bool>(
      context,
      (_) => ConfigureRouterDnsDialog(
        controller: controller,
        routerId: routerId,
        initialPreflight: initialPreflight,
      ),
    );
  }

  @override
  State<ConfigureRouterDnsDialog> createState() =>
      _ConfigureRouterDnsDialogState();
}

class _ConfigureRouterDnsDialogState extends State<ConfigureRouterDnsDialog> {
  bool _isLoadingPreflight = true;
  AdGuardDnsPreflightResult? _preflight;
  bool _preserveFallback = false;
  bool _isApplying = false;
  String _currentStep = '';
  AdGuardDnsConfigResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialPreflight != null) {
      _preflight = widget.initialPreflight;
      _isLoadingPreflight = false;
    } else {
      _loadPreflight();
    }
  }

  Future<void> _loadPreflight() async {
    setState(() {
      _isLoadingPreflight = true;
      _result = null;
    });
    try {
      final res = await widget.controller.preflightRouterDnsConfiguration();
      if (mounted) {
        setState(() {
          _preflight = res;
          _isLoadingPreflight = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingPreflight = false;
        });
      }
    }
  }

  Future<void> _applyConfiguration() async {
    if (_preflight == null || !_preflight!.canProceed) return;

    setState(() {
      _isApplying = true;
      _currentStep = 'Changing the router…';
    });

    final res = await widget.controller.configureRouterDns(
      preserveExistingAsFallback: _preserveFallback,
      targetForwarder: _preflight!.targetForwarder,
    );

    if (mounted) {
      setState(() {
        _isApplying = false;
        _result = res;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Point the router at AdGuard Home',
              style: KeystoneType.sheetTitle(ks.tx),
            ),
            const SizedBox(height: 8),
            ..._content(context),
            const SizedBox(height: 20),
            ..._actions(context),
          ],
        ),
      ),
    );
  }

  List<String> _advisories() {
    final p = _preflight!;
    return p.warnings.where((w) {
      if (p.loopDetected && w == p.loopReason) return false;
      if (p.portConflict && w == p.portConflictReason) return false;
      if (p.isHostname && w.toLowerCase().contains('hostname')) return false;
      return true;
    }).toList();
  }

  Widget _working(String text) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(text, style: KeystoneType.body(ks.tx2)),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context) {
    final ks = context.ks;
    if (_isLoadingPreflight) return [_working('Checking the router…')];
    if (_isApplying) {
      return [
        _working(_currentStep),
        Text(
          'If the router stops answering, it puts the old settings back '
          'by itself within 30 seconds.',
          style: KeystoneType.secondary(ks.mu),
        ),
      ];
    }
    if (_result != null) return _resultView(context);
    final p = _preflight;
    if (p == null) {
      return [
        const KsBanner('Keystone couldn\'t check the router.', bad: true),
      ];
    }
    final notes = _advisories();
    return [
      Text(
        'The router sends every lookup to AdGuard Home, so ads are blocked '
        'on every device without setting each one up.',
        style: KeystoneType.body(ks.tx2),
      ),
      const SizedBox(height: 12),
      Text(
        p.isExternal
            ? 'AdGuard Home on another device'
            : 'AdGuard Home on this router',
        style: KeystoneType.secondary(ks.mu),
      ),
      Text(
        p.targetForwarder,
        key: const Key('agh_dns_target_forwarder_text'),
        style: KeystoneType.address(ks.tx),
      ),
      if (p.loopDetected)
        KsBanner(
          p.loopReason ??
              'This would send lookups round in a circle, so it can\'t be done.',
          bad: true,
          key: const Key('agh_dns_loop_error_text'),
        ),
      if (p.portConflict)
        KsBanner(
          p.portConflictReason ??
              'AdGuard Home and the router\'s own DNS use the same port.',
          bad: true,
          key: const Key('agh_dns_conflict_error_text'),
        ),
      if (p.isHostname)
        const KsBanner(
          'The address is a name, not a number. A fixed IP address is more '
          'reliable here.',
        ),
      if (!p.loopDetected && !p.portConflict && notes.isNotEmpty)
        Container(
          key: const Key('agh_dns_advisory_warning_card'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ks.warn.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in notes)
                Text(
                  w,
                  key: const Key('agh_dns_advisory_warning_text'),
                  style: KeystoneType.secondary(ks.warnTx),
                ),
            ],
          ),
        ),
      if (p.canProceed) ...[
        const KsSection('If AdGuard Home stops'),
        KsChoice<bool>(
          label: 'What the router does',
          value: _preserveFallback,
          options: const [
            (false, 'Nothing works until it\'s back'),
            (true, 'Use the old servers instead'),
          ],
          help: _preserveFallback
              ? 'Some lookups may skip AdGuard Home.'
              : 'Every lookup goes through AdGuard Home.',
          onChanged: (v) => setState(() => _preserveFallback = v),
        ),
      ],
    ];
  }

  List<Widget> _resultView(BuildContext context) {
    final ks = context.ks;
    final r = _result!;
    final title = r.isSuccess
        ? 'Done. Every device now uses AdGuard Home.'
        : r.isRolledBack
        ? 'The router stopped answering, so it put the old settings back.'
        : r.isAmbiguous
        ? 'Keystone can\'t tell if it worked. Check the router.'
        : r.message;
    final notes = r.isSuccess && _preflight != null ? _advisories() : const [];
    return [
      Row(
        children: [
          KsDot(r.isSuccess ? ks.ok : ks.warn, size: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              key: const Key('agh_dns_config_result_title'),
              style: KeystoneType.bodyStrong(ks.tx),
            ),
          ),
        ],
      ),
      if (r.appliedServers.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Lookups go to ${r.appliedServers.join(', ')}',
            style: KeystoneType.secondary(ks.mu),
          ),
        ),
      if (notes.isNotEmpty)
        Container(
          key: const Key('agh_dns_result_advisory_card'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ks.warn.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in notes)
                Text(
                  w,
                  key: const Key('agh_dns_result_advisory_warning_text'),
                  style: KeystoneType.secondary(ks.warnTx),
                ),
            ],
          ),
        ),
    ];
  }

  List<Widget> _actions(BuildContext context) {
    if (_isApplying) return const [];
    if (_result != null) {
      return [
        FilledButton(
          key: const Key('agh_dns_config_done_btn'),
          onPressed: () => Navigator.of(context).pop(_result!.isSuccess),
          child: const Text('Done'),
        ),
        if (!_result!.isSuccess)
          TextButton(onPressed: _loadPreflight, child: const Text('Try again')),
      ];
    }
    return [
      FilledButton(
        key: const Key('agh_apply_dns_btn'),
        onPressed: _preflight?.canProceed == true ? _applyConfiguration : null,
        child: const Text('Point the router at it'),
      ),
      TextButton(
        key: const Key('agh_cancel_dns_btn'),
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
    ];
  }
}
