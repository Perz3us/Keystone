// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

class AddSsidDialog extends ConsumerStatefulWidget {
  final List<WirelessRadio> radios;
  final WirelessRadio targetRadio;

  const AddSsidDialog({
    super.key,
    required this.radios,
    required this.targetRadio,
  });

  @override
  ConsumerState<AddSsidDialog> createState() => _AddSsidDialogState();
}

class _AddSsidDialogState extends ConsumerState<AddSsidDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController();
  final _passphraseController = TextEditingController();

  final _mobilityDomainController = TextEditingController(text: '4f4b');
  final _dtimPeriodController = TextEditingController(text: '2');
  final _gtkRekeyController = TextEditingController(text: '3600');
  final _inactivityLimitController = TextEditingController(text: '300');
  final _maxListenIntervalController = TextEditingController(text: '65535');
  final _maclistController = TextEditingController();

  final _dhcpStartController = TextEditingController(text: '100');
  final _dhcpLimitController = TextEditingController(text: '150');
  final _dhcpLeaseController = TextEditingController(text: '12h');
  final _dnsServersController = TextEditingController();
  String _ipv6Ra = 'server';
  String _dhcpv6Mode = 'server';
  bool _dhcpSettingsModified = false;

  late WirelessRadio _selectedRadio;

  String _selectedEncryption = 'sae-mixed';
  String _selectedNetwork = 'lan';
  String _selectedCipher = 'auto';
  String _selectedPmf = '1';
  List<String> _availableNetworks = ['lan', 'guest', 'wan'];

  bool _confirmOpenNetwork = false;

  bool _isolateClients = false;
  bool _isHidden = false;
  bool _wmmEnabled = true;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;
  bool _ieee80211k = false;
  bool _ieee80211v = false;

  String _macfilter = 'disable';

  bool _isSubmitting = false;
  bool _isLoadingCapabilities = false;
  bool _showPassphrase = false;
  bool _showAdvanced = false;

  List<Map<String, String>> _dynamicEncryptions = [];
  List<Map<String, String>> _dynamicCiphers = [];

  @override
  void initState() {
    super.initState();
    _selectedRadio = widget.targetRadio;
    _fetchAvailableNetworks();
    _fetchHardwareCapabilities();
    _loadSubnetDhcpDefaults();
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passphraseController.dispose();
    _mobilityDomainController.dispose();
    _dtimPeriodController.dispose();
    _gtkRekeyController.dispose();
    _inactivityLimitController.dispose();
    _maxListenIntervalController.dispose();
    _maclistController.dispose();
    _dhcpStartController.dispose();
    _dhcpLimitController.dispose();
    _dhcpLeaseController.dispose();
    _dnsServersController.dispose();
    super.dispose();
  }

  void _loadSubnetDhcpDefaults() {
    try {
      final appState = ref.read(appStateProvider);
      final rawDhcp =
          appState.dashboardData?['uciDhcpConfig'] ??
          appState.dashboardData?['dhcp'];
      if (rawDhcp is Map) {
        final values = (rawDhcp['values'] is Map)
            ? rawDhcp['values'] as Map
            : rawDhcp;
        values.forEach((k, v) {
          if (v is Map &&
              v['.type'] == 'dhcp' &&
              (v['interface'] == _selectedNetwork || k == _selectedNetwork)) {
            if (v['start'] != null) {
              _dhcpStartController.text = v['start'].toString();
            }
            if (v['limit'] != null) {
              _dhcpLimitController.text = v['limit'].toString();
            }
            if (v['leasetime'] != null) {
              _dhcpLeaseController.text = v['leasetime'].toString();
            }
            if (v['ra'] != null) _ipv6Ra = v['ra'].toString();
            if (v['dhcpv6'] != null) _dhcpv6Mode = v['dhcpv6'].toString();
            if (v['dns'] != null) {
              final dnsVal = v['dns'];
              _dnsServersController.text = dnsVal is List
                  ? dnsVal.join(', ')
                  : dnsVal.toString();
            }
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _selectedNetwork = _availableNetworks.first;
          }
        });
        _loadSubnetDhcpDefaults();
      }
    } catch (_) {}
  }

  Future<void> _fetchHardwareCapabilities() async {
    if (!mounted) return;
    setState(() => _isLoadingCapabilities = true);
    final appState = ref.read(appStateProvider);
    try {
      final refIface = _selectedRadio.interfaces.isNotEmpty
          ? _selectedRadio.interfaces.firstWhere(
              (i) => i.mode.toLowerCase() == 'ap',
              orElse: () => _selectedRadio.interfaces.first,
            )
          : null;

      final caps = await appState.fetchWirelessHardwareCapabilities(
        sectionName: refIface?.sectionName ?? _selectedRadio.name,
        radioName: _selectedRadio.name,
      );

      if (mounted) {
        setState(() {
          _dynamicEncryptions = caps['encryptions'] ?? [];
          _dynamicCiphers = caps['ciphers'] ?? [];
          _applySmartDefaults();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingCapabilities = false);
    }
  }

  void _applySmartDefaults() {
    if (_dynamicEncryptions.isEmpty) return;
    final supported = _dynamicEncryptions.map((e) => e['value']!).toList();
    for (final preferred in ['sae-mixed', 'psk2', 'psk', 'none']) {
      if (supported.contains(preferred)) {
        _selectedEncryption = preferred;
        break;
      }
    }
    _updateCipherForEncryption(_selectedEncryption);
  }

  void _updateCipherForEncryption(String enc) {
    if (enc == 'sae' || enc == 'sae-mixed') {
      _selectedCipher = 'ccmp';
      _selectedPmf = enc == 'sae' ? '2' : '1';
    } else if (enc == 'psk2') {
      _selectedCipher = 'ccmp';
      _selectedPmf = '1';
    } else if (enc == 'psk') {
      _selectedCipher = 'auto';
      _selectedPmf = '0';
    } else if (enc == 'owe') {
      _selectedCipher = 'ccmp';
      _selectedPmf = '2';
    } else {
      _selectedCipher = 'auto';
      _selectedPmf = '0';
    }
  }

  bool _requiresPassphrase() =>
      _selectedEncryption != 'none' && _selectedEncryption != 'owe';

  bool _isEncryptionSupported(String v) =>
      _dynamicEncryptions.isEmpty ||
      _dynamicEncryptions.any((e) => e['value'] == v);

  bool _isCipherSupported(String v) =>
      _dynamicCiphers.isEmpty || _dynamicCiphers.any((c) => c['value'] == v);

  String? _validatePassphrase(String? value) {
    if (!_requiresPassphrase()) return null;
    if (value == null || value.trim().isEmpty) return 'Passphrase is required';
    final t = value.trim();
    if (t.length < 8) return 'Passphrase must be at least 8 characters';
    if (t.length > 63) return 'Passphrase must not exceed 63 characters';
    return null;
  }

  bool _isFormValid() {
    if (_isSubmitting || _isLoadingCapabilities) return false;

    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return false;
    if (utf8.encode(ssid).length > 32) return false;

    final isDuplicate = _selectedRadio.interfaces
        .where((i) => i.mode.toLowerCase() == 'ap')
        .any((i) => i.ssid.trim().toLowerCase() == ssid.toLowerCase());
    if (isDuplicate) return false;

    if (_requiresPassphrase()) {
      final pass = _passphraseController.text.trim();
      if (pass.isEmpty || pass.length < 8 || pass.length > 63) return false;
    }

    if (_selectedEncryption == 'none' && !_confirmOpenNetwork) {
      return false;
    }

    if (_ieee80211r) {
      final mob = _mobilityDomainController.text.trim();
      if (mob.isEmpty || mob.length > 4) return false;
    }

    if (_dtimPeriodController.text.trim().isNotEmpty) {
      final dtim = int.tryParse(_dtimPeriodController.text.trim());
      if (dtim == null || dtim < 1 || dtim > 255) return false;
    }

    if (_gtkRekeyController.text.trim().isNotEmpty) {
      final rekey = int.tryParse(_gtkRekeyController.text.trim());
      if (rekey == null || rekey < 0) return false;
    }

    if (_inactivityLimitController.text.trim().isNotEmpty) {
      final inact = int.tryParse(_inactivityLimitController.text.trim());
      if (inact == null || inact < 0) return false;
    }

    if (_maxListenIntervalController.text.trim().isNotEmpty) {
      final listen = int.tryParse(_maxListenIntervalController.text.trim());
      if (listen == null || listen < 0) return false;
    }

    return true;
  }

  String _getNetworkLabel(String net) {
    switch (net.toLowerCase()) {
      case 'lan':
        return 'Home network';
      case 'guest':
        return 'Guest network';
      case 'wan':
        return 'Internet port';
      default:
        return net;
    }
  }

  Future<void> _submitAddSsid() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    final appState = ref.read(appStateProvider);

    try {
      final extraOptions = <String, String>{
        'cipher': _selectedCipher,
        'ieee80211w': _selectedPmf,
        'isolate': _isolateClients ? '1' : '0',
        'hidden': _isHidden ? '1' : '0',
        'wmm': _wmmEnabled ? '1' : '0',
        'disassoc_low_ack': _disassocLowAck ? '1' : '0',
        'multicast_to_unicast': _multicastToUnicast ? '1' : '0',
        'wds': _wds ? '1' : '0',
        'ieee80211r': _ieee80211r ? '1' : '0',
      };

      if (_ieee80211r) {
        extraOptions['ft_over_ds'] = _ftOverDs ? '1' : '0';
        extraOptions['ft_psk_generate_local'] = _ftPskGenerateLocal ? '1' : '0';
        if (_mobilityDomainController.text.trim().isNotEmpty) {
          extraOptions['mobility_domain'] = _mobilityDomainController.text
              .trim()
              .toLowerCase();
        }
      }
      if (_ieee80211k) {
        extraOptions['ieee80211k'] = '1';
      }
      if (_ieee80211v) {
        extraOptions['ieee80211v'] = '1';
      }
      if (_dtimPeriodController.text.trim().isNotEmpty) {
        extraOptions['dtim_period'] = _dtimPeriodController.text.trim();
      }
      if (_gtkRekeyController.text.trim().isNotEmpty) {
        extraOptions['gtk_rekey'] = _gtkRekeyController.text.trim();
      }
      if (_inactivityLimitController.text.trim().isNotEmpty) {
        extraOptions['inactivity_limit'] = _inactivityLimitController.text
            .trim();
      }
      if (_maxListenIntervalController.text.trim().isNotEmpty) {
        extraOptions['max_listen_interval'] = _maxListenIntervalController.text
            .trim();
      }
      if (_macfilter != 'disable') {
        extraOptions['macfilter'] = _macfilter;
        if (_maclistController.text.trim().isNotEmpty) {
          final macs = _maclistController.text
              .split(RegExp(r'[\n,;]+'))
              .map((e) => e.trim().toUpperCase())
              .where((e) => e.isNotEmpty)
              .join(' ');
          extraOptions['maclist'] = macs;
        }
      }

      final success = await appState.addWirelessInterface(
        radioName: _selectedRadio.name,
        ssid: _ssidController.text.trim(),
        encryption: _selectedEncryption,
        key: _requiresPassphrase() ? _passphraseController.text.trim() : '',
        network: _selectedNetwork,
        extraOptions: extraOptions,
        context: mounted ? context : null,
      );

      bool dhcpSuccess = true;
      if (success && _dhcpSettingsModified) {
        final dhcpValues = <String, dynamic>{
          'start': _dhcpStartController.text.trim(),
          'limit': _dhcpLimitController.text.trim(),
          'leasetime': _dhcpLeaseController.text.trim(),
          'ra': _ipv6Ra,
          'dhcpv6': _dhcpv6Mode,
        };
        if (_dnsServersController.text.trim().isNotEmpty) {
          dhcpValues['dns'] = _dnsServersController.text
              .split(RegExp(r'[\s,]+'))
              .where((s) => s.isNotEmpty)
              .toList();
        }
        dhcpSuccess = await appState.updateInterfaceDhcpConfig(
          interface: _selectedNetwork,
          values: dhcpValues,
          context: mounted ? context : null,
        );
      }

      if (mounted) {
        if (success && dhcpSuccess) {
          Navigator.pop(context, true);
          ksSay(context, 'New SSID "${_ssidController.text.trim()}" created.');
        } else if (success && !dhcpSuccess) {
          Navigator.pop(context, true);
          ksSay(
            context,
            'New SSID "${_ssidController.text.trim()}" created, but subnet DHCP configuration could not be applied.',
          );
        } else {
          final username = appState.sessionUsername;
          if ((appState.capabilities?.hasUciWriteAccess ?? true) == false ||
              !appState.isAdministrativeUser) {
            ksSay(
              context,
              'Access Denied: Account \'$username\' lacks UCI write authorization.',
            );
          } else {
            ksSay(context, 'Failed to create wireless interface on router');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ksSay(context, 'Failed to create wireless interface');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  static const _plainSecurity = {
    'sae-mixed': 'WPA2 and WPA3 (recommended)',
    'sae': 'WPA3 only, the strongest',
    'psk2': 'WPA2 only, for older devices',
    'psk': 'WPA, very old devices only',
    'owe': 'Open, but encrypted (no password)',
    'none': 'Open, no password',
  };

  static const _plainCipher = {
    'auto': 'Let the router choose',
    'ccmp': 'AES (recommended)',
    'gcmp256': 'GCMP-256, for Wi-Fi 6 devices',
    'tkip': 'TKIP, old and weak',
  };

  List<(String, String)> _securityOptions() => [
    for (final e
        in _dynamicEncryptions.isEmpty
            ? [
                for (final k in _plainSecurity.keys)
                  {'value': k, 'label': _plainSecurity[k]!},
              ]
            : _dynamicEncryptions)
      if (_isEncryptionSupported(e['value']!))
        (e['value']!, _plainSecurity[e['value']] ?? e['label']!),
  ];

  List<(String, String)> _cipherOptions() => [
    for (final c
        in _dynamicCiphers.isEmpty
            ? [
                for (final k in _plainCipher.keys)
                  {'value': k, 'label': _plainCipher[k]!},
              ]
            : _dynamicCiphers)
      if (_isCipherSupported(c['value']!))
        (c['value']!, _plainCipher[c['value']] ?? c['label']!),
  ];

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final needsPass = _requiresPassphrase();
    final canSave = !_isSubmitting && _isFormValid();

    Widget sw(String title, String? sub, bool v, ValueChanged<bool> on) =>
        KsSwitchRow(title: title, subtitle: sub, value: v, onChanged: on);

    void dhcp(_) => setState(() => _dhcpSettingsModified = true);

    Widget numbers(
      List<(String, TextEditingController)> fields, {
      ValueChanged<String>? onChanged,
    }) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (label, c)) in fields.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: KsField(
              label: label,
              controller: c,
              keyboardType: TextInputType.number,
              onChanged: onChanged ?? (_) => setState(() {}),
            ),
          ),
        ],
      ],
    );

    return PopScope(
      canPop: !_isSubmitting,
      child: Scaffold(
        backgroundColor: ks.bg,
        appBar: AppBar(
          backgroundColor: ks.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ks.tx,
          titleSpacing: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: canSave ? _submitAddSsid : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                const KsTitle(
                  'Add a network',
                  subtitle: 'A second Wi-Fi name, for guests or gadgets',
                ),
                if (_isLoadingCapabilities)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: ks.line,
                      color: ks.ac,
                    ),
                  ),
                if (!hasUciWrite)
                  KsBanner(
                    "You're signed in as '${appState.sessionUsername}', which "
                    "may not be allowed to change Wi-Fi. Sign in as root to "
                    'add networks.',
                    bad: true,
                  ),
                KsField(
                  label: 'Network name',
                  controller: _ssidController,
                  hint: 'What devices see in their Wi-Fi list',
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Give the network a name.';
                    }
                    if (utf8.encode(val.trim()).length > 32) {
                      return 'Too long. Use 32 letters or fewer.';
                    }
                    final dup = _selectedRadio.interfaces
                        .where((i) => i.mode.toLowerCase() == 'ap')
                        .any(
                          (i) =>
                              i.ssid.trim().toLowerCase() ==
                              val.trim().toLowerCase(),
                        );
                    if (dup) {
                      return 'There is already a network called that on '
                          '${_selectedRadio.bandLabel}.';
                    }
                    return null;
                  },
                ),
                if (widget.radios.length > 1)
                  KsChoice<String>(
                    label: 'Band',
                    value: _selectedRadio.name,
                    options: [
                      for (final r in widget.radios) (r.name, r.bandLabel),
                    ],
                    onChanged: (name) {
                      final r = widget.radios.firstWhere((r) => r.name == name);
                      if (r == _selectedRadio) return;
                      setState(() => _selectedRadio = r);
                      _fetchHardwareCapabilities();
                    },
                  ),
                KsChoice<String>(
                  label: 'Connects to',
                  value: _selectedNetwork,
                  help: _selectedNetwork == 'guest'
                      ? "Guests get internet but can't see your devices"
                      : null,
                  options: [
                    for (final n in _availableNetworks)
                      (n, _getNetworkLabel(n)),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedNetwork = v;
                    if (v == 'guest') _isolateClients = true;
                    _loadSubnetDhcpDefaults();
                  }),
                ),
                KsChoice<String>(
                  label: 'Security',
                  value: _selectedEncryption,
                  options: _securityOptions(),
                  onChanged: (v) => setState(() {
                    _selectedEncryption = v;
                    _confirmOpenNetwork = false;
                    _updateCipherForEncryption(v);
                  }),
                ),
                if (needsPass) ...[
                  KsField(
                    label: 'Password',
                    controller: _passphraseController,
                    obscure: !_showPassphrase,
                    help: '8 to 63 characters',
                    onChanged: (_) => setState(() {}),
                    validator: _validatePassphrase,
                    suffix: IconButton(
                      tooltip: _showPassphrase
                          ? 'Hide password'
                          : 'Show password',
                      icon: Icon(
                        _showPassphrase
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: ks.mu,
                      ),
                      onPressed: () =>
                          setState(() => _showPassphrase = !_showPassphrase),
                    ),
                  ),
                  PasswordStrengthMeter(password: _passphraseController.text),
                ],
                if (_selectedEncryption == 'none') ...[
                  const KsBanner(
                    'Anyone nearby can join an open network and see what '
                    "isn't encrypted by the websites themselves.",
                  ),
                  KsSwitchRow(
                    title: 'I understand anyone can join',
                    value: _confirmOpenNetwork,
                    onChanged: (v) => setState(() => _confirmOpenNetwork = v),
                  ),
                ],
                const SizedBox(height: 8),
                sw(
                  'Hide the network name',
                  "Devices have to type the name to join. It doesn't make "
                      'it safer.',
                  _isHidden,
                  (v) => setState(() => _isHidden = v),
                ),
                sw(
                  'Keep devices apart',
                  "Devices on this network can't see each other, only the "
                      'internet',
                  _isolateClients,
                  (v) => setState(() => _isolateClients = v),
                ),
                const SizedBox(height: 8),
                KsRow(
                  title: _showAdvanced
                      ? 'Hide advanced settings'
                      : 'Show advanced settings',
                  subtitle: 'Who can join, roaming, fine-tuning, addresses',
                  chevron: false,
                  trailing: Icon(
                    _showAdvanced
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: ks.mu,
                  ),
                  onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                ),
                if (_showAdvanced) ...[
                  const KsSection('Security details'),
                  if (_selectedEncryption != 'none')
                    KsChoice<String>(
                      label: 'Protect the connection itself (802.11w)',
                      value: _selectedPmf,
                      options: const [
                        ('0', 'Off, for very old devices'),
                        ('1', 'When the device can (recommended)'),
                        ('2', 'Always, needed for WPA3'),
                      ],
                      onChanged:
                          (_selectedEncryption == 'sae' ||
                              _selectedEncryption == 'owe')
                          ? null
                          : (v) => setState(() => _selectedPmf = v),
                    ),
                  if (needsPass)
                    KsChoice<String>(
                      label: 'Encryption',
                      value: _selectedCipher,
                      options: _cipherOptions(),
                      onChanged: (v) => setState(() => _selectedCipher = v),
                    ),
                  const KsSection('Who can join'),
                  KsChoice<String>(
                    label: 'Device list',
                    value: _macfilter,
                    options: const [
                      ('disable', 'Anyone with the password'),
                      ('allow', 'Only the devices listed'),
                      ('deny', 'Everyone except the devices listed'),
                    ],
                    onChanged: (v) => setState(() => _macfilter = v),
                  ),
                  if (_macfilter != 'disable')
                    KsField(
                      label: 'Devices',
                      controller: _maclistController,
                      maxLines: 4,
                      hint: 'AA:BB:CC:DD:EE:FF',
                      help: 'One device address per line',
                      onChanged: (_) => setState(() {}),
                    ),
                  const KsSection('Roaming between access points'),
                  sw(
                    'Fast roaming (802.11r)',
                    'Phones move between your access points without '
                        'dropping calls',
                    _ieee80211r,
                    (v) => setState(() => _ieee80211r = v),
                  ),
                  if (_ieee80211r) ...[
                    sw(
                      'Hand over through the cable',
                      'For access points joined by Ethernet',
                      _ftOverDs,
                      (v) => setState(() => _ftOverDs = v),
                    ),
                    sw(
                      'Make roaming keys on each access point',
                      null,
                      _ftPskGenerateLocal,
                      (v) => setState(() => _ftPskGenerateLocal = v),
                    ),
                    KsField(
                      label: 'Roaming group',
                      controller: _mobilityDomainController,
                      hint: '4f4b',
                      help: 'The same four characters on every access point',
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  sw(
                    'Signal reports (802.11k)',
                    'Helps devices pick the best access point',
                    _ieee80211k,
                    (v) => setState(() => _ieee80211k = v),
                  ),
                  sw(
                    'Steer devices (802.11v)',
                    'The router suggests a better access point',
                    _ieee80211v,
                    (v) => setState(() => _ieee80211v = v),
                  ),
                  const KsSection('Fine-tuning'),
                  sw(
                    'Put calls and video first (WMM)',
                    'Leave on; many devices need it for full speed',
                    _wmmEnabled,
                    (v) => setState(() => _wmmEnabled = v),
                  ),
                  sw(
                    'Drop devices with a bad connection',
                    'Frees the air for everyone else',
                    _disassocLowAck,
                    (v) => setState(() => _disassocLowAck = v),
                  ),
                  sw(
                    'Send group traffic one by one',
                    'More reliable streaming to several devices',
                    _multicastToUnicast,
                    (v) => setState(() => _multicastToUnicast = v),
                  ),
                  sw(
                    'Bridge to another router (WDS)',
                    'Only for linking two routers over Wi-Fi',
                    _wds,
                    (v) => setState(() => _wds = v),
                  ),
                  numbers([
                    ('Beacon interval (DTIM)', _dtimPeriodController),
                    ('New keys every (seconds)', _gtkRekeyController),
                  ]),
                  numbers([
                    (
                      'Drop idle devices after (seconds)',
                      _inactivityLimitController,
                    ),
                    ('Power-save listen limit', _maxListenIntervalController),
                  ]),
                  const KsSection('Addresses on this network'),
                  KsBanner(
                    'These apply to every device on '
                    '${_getNetworkLabel(_selectedNetwork)}, not only this '
                    'Wi-Fi network.',
                  ),
                  numbers([
                    ('First address', _dhcpStartController),
                    ('How many', _dhcpLimitController),
                  ], onChanged: dhcp),
                  KsField(
                    label: 'Each device keeps its address for',
                    controller: _dhcpLeaseController,
                    hint: '12h',
                    onChanged: dhcp,
                  ),
                  KsField(
                    label: 'Name servers to hand out',
                    controller: _dnsServersController,
                    hint: 'Leave empty to use the router',
                    onChanged: dhcp,
                  ),
                  KsChoice<String>(
                    label: 'IPv6 addresses',
                    value: _ipv6Ra,
                    options: const [
                      ('server', 'The router gives them out'),
                      ('relay', 'Passed on from the provider'),
                      ('disabled', 'Off'),
                    ],
                    onChanged: (v) => setState(() {
                      _ipv6Ra = v;
                      _dhcpSettingsModified = true;
                    }),
                  ),
                  KsChoice<String>(
                    label: 'IPv6 details (DHCPv6)',
                    value: _dhcpv6Mode,
                    options: const [
                      ('server', 'The router gives them out'),
                      ('relay', 'Passed on from the provider'),
                      ('disabled', 'Off'),
                    ],
                    onChanged: (v) => setState(() {
                      _dhcpv6Mode = v;
                      _dhcpSettingsModified = true;
                    }),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
