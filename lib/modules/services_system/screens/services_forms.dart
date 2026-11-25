// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../models/ddns_info.dart';

class CronPreset {
  final String id;
  final String label;
  final String expression;
  const CronPreset(this.id, this.label, this.expression);

  String getLocalizedLabel(AppLocalizations? l10n) {
    switch (id) {
      case 'every_5_min':
        return l10n?.cronPresetEvery5Min ?? label;
      case 'every_15_min':
        return l10n?.cronPresetEvery15Min ?? label;
      case 'every_hour':
        return l10n?.cronPresetEveryHour ?? label;
      case 'every_day_midnight':
        return l10n?.cronPresetEveryDayMidnight ?? label;
      case 'every_day_4am':
        return l10n?.cronPresetEveryDay4Am ?? label;
      case 'every_weekday_midnight':
        return l10n?.cronPresetEveryWeekdayMidnight ?? label;
      case 'every_sunday_midnight':
        return l10n?.cronPresetEverySundayMidnight ?? label;
      case 'first_day_month_midnight':
        return l10n?.cronPresetFirstDayMonthMidnight ?? label;
      case 'custom':
        return l10n?.cronPresetCustomExpression ?? label;
      default:
        return label;
    }
  }
}

const List<CronPreset> kCronPresets = [
  CronPreset('every_5_min', 'Every 5 Minutes', '*/5 * * * *'),
  CronPreset('every_15_min', 'Every 15 Minutes', '*/15 * * * *'),
  CronPreset('every_hour', 'Every Hour', '0 * * * *'),
  CronPreset(
    'every_day_midnight',
    'Every Day at Midnight (12:00 AM)',
    '0 0 * * *',
  ),
  CronPreset('every_day_4am', 'Every Day at 4:00 AM', '0 4 * * *'),
  CronPreset(
    'every_weekday_midnight',
    'Every Weekday (Mon-Fri) at Midnight',
    '0 0 * * 1-5',
  ),
  CronPreset('every_sunday_midnight', 'Every Sunday at Midnight', '0 0 * * 0'),
  CronPreset(
    'first_day_month_midnight',
    'First Day of Every Month at Midnight',
    '0 0 1 * *',
  ),
  CronPreset('custom', 'Custom Expression', ''),
];

