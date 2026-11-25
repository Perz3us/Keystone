// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/saved_ssh_command.dart';

class SavedCommandsSheet extends StatelessWidget {
  final List<SavedSshCommand> commands;
  final ValueChanged<SavedSshCommand> onRun;
  final ValueChanged<SavedSshCommand> onDelete;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;

  const SavedCommandsSheet({
    super.key,
    required this.commands,
    required this.onRun,
    required this.onDelete,
    this.onAdd,
    this.onImport,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SavedSshCommand> commands,
    required ValueChanged<SavedSshCommand> onRun,
    required ValueChanged<SavedSshCommand> onDelete,
    VoidCallback? onAdd,
    VoidCallback? onImport,
  }) => ksSheet<void>(
    context,
    (_) => SavedCommandsSheet(
      commands: commands,
      onRun: onRun,
      onDelete: onDelete,
      onAdd: onAdd,
      onImport: onImport,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    void then(VoidCallback f) {
      Navigator.of(context).pop();
      f();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Saved commands',
                style: KeystoneType.sheetTitle(ks.tx),
              ),
            ),
            Text(
              '${commands.length} of 50',
              style: KeystoneType.caption(ks.mu),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (commands.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'None yet. Type a command, then save it here to run it again '
              'with one tap.',
              style: KeystoneType.body(ks.mu),
            ),
          )
        else
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in commands)
                  KsRow(
                    title: c.name,
                    subtitle: c.command,
                    chevron: false,
                    onTap: () => then(() => onRun(c)),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: Icon(Icons.close_rounded, color: ks.mu),
                      onPressed: () async {
                        final ok = await ksConfirm(
                          context,
                          title: 'Remove "${c.name}"?',
                          body: c.command,
                          action: 'Remove',
                          danger: true,
                        );
                        if (ok) onDelete(c);
                      },
                    ),
                  ),
              ],
            ),
          ),
        if (onAdd != null)
          KsRow(
            title: 'Save a command',
            leading: Icon(Icons.add_rounded, color: ks.mu),
            onTap: () => then(onAdd!),
          ),
        if (onImport != null)
          KsRow(
            title: 'Bring in commands from a file',
            leading: Icon(Icons.file_download_outlined, color: ks.mu),
            onTap: () => then(onImport!),
          ),
      ],
    );
  }
}
