// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

class RevertRouterDnsDialog extends StatefulWidget {
  final AdGuardController controller;
  final String routerId;
  final AdGuardDnsRevertPreflightResult? initialPreflight;

  const RevertRouterDnsDialog({
    super.key,
    required this.controller,
    required this.routerId,
    this.initialPreflight,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    required String routerId,
    AdGuardDnsRevertPreflightResult? initialPreflight,
  }) {
    return ksSheet<bool>(
      context,
      (_) => RevertRouterDnsDialog(
        controller: controller,
        routerId: routerId,
        initialPreflight: initialPreflight,
      ),
    );
  }

  @override
  State<RevertRouterDnsDialog> createState() => _RevertRouterDnsDialogState();
}

class _RevertRouterDnsDialogState extends State<RevertRouterDnsDialog> {
  bool _isLoadingPreflight = true;
  AdGuardDnsRevertPreflightResult? _preflight;
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
      final res = await widget.controller.preflightRevertRouterDns();
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

  Future<void> _applyRevert() async {
    if (_preflight == null ||
        !_preflight!.canProceed ||
        _preflight!.targetRule == null) {
      return;
    }

    setState(() {
      _isApplying = true;
      _currentStep = 'Changing the router…';
    });

    final res = await widget.controller.revertRouterDns(
      targetForwarder: _preflight!.targetRule!,
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
      key: const Key('agh_revert_dns_dialog'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Stop sending lookups to AdGuard Home',
              style: KeystoneType.sheetTitle(ks.tx),
            ),
            const SizedBox(height: 8),
            ..._content(),
            const SizedBox(height: 20),
            ..._actions(),
          ],
        ),
      ),
    );
  }

  Widget _working(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(text, style: KeystoneType.body(context.ks.tx2)),
      ],
    ),
  );

  List<Widget> _content() {
    final ks = context.ks;
    if (_isLoadingPreflight) return [_working('Checking the router…')];
    if (_isApplying) return [_working(_currentStep)];
    final r = _result;
    if (r != null) {
      final title = switch (r.status) {
        AdGuardDnsConfigStatus.success =>
          'Done. The router no longer sends lookups to AdGuard Home.',
        AdGuardDnsConfigStatus.rolledBack =>
          'The router stopped answering, so it put the old settings back.',
        AdGuardDnsConfigStatus.ambiguous =>
          'Keystone can\'t tell if it worked. Check the router.',
        AdGuardDnsConfigStatus.failed =>
          r.message.isNotEmpty ? r.message : 'The router didn\'t change.',
      };
      return [
        Row(
          children: [
            KsDot(r.isSuccess ? ks.ok : ks.warn, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                key: const Key('agh_revert_dns_result_title'),
                style: KeystoneType.bodyStrong(ks.tx),
              ),
            ),
          ],
        ),
        if (r.isSuccess && r.appliedServers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Lookups now go to ${r.appliedServers.join(', ')}',
              style: KeystoneType.secondary(ks.mu),
            ),
          ),
      ];
    }
    final p = _preflight;
    if (p == null) {
      return [
        const KsBanner('Keystone couldn\'t check the router.', bad: true),
      ];
    }
    if (!p.canProceed) {
      final (msg, key) = p.isMissing
          ? (
              'The router isn\'t sending lookups to this AdGuard Home.',
              'agh_revert_dns_missing_error',
            )
          : p.isAmbiguous
          ? (
              'The router has more than one rule for AdGuard Home. Check it '
                  'in LuCI.',
              'agh_revert_dns_ambiguous_error',
            )
          : (
              p.failureReason ?? 'This can\'t be undone from here.',
              'agh_revert_dns_generic_error',
            );
      return [
        KsBanner(msg, bad: true, key: Key(key)),
        if (p.currentServers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Lookups go to ${p.currentServers.join(', ')}',
              style: KeystoneType.secondary(ks.mu),
            ),
          ),
      ];
    }
    return [
      Text(
        'The router goes back to its own DNS, so ads are no longer blocked '
        'for devices that use the router.',
        style: KeystoneType.body(ks.tx2),
      ),
      const SizedBox(height: 12),
      Text('Taken off', style: KeystoneType.secondary(ks.mu)),
      Text(
        p.targetRule ?? '',
        key: const Key('agh_revert_dns_target_text'),
        style: KeystoneType.address(ks.tx),
      ),
      const SizedBox(height: 8),
      Text('Lookups go to', style: KeystoneType.secondary(ks.mu)),
      Text(
        p.remainingServers.isNotEmpty
            ? p.remainingServers.join(', ')
            : 'The router\'s internet provider',
        key: const Key('agh_revert_dns_remaining_text'),
        style: KeystoneType.address(ks.tx),
      ),
      if (p.remainingServers.isEmpty)
        const KsBanner(
          'No other DNS servers are set, so the router uses the ones its '
          'internet provider gives it.',
          key: Key('agh_revert_dns_no_remaining_warning'),
        ),
    ];
  }

  List<Widget> _actions() {
    final ks = context.ks;
    if (_isApplying) return const [];
    if (_result != null) {
      return [
        FilledButton(
          key: const Key('agh_revert_dns_done_btn'),
          onPressed: () => Navigator.of(context).pop(_result!.isSuccess),
          child: const Text('Done'),
        ),
        if (!_result!.isSuccess)
          TextButton(
            key: const Key('agh_revert_dns_retry_btn'),
            onPressed: _loadPreflight,
            child: const Text('Try again'),
          ),
      ];
    }
    if (_preflight != null && !_preflight!.canProceed) {
      return [
        FilledButton(
          key: const Key('agh_cancel_revert_dns_btn'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
      ];
    }
    return [
      FilledButton(
        key: const Key('agh_confirm_revert_dns_btn'),
        style: FilledButton.styleFrom(
          backgroundColor: ks.bad,
          foregroundColor: ks.bg,
        ),
        onPressed: _preflight?.canProceed == true ? _applyRevert : null,
        child: const Text('Stop sending lookups'),
      ),
      TextButton(
        key: const Key('agh_cancel_revert_dns_btn'),
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancel'),
      ),
    ];
  }
}