class CronValidator {
  static String? validateExpression(String expr) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) return 'Cron expression cannot be empty';

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length != 5) {
      return 'Must contain 5 fields: minute hour day-of-month month day-of-week';
    }

    final fields = [
      (parts[0], 'Minute', 0, 59),
      (parts[1], 'Hour', 0, 23),
      (parts[2], 'Day of Month', 1, 31),
      (parts[3], 'Month', 1, 12),
      (parts[4], 'Day of Week', 0, 7),
    ];

    for (final f in fields) {
      final err = _validateField(f.$1, f.$2, f.$3, f.$4);
      if (err != null) return err;
    }

    return null;
  }

  static String? _validateField(String value, String name, int min, int max) {
    if (value == '*') return null;

    if (value.contains('/')) {
      final subparts = value.split('/');
      if (subparts.length != 2) return 'Invalid step format in $name';
      final step = int.tryParse(subparts[1]);
      if (step == null || step <= 0) return 'Invalid step number in $name';
      if (subparts[0] != '*') {
        final err = _validateField(subparts[0], name, min, max);
        if (err != null) return err;
      }
      return null;
    }

    if (value.contains(',')) {
      for (final item in value.split(',')) {
        final err = _validateField(item, name, min, max);
        if (err != null) return err;
      }
      return null;
    }

    if (value.contains('-')) {
      final range = value.split('-');
      if (range.length != 2) return 'Invalid range in $name';
      final start = int.tryParse(range[0]);
      final end = int.tryParse(range[1]);
      if (start == null || end == null) return 'Invalid range numbers in $name';
      if (start < min || start > max || end < min || end > max) {
        return '$name range must be between $min and $max';
      }
      if (start > end) return '$name start cannot exceed end';
      return null;
    }

    final numVal = int.tryParse(value);
    if (numVal == null) return 'Invalid character in $name';
    if (numVal < min || numVal > max) {
      return '$name must be between $min and $max';
    }

    return null;
  }

  static String describeSchedule(String expr, [AppLocalizations? l10n]) {
    final trimmed = expr.trim();
    if (validateExpression(trimmed) != null) {
      return l10n?.cronCustomSchedule ?? 'Custom schedule';
    }

    for (final preset in kCronPresets) {
      if (preset.expression == trimmed) {
        return preset.getLocalizedLabel(l10n);
      }
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 5) {
      final min = parts[0];
      final hour = parts[1];
      final dom = parts[2];
      final mon = parts[3];
      final dow = parts[4];

      if (min == '*' && hour == '*' && dom == '*' && mon == '*' && dow == '*') {
        return l10n?.cronRunsEveryMinute ?? 'Runs every minute';
      }
      if (min.startsWith('*/') &&
          hour == '*' &&
          dom == '*' &&
          mon == '*' &&
          dow == '*') {
        final step = min.substring(2);
        return l10n?.cronRunsEveryXMinutes(step) ?? 'Runs every $step minutes';
      }
      if (hour.startsWith('*/') && dom == '*' && mon == '*' && dow == '*') {
        final step = hour.substring(2);
        final m = int.tryParse(min) ?? 0;
        final mStr = m.toString().padLeft(2, '0');
        return l10n?.cronRunsEveryXHoursAt(step, mStr) ??
            'Runs every $step hours at :$mStr';
      }

      final h = int.tryParse(hour);
      final m = int.tryParse(min);

      if (h != null && m != null) {
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
        final mStr = m.toString().padLeft(2, '0');
        final timeStr = '$h12:$mStr $period';

        if (dom == '*' && mon == '*' && dow == '*') {
          return l10n?.cronRunsEveryDayAt(timeStr) ??
              'Runs every day at $timeStr';
        }
        if (dom == '*' && mon == '*' && (dow == '0' || dow == '7')) {
          return l10n?.cronRunsEverySundayAt(timeStr) ??
              'Runs every Sunday at $timeStr';
        }
        if (dom == '*' && mon == '*' && dow == '1-5') {
          return l10n?.cronRunsOnWeekdaysAt(timeStr) ??
              'Runs on weekdays (Mon-Fri) at $timeStr';
        }
        if (dom != '*' && mon == '*' && dow == '*') {
          return l10n?.cronRunsOnDayOfMonthAt(dom, timeStr) ??
              'Runs on day $dom of every month at $timeStr';
        }
      }
    }
    return l10n?.cronRunsOnSchedule(trimmed) ?? 'Runs on schedule ($trimmed)';
  }

  static String? validateCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return 'Command cannot be empty';
    if (trimmed.contains('\n') || trimmed.contains('\r')) {
      return 'Command cannot contain newlines';
    }
    if (trimmed.length > 500) {
      return 'Command is too long (max 500 characters)';
    }
    return null;
  }

  static String? checkDangerousCommandWarning(String command) {
    final lower = command.toLowerCase();
    if (lower.contains('rm -rf /') ||
        lower.contains('rm -rf *') ||
        lower.contains('mkfs')) {
      return 'CAUTION: This command contains potentially destructive removal operations!';
    }
    if (lower.contains('dd if=') && lower.contains('of=/dev/')) {
      return 'CAUTION: Direct raw disk writes detected!';
    }
    return null;
  }
}

class DdnsEditDialog extends StatefulWidget {
  final DdnsInstance? existingInstance;
  final Future<bool> Function(DdnsInstance instance) onSave;
  final Future<DdnsValidationResult> Function(DdnsInstance instance) onTest;

  const DdnsEditDialog({
    super.key,
    this.existingInstance,
    required this.onSave,
    required this.onTest,
  });

  @override
  State<DdnsEditDialog> createState() => DdnsEditDialogState();
}

