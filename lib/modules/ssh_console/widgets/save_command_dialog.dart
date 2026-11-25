// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class SaveCommandDialog extends StatefulWidget {
  final String initialCommand;

  const SaveCommandDialog({super.key, required this.initialCommand});

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required String initialCommand,
  }) => ksSheet<Map<String, String>>(
    context,
    (_) => SaveCommandDialog(initialCommand: initialCommand),
  );

  @override
  State<SaveCommandDialog> createState() => _SaveCommandDialogState();
}

class _SaveCommandDialogState extends State<SaveCommandDialog> {
  final _name = TextEditingController();
  late final _cmd = TextEditingController(text: widget.initialCommand);

  @override
  void dispose() {
    _name.dispose();
    _cmd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final ok = _name.text.trim().isNotEmpty && _cmd.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Save a command', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 12),
        KsField(
          label: 'Name',
          controller: _name,
          hint: 'For example Check uptime',
          onChanged: (_) => setState(() {}),
        ),
        KsField(
          label: 'Command',
          controller: _cmd,
          hint: 'uptime',
          maxLines: 3,
          help: "Don't save passwords in a command.",
          onChanged: (_) => setState(() {}),
        ),
        FilledButton(
          onPressed: ok
              ? () => Navigator.of(
                  context,
                ).pop({'name': _name.text.trim(), 'command': _cmd.text.trim()})
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
