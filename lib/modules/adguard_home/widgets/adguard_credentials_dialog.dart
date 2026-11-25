// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_api_models.dart';

class AdGuardCredentialsDialog extends StatefulWidget {
  final AdGuardController controller;

  const AdGuardCredentialsDialog({super.key, required this.controller});

  static Future<bool?> show(
    BuildContext context, {
    required AdGuardController controller,
  }) {
    return ksSheet<bool>(
      context,
      (_) => AdGuardCredentialsDialog(controller: controller),
    );
  }

  @override
  State<AdGuardCredentialsDialog> createState() =>
      _AdGuardCredentialsDialogState();
}

class _AdGuardCredentialsDialogState extends State<AdGuardCredentialsDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Enter the name.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final creds = AdGuardCredentials(username: username, password: password);
      final success = await widget.controller.setCredentials(creds);
      if (!mounted) return;
      if (!success) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Authentication failed. Invalid username or password.';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sign in to AdGuard Home', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'The name and password you set in AdGuard Home, not the router\'s.',
          style: KeystoneType.secondary(ks.mu),
        ),
        KsField(
          key: const Key('agh_credentials_username_field'),
          label: 'Name',
          controller: _usernameController,
          enabled: !_isSubmitting,
        ),
        KsField(
          key: const Key('agh_credentials_password_field'),
          label: 'Password',
          controller: _passwordController,
          obscure: _obscurePassword,
          enabled: !_isSubmitting,
          suffix: IconButton(
            tooltip: _obscurePassword ? 'Show password' : 'Hide password',
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: ks.mu,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        if (_errorMessage != null) KsBanner(_errorMessage!, bad: true),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('agh_credentials_submit_button'),
          onPressed: _isSubmitting ? null : _submit,
          child: Text(_isSubmitting ? 'Signing in…' : 'Sign in'),
        ),
      ],
    );
  }
}