class DdnsEditDialogState extends State<DdnsEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _lookupHostController;
  late TextEditingController _domainController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _updateUrlController;
  late TextEditingController _ipUrlController;
  late TextEditingController _checkIntervalController;
  late TextEditingController _forceIntervalController;

  late String _selectedServiceName;
  late String _interface;
  late String _ipSource;
  late String _checkUnit;
  late String _forceUnit;
  late bool _enabled;
  late bool _useHttps;
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isTesting = false;
  DdnsValidationResult? _testResult;

  @override
  void initState() {
    super.initState();
    final inst = widget.existingInstance;
    _selectedServiceName =
        inst?.serviceName ?? kDdnsProviderPresets.first.serviceName;
    _nameController = TextEditingController(text: inst?.name ?? 'myddns_ipv4');
    _lookupHostController = TextEditingController(text: inst?.lookupHost ?? '');
    _domainController = TextEditingController(text: inst?.domain ?? '');
    _usernameController = TextEditingController(text: inst?.username ?? '');
    _passwordController = TextEditingController(text: inst?.password ?? '');
    _updateUrlController = TextEditingController(text: inst?.updateUrl ?? '');
    _ipUrlController = TextEditingController(
      text: (inst?.ipUrl != null && inst!.ipUrl.isNotEmpty)
          ? inst.ipUrl
          : 'https://ipv4.icanhazip.com',
    );
    _checkIntervalController = TextEditingController(
      text: (inst?.checkInterval ?? 10).toString(),
    );
    _forceIntervalController = TextEditingController(
      text: (inst?.forceInterval ?? 24).toString(),
    );

    _interface = inst?.interface ?? 'wan';
    _ipSource = inst?.ipSource ?? 'web';
    _checkUnit = inst?.checkUnit ?? 'minutes';
    _forceUnit = inst?.forceUnit ?? 'hours';
    _enabled = inst?.enabled ?? true;
    _useHttps = inst?.useHttps ?? true;
  }

  bool get _isDirty {
    if (widget.existingInstance == null) return true;
    final inst = widget.existingInstance!;
    return _nameController.text.trim() != inst.name ||
        _lookupHostController.text.trim() != inst.lookupHost ||
        _domainController.text.trim() != inst.domain ||
        _usernameController.text.trim() != inst.username ||
        _passwordController.text.trim() != inst.password ||
        _selectedServiceName != inst.serviceName ||
        _interface != inst.interface ||
        _ipSource != inst.ipSource ||
        _ipUrlController.text.trim() != inst.ipUrl ||
        _updateUrlController.text.trim() != inst.updateUrl ||
        _checkIntervalController.text.trim() != inst.checkInterval.toString() ||
        _checkUnit != inst.checkUnit ||
        _enabled != inst.enabled ||
        _useHttps != inst.useHttps;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lookupHostController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _updateUrlController.dispose();
    _ipUrlController.dispose();
    _checkIntervalController.dispose();
    _forceIntervalController.dispose();
    super.dispose();
  }

  DdnsProviderPreset get _currentPreset => kDdnsProviderPresets.firstWhere(
    (p) => p.serviceName == _selectedServiceName,
    orElse: () => kDdnsProviderPresets.last,
  );

  DdnsInstance _buildCurrentInstance() {
    return DdnsInstance(
      name: _nameController.text.trim(),
      enabled: _enabled,
      serviceName: _selectedServiceName,
      lookupHost: _lookupHostController.text.trim(),
      domain: _domainController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text.trim(),
      interface: _interface,
      ipSource: _ipSource,
      ipUrl: _ipUrlController.text.trim(),
      updateUrl: _updateUrlController.text.trim(),
      useHttps: _useHttps,
      checkInterval: int.tryParse(_checkIntervalController.text) ?? 10,
      checkUnit: _checkUnit,
      forceInterval: int.tryParse(_forceIntervalController.text) ?? 24,
      forceUnit: _forceUnit,
    );
  }

  Future<void> _runTest() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final testRes = await widget.onTest(_buildCurrentInstance());
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = testRes;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final ok = await widget.onSave(_buildCurrentInstance());
    if (mounted) {
      setState(() => _isSaving = false);
      if (ok) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final preset = _currentPreset;
    final isEditing = widget.existingInstance != null;
    final busy = _isSaving || _isTesting;
    final test = _testResult;
    const urls = [
      ('https://ipv4.icanhazip.com', 'icanhazip'),
      ('https://api.ipify.org', 'ipify'),
      ('http://checkip.dyndns.com', 'DynDNS'),
      ('http://checkipv6.dyndns.com', 'DynDNS IPv6'),
    ];

    return KsFormPage(
      title: isEditing ? 'Change the name' : 'Add a name',
      subtitle: 'A web address that follows this router',
      action: 'Save',
      busy: _isSaving,
      formKey: _formKey,
      onAction: busy || (isEditing && !_isDirty) ? null : _save,
      children: [
        KsChoice<String>(
          label: 'Name service',
          value: _selectedServiceName,
          options: [
            for (final p in kDdnsProviderPresets) (p.serviceName, p.label),
          ],
          onChanged: (v) => setState(() => _selectedServiceName = v),
        ),
        KsField(
          label: 'Your web address',
          controller: _lookupHostController,
          hint: preset.lookupHostHint,
          onChanged: (_) => setState(() {}),
          validator: (v) => (v ?? '').trim().isEmpty
              ? 'Enter the address to keep up to date.'
              : null,
        ),
        KsField(
          label: 'Domain at the service',
          controller: _domainController,
          hint: preset.domainHint,
          onChanged: (_) => setState(() {}),
        ),
        KsField(
          label: 'User name or ID',
          controller: _usernameController,
          hint: preset.usernameHint,
          onChanged: (_) => setState(() {}),
        ),
        KsField(
          label: 'Password or token',
          controller: _passwordController,
          hint: preset.passwordHint,
          obscure: _obscurePassword,
          onChanged: (_) => setState(() {}),
          suffix: IconButton(
            tooltip: _obscurePassword ? 'Show' : 'Hide',
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
        if (preset.requiresCustomUrl)
          KsField(
            label: 'Update link',
            controller: _updateUrlController,
            hint: 'https://…/update?host=[DOMAIN]&ip=[IP]',
            help: '[USERNAME], [PASSWORD], [DOMAIN] and [IP] are filled in',
            onChanged: (_) => setState(() {}),
          ),
        KsSwitchRow(
          title: 'On',
          subtitle: 'Keep this name up to date',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const KsSection('How it finds your address'),
        KsChoice<String>(
          label: 'Look it up',
          value: _ipSource,
          options: const [
            ('web', 'Ask a website (works behind the mobile network)'),
            ('network', 'From a router connection'),
            ('interface', 'From a network device'),
          ],
          onChanged: (v) => setState(() => _ipSource = v),
        ),
        if (_ipSource == 'web') ...[
          KsField(
            label: 'Website that tells it',
            controller: _ipUrlController,
            hint: 'https://ipv4.icanhazip.com',
            onChanged: (_) => setState(() {}),
            validator: (v) => _ipSource == 'web' && (v ?? '').trim().isEmpty
                ? 'Enter a website.'
                : null,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (u, l) in urls)
                ChoiceChip(
                  label: Text(l),
                  selected: _ipUrlController.text.trim() == u,
                  onSelected: (_) => setState(() => _ipUrlController.text = u),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ] else
          KsChoice<String>(
            label: 'Connection',
            value: _interface,
            options: [
              ('wan', 'Internet'),
              ('wan6', 'Internet (IPv6)'),
              ('lan', 'Home network'),
              if (!{'wan', 'wan6', 'lan'}.contains(_interface))
                (_interface, _interface),
            ],
            onChanged: (v) => setState(() => _interface = v),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: KsField(
                label: 'Check every',
                controller: _checkIntervalController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: KsChoice<String>(
                label: ' ',
                value: _checkUnit,
                options: const [
                  ('minutes', 'minutes'),
                  ('hours', 'hours'),
                  ('days', 'days'),
                ],
                onChanged: (v) => setState(() => _checkUnit = v),
              ),
            ),
          ],
        ),
        KsSwitchRow(
          title: 'Send it securely (HTTPS)',
          value: _useHttps,
          onChanged: (v) => setState(() => _useHttps = v),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: busy ? null : _runTest,
          child: Text(_isTesting ? 'Trying it…' : 'Try it now'),
        ),
        if (test != null) ...[
          const SizedBox(height: 12),
          KsBanner(
            test.isValid
                ? 'It works. The service took the update.'
                : (test.errorMessage ?? "It didn't work."),
            bad: !test.isValid,
          ),
          if (test.testOutput case final o? when o.trim().isNotEmpty)
            SelectableText(o.trim(), style: KeystoneType.address(ks.tx2)),
        ],
      ],
    );
  }
}
