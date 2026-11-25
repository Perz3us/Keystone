// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';

class ChangeRouterPasswordDialog extends StatefulWidget {
  const ChangeRouterPasswordDialog({super.key});

  static Future<bool?> show(BuildContext context) =>
      Navigator.of(context).push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const ChangeRouterPasswordDialog(),
        ),
      );

  @override
  State<ChangeRouterPasswordDialog> createState() =>
      _ChangeRouterPasswordDialogState();
}

class _ChangeRouterPasswordDialogState
    extends State<ChangeRouterPasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _allowShort = false;
  ChangePasswordStatus _status = ChangePasswordStatus.idle;
  String? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_current, _next, _again]) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [_current, _next, _again]) {
      c.removeListener(_changed);
      c.clear();
      c.dispose();
    }
    super.dispose();
  }

  bool get _busy => const {
    ChangePasswordStatus.validating,
    ChangePasswordStatus.requesting,
    ChangePasswordStatus.reauthenticating,
    ChangePasswordStatus.verifying,
    ChangePasswordStatus.savingStorage,
  }.contains(_status);

  bool get _short => _next.text.isNotEmpty && _next.text.length < 8;

  String? get _problem {
    if (_current.text.isEmpty || _next.text.isEmpty) return null;
    if (_next.text == _current.text) return "That's the password you have now.";
    if (_again.text.isNotEmpty && _again.text != _next.text) {
      return "The two new passwords don't match.";
    }
    return null;
  }

  bool get _canChange =>
      !_busy &&
      _status != ChangePasswordStatus.storageWarning &&
      _status != ChangePasswordStatus.ambiguous &&
      _current.text.isNotEmpty &&
      _next.text.isNotEmpty &&
      _again.text == _next.text &&
      _problem == null &&
      (!_short || _allowShort);

  Future<void> _change() async {
    final ok = await ksConfirm(
      context,
      title: 'Change the router password?',
      body:
          'Everyone signed in to the router is signed out. If you forget '
          'the new password, only a factory reset gets you back in.',
      action: 'Change it',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _status = ChangePasswordStatus.validating;
      _error = null;
    });
    final r = await AppState.instance.changeRouterPassword(
      currentPassword: _current.text,
      newPassword: _next.text,
      onProgress: (s) {
        if (mounted) setState(() => _status = s);
      },
    );
    if (!mounted) return;
    if (r.isSuccess && r.status == ChangePasswordStatus.success) {
      ksSay(context, 'Password changed.');
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _status = switch (r.status) {
        ChangePasswordStatus.storageWarning ||
        ChangePasswordStatus.ambiguous => r.status,
        _ => ChangePasswordStatus.failed,
      };
      _error = r.errorMessage;
    });
  }

  Future<void> _saveAgain() async {
    final router = AppState.instance.selectedRouter;
    if (router == null) return;
    setState(() => _retrying = true);
    final ok = await AppState.instance.retrySaveRouterPassword(router);
    if (!mounted) return;
    setState(() => _retrying = false);
    if (ok) {
      ksSay(context, 'Password changed and saved.');
      Navigator.of(context).pop(true);
    } else {
      ksSay(context, "It still couldn't be saved. Write the password down.");
    }
  }

  String get _progress => switch (_status) {
    ChangePasswordStatus.requesting => 'Changing it on the router…',
    ChangePasswordStatus.reauthenticating => 'Signing in with the new one…',
    ChangePasswordStatus.verifying => 'Checking it works…',
    ChangePasswordStatus.savingStorage => 'Saving it on this phone…',
    _ => 'Working…',
  };

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final eye = IconButton(
      tooltip: _show ? 'Hide passwords' : 'Show passwords',
      icon: Icon(
        _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: ks.mu,
      ),
      onPressed: () => setState(() => _show = !_show),
    );
    final done =
        _status == ChangePasswordStatus.storageWarning ||
        _status == ChangePasswordStatus.ambiguous;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: ks.bg,
        appBar: AppBar(
          backgroundColor: ks.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ks.tx,
          actions: [
            if (!done)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: _canChange ? _change : null,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              const KsTitle(
                'Router password',
                subtitle: 'The one you sign in to the router with',
              ),
              if (_status == ChangePasswordStatus.ambiguous) ...[
                const KsBanner(
                  "Keystone can't tell whether the password changed: the "
                  'router stopped answering halfway.',
                  bad: true,
                ),
                Text(
                  'Sign out, then sign in with the new password. If that '
                  "doesn't work, use the old one.",
                  style: KeystoneType.body(ks.tx2),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('OK'),
                ),
              ] else if (_status == ChangePasswordStatus.storageWarning) ...[
                const KsBanner(
                  'The password changed on the router, but this phone '
                  "couldn't save it. Write it down now.",
                ),
                if (_error != null)
                  Text(_error!, style: KeystoneType.secondary(ks.mu)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _retrying ? null : _saveAgain,
                  child: Text(_retrying ? 'Saving…' : 'Try saving it again'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("I've written it down"),
                ),
              ] else ...[
                KsField(
                  label: 'Current password',
                  controller: _current,
                  obscure: !_show,
                  enabled: !_busy,
                  suffix: eye,
                ),
                KsField(
                  label: 'New password',
                  controller: _next,
                  obscure: !_show,
                  enabled: !_busy,
                  help: '8 characters or more',
                ),
                PasswordStrengthMeter(password: _next.text),
                KsField(
                  label: 'New password again',
                  controller: _again,
                  obscure: !_show,
                  enabled: !_busy,
                ),
                if (_problem != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _problem!,
                      style: KeystoneType.secondary(ks.bad),
                    ),
                  ),
                if (_short)
                  KsSwitchRow(
                    title: 'Use a short password anyway',
                    subtitle: 'Shorter than 8 is easy to guess',
                    value: _allowShort,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _allowShort = v),
                  ),
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_progress, style: KeystoneType.body(ks.mu)),
                  ),
                if (_status == ChangePasswordStatus.failed)
                  KsBanner(
                    _error ?? "The router didn't change the password.",
                    bad: true,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
