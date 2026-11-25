// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

class LuciGuardrail {
  static Future<bool> confirmStagedChangesOrExit(
    BuildContext context,
    AppState appState, {
    String title = 'Keep the Wi-Fi change?',
    String? subtitle,
    String revertLabel = 'Undo',
    String confirmLabel = 'Keep it',
  }) async {
    if (!appState.isAccessControlPendingConfirmation) return true;
    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
    final action = await _dialog<String>(
      context,
      title: title,
      body: Text(
        subtitle ??
            'You changed who can join the Wi-Fi. Keep the change, or put '
                'the old settings back before you leave.',
        style: KeystoneType.body(context.ks.tx2),
      ),
      dismissible: false,
      actions: (c) => [
        TextButton(
          onPressed: () => Navigator.pop(c, 'revert'),
          child: Text(revertLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'confirm'),
          child: Text(confirmLabel),
        ),
      ],
    );
    if (action == 'revert') {
      if (context.mounted) {
        await appState.revertWifiAccessControlChanges(context: context);
      }
      return true;
    }
    if (action == 'confirm') {
      await appState.confirmWifiAccessControlChanges();
      return true;
    }
    return false;
  }

  static Future<bool> showConfirmation(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? customContent,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    IconData? icon,
    Color? iconColor,
    bool isDestructive = false,
    OsHapticType hapticType = OsHapticType.medium,
    bool barrierDismissible = true,
  }) async {
    if (!context.mounted) return false;
    unawaited(OsPlatformIntegration.triggerHaptic(hapticType));
    final ks = context.ks;
    final ok = await _dialog<bool>(
      context,
      title: title,
      body:
          customContent ??
          (subtitle == null
              ? null
              : Text(subtitle, style: KeystoneType.body(ks.tx2))),
      dismissible: barrierDismissible,
      actions: (c) => [
        if (cancelLabel.isNotEmpty)
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(cancelLabel, style: KeystoneType.body(ks.tx)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(c, true),
          child: Text(
            confirmLabel,
            style: KeystoneType.body(isDestructive ? ks.bad : ks.ac),
          ),
        ),
      ],
    );
    return ok ?? false;
  }

  static Future<T?> _dialog<T>(
    BuildContext context, {
    required String title,
    Widget? body,
    required bool dismissible,
    required List<Widget> Function(BuildContext) actions,
  }) {
    final ks = context.ks;
    return showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text(title, style: KeystoneType.sheetTitle(ks.tx)),
        content: body == null ? null : SingleChildScrollView(child: body),
        actions: actions(c),
      ),
    );
  }
}
