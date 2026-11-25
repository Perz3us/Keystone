// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

class AdGuardProfileDialog extends StatefulWidget {
  final AdGuardController controller;
  final AdGuardInstanceProfile? initialProfile;

  const AdGuardProfileDialog({
    super.key,
    required this.controller,
    this.initialProfile,
  });

  static Future<AdGuardInstanceProfile?> show(
    BuildContext context, {
    required AdGuardController controller,
    AdGuardInstanceProfile? initialProfile,
  }) {
    return ksFormRoute<AdGuardInstanceProfile>(
      context,
      AdGuardProfileDialog(
        controller: controller,
        initialProfile: initialProfile,
      ),
    );
  }

  @override
  State<AdGuardProfileDialog> createState() => _AdGuardProfileDialogState();
}

class _AdGuardProfileDialogState extends State<AdGuardProfileDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _useHttps = false;
  bool _obscurePassword = true;
  bool _isTesting = false;
  bool _isSaving = false;
  bool _testCredsProvided = false;
  AdGuardConnectionStatus? _testStatus;
  String? _testMessage;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameController = TextEditingController(text: p?.name ?? '');
    _hostController = TextEditingController(text: p?.host ?? '');
    _portController = TextEditingController(text: '${p?.port ?? 3000}');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _useHttps = p?.useHttps ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static ({String host, int? port, bool? useHttps}) sanitizeHostInput(
    String input,
  ) {
    var raw = input.trim();
    bool? useHttps;
    if (raw.startsWith('https://')) {
      useHttps = true;
      raw = raw.substring(8);
    } else if (raw.startsWith('http://')) {
      useHttps = false;
      raw = raw.substring(7);
    }

    final slashIdx = raw.indexOf('/');
    if (slashIdx != -1) {
      raw = raw.substring(0, slashIdx);
    }
    raw = raw.trim();

    int? port;
    String host = raw;

    if (raw.startsWith('[')) {
      final closeBracket = raw.indexOf(']');
      if (closeBracket != -1) {
        final inside = raw.substring(1, closeBracket);
        final after = raw.substring(closeBracket + 1);
        host = inside;
        if (after.startsWith(':')) {
          final p = int.tryParse(after.substring(1));
          if (p != null && p > 0 && p <= 65535) {
            port = p;
          }
        }
      }
    } else if (raw.contains(':')) {
      final parts = raw.split(':');
      if (parts.length == 2) {
        final p = int.tryParse(parts[1]);
        if (p != null && p > 0 && p <= 65535) {
          host = parts[0];
          port = p;
        }
      }
    }

    return (host: host.trim(), port: port, useHttps: useHttps);
  }

  static bool isValidHost(String host) {
    if (host.isEmpty) return false;
    final ipv4Regex = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4Regex.hasMatch(host)) {
      final octets = host.split('.').map(int.tryParse);
      return octets.every((o) => o != null && o >= 0 && o <= 255);
    }
    final cleanIpv6 = host.replaceAll('[', '').replaceAll(']', '');
    if (cleanIpv6.contains(':')) {
      final ipv6Regex = RegExp(r'^[0-9a-fA-F:]+$');
      return ipv6Regex.hasMatch(cleanIpv6);
    }
    final hostnameRegex = RegExp(
      r'^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$',
    );
    return hostnameRegex.hasMatch(host);
  }

  Future<void> _runConnectionTest() async {
    final parsed = sanitizeHostInput(_hostController.text);
    if (parsed.port != null) {
      _portController.text = '${parsed.port}';
    }
    if (parsed.useHttps != null) {
      setState(() {
        _useHttps = parsed.useHttps!;
      });
    }
    _hostController.text = parsed.host;

    if (!_formKey.currentState!.validate()) return;

    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isTesting = true;
      _testStatus = null;
      _testMessage = null;
    });

    try {
      final status = await widget.controller.testProfileConnection(
        host: host,
        port: port,
        useHttps: _useHttps,
        username: username.isNotEmpty ? username : null,
        password: password.isNotEmpty ? password : null,
      );

      if (!mounted) return;

      final hasCreds = username.isNotEmpty || password.isNotEmpty;
      _testCredsProvided = hasCreds;

      setState(() {
        _isTesting = false;
        _testStatus = status;
        switch (status) {
          case AdGuardConnectionStatus.authenticated:
            _testMessage = 'It answers, and the sign-in works.';
            break;
          case AdGuardConnectionStatus.authRequired:
            _testMessage = hasCreds
                ? 'Authentication failed. Invalid username or password.'
                : 'It needs a name and password.';
            break;
          case AdGuardConnectionStatus.apiUnreachable:
            _testMessage =
                'No answer. Check the address, the port and that the device is on.';
            break;
          case AdGuardConnectionStatus.invalidEndpoint:
            _testMessage =
                'Something answers there, but it isn\'t AdGuard Home.';
            break;
          default:
            _testMessage = 'The check didn\'t work. Try again.';
            break;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTesting = false;
        _testStatus = AdGuardConnectionStatus.apiUnreachable;
        _testMessage = 'The check didn\'t work. Try again.';
      });
    }
  }

  Future<void> _save() async {
    final parsed = sanitizeHostInput(_hostController.text);
    if (parsed.port != null) {
      _portController.text = '${parsed.port}';
    }
    if (parsed.useHttps != null) {
      setState(() {
        _useHttps = parsed.useHttps!;
      });
    }
    _hostController.text = parsed.host;

    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 3000;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSaving = true;
    });

    try {
      final profileId =
          widget.initialProfile?.id ??
          'ext_${DateTime.now().millisecondsSinceEpoch}';
      final profile = AdGuardInstanceProfile.external(
        id: profileId,
        name: name,
        host: host,
        port: port,
        useHttps: _useHttps,
      );

      if (widget.initialProfile != null) {
        await widget.controller.updateProfile(
          profile,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      } else {
        await widget.controller.addExternalProfile(
          profile,
          username: username.isNotEmpty ? username : null,
          password: password.isNotEmpty ? password : null,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(profile);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ksSay(context, 'Couldn\'t save it. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final ok = _testStatus == AdGuardConnectionStatus.authenticated;
    return KsFormPage(
      title: widget.initialProfile != null
          ? 'Edit this AdGuard Home'
          : 'AdGuard Home on another device',
      subtitle: 'For one that runs on a Raspberry Pi, a NAS or a computer',
      action: 'Save',
      actionKey: const Key('agh_save_profile_button'),
      busy: _isSaving,
      onAction: _isTesting ? null : _save,
      formKey: _formKey,
      children: [
        KsField(
          key: const Key('agh_profile_name_field'),
          label: 'Name',
          controller: _nameController,
          hint: 'Raspberry Pi',
          validator: (v) =>
              v == null || v.trim().isEmpty ? 'Please enter a name' : null,
        ),
        KsField(
          key: const Key('agh_profile_host_field'),
          label: 'Address',
          controller: _hostController,
          hint: '192.168.1.129',
          keyboardType: TextInputType.url,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Host is required';
            if (!isValidHost(sanitizeHostInput(v).host)) {
              return 'Enter a valid IP address or hostname';
            }
            return null;
          },
        ),
        KsField(
          key: const Key('agh_profile_port_field'),
          label: 'Port',
          controller: _portController,
          hint: '3000',
          keyboardType: TextInputType.number,
          validator: (v) {
            final port = int.tryParse(v?.trim() ?? '');
            return port == null || port < 1 || port > 65535
                ? 'A number from 1 to 65535'
                : null;
          },
        ),
        const SizedBox(height: 8),
        KsSwitchRow(
          key: const Key('agh_profile_https_switch'),
          title: 'Use HTTPS',
          value: _useHttps,
          onChanged: (v) => setState(() => _useHttps = v),
        ),
        const KsSection('Sign-in, if it has one'),
        KsField(
          key: const Key('agh_profile_username_field'),
          label: 'Name',
          controller: _usernameController,
        ),
        KsField(
          key: const Key('agh_profile_password_field'),
          label: 'Password',
          controller: _passwordController,
          obscure: _obscurePassword,
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
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('agh_test_connection_button'),
          onPressed: _isTesting ? null : _runConnectionTest,
          child: Text(_isTesting ? 'Checking…' : 'Check it works'),
        ),
        if (_testStatus != null && _testMessage != null)
          Padding(
            key: const Key('agh_test_status_indicator'),
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                KsDot(ok ? ks.ok : (_testCredsProvided ? ks.bad : ks.warn)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _testMessage!,
                    style: KeystoneType.secondary(ok ? ks.tx2 : ks.warnTx),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
