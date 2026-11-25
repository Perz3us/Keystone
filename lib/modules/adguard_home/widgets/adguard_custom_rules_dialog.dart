// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';

class AdGuardCustomRulesDialog extends StatefulWidget {
  final AdGuardController controller;
  final List<String>? initialRules;

  const AdGuardCustomRulesDialog({
    super.key,
    required this.controller,
    this.initialRules,
  });

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
    List<String>? initialRules,
  }) {
    return ksFormRoute<bool>(
      context,
      AdGuardCustomRulesDialog(
        controller: controller,
        initialRules: initialRules,
      ),
    );
  }

  @override
  State<AdGuardCustomRulesDialog> createState() =>
      _AdGuardCustomRulesDialogState();
}

class _AdGuardCustomRulesDialogState extends State<AdGuardCustomRulesDialog> {
  late final TextEditingController _textController;
  bool _isSaving = false;
  String? _errorMessage;
  int _ruleCount = 0;

  @override
  void initState() {
    super.initState();
    final existingRules =
        widget.initialRules ??
        widget.controller.currentState.filtering?.userRules ??
        [];
    _textController = TextEditingController(text: existingRules.join('\n'));
    _ruleCount = _countRules(_textController.text);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final count = _countRules(_textController.text);
    if (count != _ruleCount) {
      setState(() {
        _ruleCount = count;
      });
    }
  }

  int _countRules(String text) {
    if (text.isEmpty) return 0;
    return text
        .split('\n')
        .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('!'))
        .length;
  }

  List<String> _parseRules(String text) {
    return text
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> _saveRules() async {
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final rules = _parseRules(_textController.text);
    final success = await widget.controller.updateUserRules(rules);

    if (!mounted) return;

    if (success) {
      ksSay(context, 'Your rules are saved.');
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage =
            widget.controller.currentState.filteringError ??
            'AdGuard Home didn\'t save them. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return KsFormPage(
      key: const Key('agh_custom_rules_dialog'),
      title: 'Your own rules',
      subtitle: '$_ruleCount rules. One per line.',
      action: 'Save',
      actionKey: const Key('agh_custom_rules_save_button'),
      busy: _isSaving,
      onAction: _saveRules,
      children: [
        if (_errorMessage != null)
          KsBanner(
            _errorMessage!,
            bad: true,
            key: const Key('agh_custom_rules_error_banner'),
          ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('agh_custom_rules_text_field'),
          controller: _textController,
          enabled: !_isSaving,
          minLines: 10,
          maxLines: null,
          style: KeystoneType.address(ks.tx).copyWith(fontSize: 14),
          decoration: ksInput(
            context,
            hint: '||ads.example.com^\n@@||allowed.com^',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '||site.com^ blocks a site and everything under it.\n'
          '@@||site.com^ always lets a site through.\n'
          'A line that starts with ! is a note.',
          style: KeystoneType.secondary(ks.mu),
        ),
      ],
    );
  }
}
