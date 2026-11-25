// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_persistent_session_interface.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import '../controllers/ssh_console_controller.dart';
import '../models/saved_ssh_command.dart';
import '../models/ssh_command_risk.dart';
import '../services/saved_commands_service.dart';
import '../widgets/save_command_dialog.dart';
import '../widgets/saved_commands_sheet.dart';

class SshConsoleScreen extends ConsumerStatefulWidget {
  const SshConsoleScreen({super.key});

  @override
  ConsumerState<SshConsoleScreen> createState() => _SshConsoleScreenState();
}

class _SshConsoleScreenState extends ConsumerState<SshConsoleScreen> {
  final FocusNode _terminalFocusNode = FocusNode();
  final TerminalController _terminalController = TerminalController();
  bool _noteDismissed = false;
  final _password = TextEditingController();

  @override
  void initState() {
    super.initState();
    _terminalFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _terminalFocusNode.removeListener(_onFocusChange);
    _terminalFocusNode.dispose();
    _terminalController.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _copyAll(String text) {
    Clipboard.setData(ClipboardData(text: text));
    final l10n = AppLocalizations.of(context);
    ksSay(
      context,
      l10n?.sshTerminalAllCopied ?? 'Terminal output copied to clipboard',
    );
  }

  Future<void> _clearBuffer(SshConsoleController controller) async {
    final confirmed = await ksConfirm(
      context,
      title: 'Clear the screen?',
      body: 'The session stays open; only what is shown goes.',
      action: 'Clear',
    );
    if (confirmed == true) {
      controller.clearBuffer();
    }
  }

  Widget _key({
    IconData? icon,
    String? label,
    required String tooltip,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    final ks = context.ks;
    final on = onPressed != null;
    final fg = (color ?? ks.tx).withValues(alpha: on ? 1 : 0.35);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: ks.node,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: on
              ? () {
                  unawaited(HapticFeedback.selectionClick());
                  onPressed();
                }
              : null,
          child: Container(
            height: 40,
            constraints: const BoxConstraints(minWidth: 44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, size: 20, color: fg)
                : Text(label!, style: KeystoneType.bodyStrong(fg)),
          ),
        ),
      ),
    );
  }

  Future<void> _showSaveDialog(
    String initialCommand,
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) async {
    final res = await SaveCommandDialog.show(
      context,
      initialCommand: initialCommand,
    );
    if (res != null && mounted) {
      final saveResult = await controller.saveCommand(
        res['name']!,
        res['command']!,
      );
      if (!mounted) return;
      if (saveResult == SaveResult.ok) {
        ksSay(context, l10n?.sshCommandSaved ?? 'Command saved');
      } else if (saveResult == SaveResult.limitReached) {
        ksSay(
          context,
          l10n?.sshTerminalMaxCommandsReached ??
              'Maximum of 50 saved commands reached. Delete one to save another.',
        );
      } else {
        ksSay(context, 'Failed to save command');
      }
    }
  }

  void _showSavedCommandsSheet(
    List<SavedSshCommand> commands,
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) {
    SavedCommandsSheet.show(
      context,
      commands: commands,
      onRun: (cmd) async {
        final risk = controller.classifyCommand(cmd.command);
        if (risk == SshCommandRisk.destructive) {
          final confirmed = await ksConfirm(
            context,
            title: 'Run "${cmd.name}"?',
            body:
                'It can stop services or erase data on the router:\n\n'
                '${cmd.command}',
            action: 'Run it',
            danger: true,
          );
          if (!confirmed || !mounted) return;
        } else if (risk == SshCommandRisk.elevated) {
          ksSay(context, 'This one changes router settings.');
        }

        controller.sendCommand(cmd.command);
      },
      onDelete: (cmd) async {
        await controller.deleteSavedCommand(cmd.id);
        if (mounted) {
          ksSay(context, l10n?.sshCommandDeleted ?? 'Command deleted');
        }
      },
      onAdd: () => _showSaveDialog('', controller, l10n),
      onImport: () => _importSavedCommands(controller, l10n),
    );
  }

  Future<void> _importSavedCommands(
    SshConsoleController controller,
    AppLocalizations? l10n,
  ) async {
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        pickerAttempted = true;
      } catch (e, stack) {
        Logger.exception('FilePicker custom extension failed', e, stack);
      }

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (e, stack) {
          Logger.exception('FilePicker any fallback failed', e, stack);
          return;
        }
      }

      if (pickedFile == null) return;

      String? content;
      try {
        final bytes = await pickedFile.readAsBytes();
        if (bytes.isNotEmpty) {
          content = utf8.decode(bytes);
        }
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            content = await File(pickedFile.path!).readAsString();
          } catch (e, stack) {
            Logger.exception('Reading file from path failed', e, stack);
          }
        }
      }

      if (content == null || content.trim().isEmpty) {
        if (mounted) {
          ksSay(
            context,
            l10n?.sshImportCommandsEmpty ?? 'The selected file is empty.',
          );
        }
        return;
      }

      final count = await controller.importCommands(content);
      if (!mounted) return;

      if (count > 0) {
        ksSay(
          context,
          l10n?.sshImportCommandsSuccess(count) ?? 'Imported $count command(s)',
        );
      } else {
        ksSay(
          context,
          l10n?.sshImportCommandsNoValid ??
              'No valid SSH commands found in JSON.',
        );
      }
    } catch (e) {
      if (mounted) {
        ksSay(context, 'Import failed: $e');
      }
    }
  }

  String _statusLabel(SshSessionStatus status) => switch (status) {
    SshSessionStatus.connected => 'Connected',
    SshSessionStatus.connecting => 'Connecting…',
    SshSessionStatus.authFailed => "Couldn't sign in",
    SshSessionStatus.connectionFailed => "Can't reach the router",
    SshSessionStatus.disconnected => 'Disconnected',
  };

  Color _statusColor(SshSessionStatus status) {
    final ks = context.ks;
    return switch (status) {
      SshSessionStatus.connected => ks.ok,
      SshSessionStatus.connecting => ks.warn,
      SshSessionStatus.authFailed ||
      SshSessionStatus.connectionFailed => ks.bad,
      SshSessionStatus.disconnected => ks.mu,
    };
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final router = ref.watch(appStateProvider.select((s) => s.selectedRouter));
    final routerId = router?.id ?? '';
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(sshConsoleControllerProvider(routerId));
    final controller = ref.read(
      sshConsoleControllerProvider(routerId).notifier,
    );
    final live = state.sessionStatus.isConnected;
    final failed = state.sessionStatus == SshSessionStatus.authFailed;
    final ask = failed && !controller.hasPassword;

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Row(
          children: [
            KsDot(ask ? ks.warn : _statusColor(state.sessionStatus)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Terminal · ${ask ? 'Needs the password' : _statusLabel(state.sessionStatus)}',
                overflow: TextOverflow.ellipsis,
                style: KeystoneType.body(ks.tx),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: state.savedCommands.isNotEmpty,
              label: Text('${state.savedCommands.length}'),
              child: const Icon(Icons.bookmarks_outlined),
            ),
            tooltip: 'Saved commands',
            onPressed: () =>
                _showSavedCommandsSheet(state.savedCommands, controller, l10n),
          ),
          PopupMenuButton<int>(
            tooltip: 'More',
            color: ks.sheet,
            onSelected: (v) => v == 0
                ? _copyAll(controller.getAllText())
                : _clearBuffer(controller),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 0,
                child: Text('Copy everything', style: KeystoneType.body(ks.tx)),
              ),
              PopupMenuItem(
                value: 1,
                child: Text(
                  'Clear the screen',
                  style: KeystoneType.body(ks.tx),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (ask || failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    ask
                        ? 'Enter the router password to open the terminal. '
                              'It is used for this session only.'
                        : "That password didn't work for the terminal.",
                    style: KeystoneType.secondary(
                      failed && !ask ? ks.bad : ks.tx2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _password,
                          obscureText: true,
                          autofocus: true,
                          onSubmitted: (v) =>
                              v.isEmpty ? null : controller.signIn(v),
                          decoration: ksInput(context, hint: 'Router password'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _password.text.isEmpty
                            ? null
                            : controller.signIn(_password.text),
                        child: const Text('Open'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else if (!_noteDismissed && live)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'This is one session: cd and exports carry over. '
                      'Leaving the screen ends it.',
                      style: KeystoneType.caption(ks.mu),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide',
                    icon: Icon(Icons.close_rounded, size: 18, color: ks.mu),
                    onPressed: () => setState(() => _noteDismissed = true),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TerminalView(
              controller.terminal,
              controller: _terminalController,
              focusNode: _terminalFocusNode,
              autofocus: live,
              autoResize: true,
              deleteDetection: true,
              cursorType: TerminalCursorType.block,
              keyboardType: TextInputType.emailAddress,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              theme: TerminalTheme(
                cursor: ks.ac,
                selection: ks.ac.withValues(alpha: 0.35),
                foreground: ks.tx,
                background: ks.bg,
                black: const Color(0XFF1E1E1E),
                red: const Color(0XFFCD3131),
                green: const Color(0XFF0DBC79),
                yellow: const Color(0XFFE5E510),
                blue: const Color(0XFF2472C8),
                magenta: const Color(0XFFBC3FBC),
                cyan: const Color(0XFF11A8CD),
                white: const Color(0XFFE5E5E5),
                brightBlack: const Color(0XFF666666),
                brightRed: const Color(0XFFF14C4C),
                brightGreen: const Color(0XFF23D18B),
                brightYellow: const Color(0XFFF5F543),
                brightBlue: const Color(0XFF3B8EEA),
                brightMagenta: const Color(0XFFD670D6),
                brightCyan: const Color(0XFF29B8DB),
                brightWhite: const Color(0XFFFFFFFF),
                searchHitBackground: const Color(0XFFFFFF2B),
                searchHitBackgroundCurrent: const Color(0XFF31FF26),
                searchHitForeground: const Color(0XFF000000),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: ks.bg,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 6,
                  children: [
                    if (!live && !failed)
                      FilledButton(
                        onPressed: controller.reconnect,
                        child: const Text('Reconnect'),
                      ),
                    _key(
                      label: 'Ctrl+C',
                      tooltip: 'Stop what is running',
                      color: ks.bad,
                      onPressed: live
                          ? () {
                              unawaited(HapticFeedback.lightImpact());
                              controller.sendCtrlC();
                            }
                          : null,
                    ),
                    _key(
                      label: 'Esc',
                      tooltip: 'Escape',
                      onPressed: live ? controller.sendEscape : null,
                    ),
                    _key(
                      label: 'Tab',
                      tooltip: 'Finish the word',
                      onPressed: live ? controller.sendTab : null,
                    ),
                    _key(
                      icon: Icons.keyboard_arrow_up_rounded,
                      tooltip: 'Up, the last command',
                      onPressed: live ? controller.sendArrowUp : null,
                    ),
                    _key(
                      icon: Icons.keyboard_arrow_down_rounded,
                      tooltip: 'Down',
                      onPressed: live ? controller.sendArrowDown : null,
                    ),
                    _key(
                      icon: Icons.keyboard_arrow_left_rounded,
                      tooltip: 'Left',
                      onPressed: live ? controller.sendArrowLeft : null,
                    ),
                    _key(
                      icon: Icons.keyboard_arrow_right_rounded,
                      tooltip: 'Right',
                      onPressed: live ? controller.sendArrowRight : null,
                    ),
                    _key(
                      icon: _terminalFocusNode.hasFocus
                          ? Icons.keyboard_hide_outlined
                          : Icons.keyboard_outlined,
                      tooltip: _terminalFocusNode.hasFocus
                          ? 'Hide the keyboard'
                          : 'Show the keyboard',
                      onPressed: () => _terminalFocusNode.hasFocus
                          ? _terminalFocusNode.unfocus()
                          : _terminalFocusNode.requestFocus(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
