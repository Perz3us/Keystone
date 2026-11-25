// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';

class ProvisionGuestNetworkDialog extends ConsumerStatefulWidget {
  final List<WirelessRadio> radios;

  const ProvisionGuestNetworkDialog({super.key, required this.radios});

  @override
  ConsumerState<ProvisionGuestNetworkDialog> createState() =>
      _ProvisionGuestNetworkDialogState();
}

class _ProvisionGuestNetworkDialogState
    extends ConsumerState<ProvisionGuestNetworkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _ssidController = TextEditingController(text: 'MyHome_Guest');
  final _passphraseController = TextEditingController();
  final _guestIpController = TextEditingController(text: '192.168.2.1');
  final _mobilityDomainController = TextEditingController();
  final _dtimPeriodController = TextEditingController(text: '2');
  final _gtkRekeyController = TextEditingController(text: '3600');
  final _inactivityLimitController = TextEditingController(text: '300');
  final _maxListenIntervalController = TextEditingController(text: '65535');
  final _maclistController = TextEditingController();

  late WirelessRadio _selectedRadio;
  String _selectedEncryption = 'sae-mixed';
  String _selectedPmf = '1';
  bool _isolateClients = true;
  bool _isSubmitting = false;
  bool _showPassphrase = false;

  String _selectedNetwork = 'guest';
  List<String> _availableNetworks = ['guest', 'lan', 'wan'];

  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;

  bool _wmm = true;
  bool _hidden = false;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  String _macfilter = 'disable';

  bool _showAdvanced = false;

  List<Map<String, String>> _dynamicEncryptions = [];

  @override
  void initState() {
    super.initState();
    _selectedRadio = widget.radios.isNotEmpty
        ? widget.radios.first
        : const WirelessRadio(
            name: 'radio0',
            isUp: true,
            channel: 'auto',
            country: 'US',
            interfaces: [],
          );
    _fetchAvailableNetworks();
    _fetchHardwareCapabilities();
  }

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _selectedNetwork = _availableNetworks.firstWhere(
              (n) => n == 'guest',
              orElse: () => _availableNetworks.first,
            );
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchHardwareCapabilities() async {
    if (!mounted) return;
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
          _applySmartDefaults();
        });
      }
    } catch (_) {}
  }

  void _applySmartDefaults() {
    if (_dynamicEncryptions.isEmpty) return;
    final supported = _dynamicEncryptions
        .map((e) => e['value']?.toString())
        .whereType<String>()
        .toSet();
    for (final preferred in ['sae-mixed', 'psk2', 'psk', 'owe', 'none']) {
      if (supported.contains(preferred)) {
        _selectedEncryption = preferred;
        break;
      }
    }
    _updateCipherAndPmf(_selectedEncryption);
  }

  void _updateCipherAndPmf(String enc) {
    if (enc == 'sae' || enc == 'sae-mixed') {
      _selectedPmf = enc == 'sae' ? '2' : '1';
    } else if (enc == 'psk2') {
      _selectedPmf = '1';
    } else if (enc == 'owe') {
      _selectedPmf = '2';
    } else {
      _selectedPmf = '0';
    }
  }

  bool _requiresPassphrase() =>
      _selectedEncryption != 'none' && _selectedEncryption != 'owe';

  @override
  void dispose() {
    _ssidController.dispose();
    _passphraseController.dispose();
    _guestIpController.dispose();
    _mobilityDomainController.dispose();
    _dtimPeriodController.dispose();
    _gtkRekeyController.dispose();
    _inactivityLimitController.dispose();
    _maxListenIntervalController.dispose();
    _maclistController.dispose();
    super.dispose();
  }

  Future<void> _submitProvisionGuest() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = ref.read(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;

    if (!hasUciWrite) {
      ksSay(
        context,
        'Read-only session: UCI write permission required to create Guest Wi-Fi.',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    List<String>? macList;
    if (_macfilter != 'disable' && _maclistController.text.trim().isNotEmpty) {
      macList = _maclistController.text
          .split(RegExp(r'[\n,;]+'))
          .map((e) => e.trim().toUpperCase())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    try {
      final success = await appState.provisionGuestNetwork(
        radioName: _selectedRadio.name,
        ssid: _ssidController.text.trim(),
        encryption: _selectedEncryption,
        key: _requiresPassphrase() ? _passphraseController.text.trim() : '',
        guestIp: _guestIpController.text.trim(),
        isolateClients: _isolateClients,
        network: _selectedNetwork,
        country: null,
        channel: null,
        htMode: null,
        txPower: null,
        ieee80211r: _ieee80211r,
        ftOverDs: _ftOverDs,
        ftPskGenerateLocal: _ftPskGenerateLocal,
        mobilityDomain: _mobilityDomainController.text.trim().isNotEmpty
            ? _mobilityDomainController.text.trim().toLowerCase()
            : null,
        wmm: _wmm,
        hidden: _hidden,
        dtimPeriod: int.tryParse(_dtimPeriodController.text.trim()),
        gtkRekey: int.tryParse(_gtkRekeyController.text.trim()),
        inactivityLimit: int.tryParse(_inactivityLimitController.text.trim()),
        maxListenInterval: int.tryParse(
          _maxListenIntervalController.text.trim(),
        ),
        disassocLowAck: _disassocLowAck,
        multicastToUnicast: _multicastToUnicast,
        wds: _wds,
        macfilter: _macfilter == 'disable' ? null : _macfilter,
        maclist: macList,
        context: mounted ? context : null,
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ksSay(
            context,
            'New Guest Wi-Fi "${_ssidController.text.trim()}" created!',
          );
        } else {
          final username = appState.sessionUsername;
          if (!hasUciWrite) {
            ksSay(
              context,
              'Access Denied: Account \'$username\' lacks ubus UCI write authorization.',
            );
          } else {
            ksSay(context, 'Failed to provision guest network on router.');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ksSay(context, 'Failed to provision guest network');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final needsPass = _requiresPassphrase();
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    const security = [
      ('sae-mixed', 'WPA2 and WPA3 (recommended)'),
      ('sae', 'WPA3 only, the strongest'),
      ('psk2', 'WPA2 only, for older devices'),
      ('owe', 'Open, but encrypted (no password)'),
      ('none', 'Open, no password'),
    ];
    final offered = _dynamicEncryptions
        .map((e) => e['value']?.toString())
        .whereType<String>()
        .toSet();

    Widget sw(String title, String? sub, bool v, ValueChanged<bool> on) =>
        KsSwitchRow(title: title, subtitle: sub, value: v, onChanged: on);

    Widget numbers(List<(String, TextEditingController)> fields) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, (label, c)) in fields.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(
            child: KsField(
              label: label,
              controller: c,
              keyboardType: TextInputType.number,
            ),
          ),
        ],
      ],
    );

    String netLabel(String n) => switch (n) {
      'guest' => 'Its own guest network (recommended)',
      'lan' => 'Your home network',
      'wan' => 'The internet port',
      _ => n,
    };

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
                onPressed: (_isSubmitting || !hasUciWrite)
                    ? null
                    : _submitProvisionGuest,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create'),
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
                  'Set up guest Wi-Fi',
                  subtitle: "Visitors get internet but can't see your devices",
                ),
                if (!hasUciWrite)
                  KsBanner(
                    "You're signed in as '${appState.sessionUsername}', which "
                    "can't change Wi-Fi. Sign in as root to create it.",
                    bad: true,
                  ),
                KsField(
                  label: 'Network name',
                  controller: _ssidController,
                  onChanged: (_) => setState(() {}),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Give the network a name.';
                    }
                    if (utf8.encode(val).length > 32) {
                      return 'Too long. Use 32 letters or fewer.';
                    }
                    return null;
                  },
                ),
                if (widget.radios.length > 1)
                  KsChoice<String>(
                    label: 'Band',
                    value: _selectedRadio.name,
                    help: 'Uses the channel already set for this band',
                    options: [
                      for (final r in widget.radios) (r.name, r.bandLabel),
                    ],
                    onChanged: (name) => setState(
                      () => _selectedRadio = widget.radios.firstWhere(
                        (r) => r.name == name,
                      ),
                    ),
                  ),
                KsChoice<String>(
                  label: 'Security',
                  value: _selectedEncryption,
                  options: [
                    for (final o in security)
                      if (offered.isEmpty || offered.contains(o.$1)) o,
                  ],
                  onChanged: (v) => setState(() {
                    _selectedEncryption = v;
                    _updateCipherAndPmf(v);
                  }),
                ),
                if (needsPass) ...[
                  KsField(
                    label: 'Password',
                    controller: _passphraseController,
                    obscure: !_showPassphrase,
                    help: '8 to 63 characters',
                    onChanged: (_) => setState(() {}),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Guests need a password to join.';
                      }
                      if (val.length < 8) return 'Use at least 8 characters.';
                      if (val.length > 63) return 'Use 63 characters or fewer.';
                      return null;
                    },
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
                if (_selectedEncryption == 'none')
                  const KsBanner(
                    'Anyone nearby can join an open network and see what '
                    "isn't encrypted by the websites themselves.",
                  ),
                const SizedBox(height: 8),
                KsRow(
                  title: _showAdvanced
                      ? 'Hide advanced settings'
                      : 'Show advanced settings',
                  subtitle: 'Its own addresses, roaming, fine-tuning',
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
                  const KsSection('Where guests go'),
                  KsChoice<String>(
                    label: 'Connects to',
                    value: _selectedNetwork,
                    options: [
                      for (final n in _availableNetworks) (n, netLabel(n)),
                    ],
                    onChanged: (v) => setState(() => _selectedNetwork = v),
                  ),
                  if (_selectedNetwork == 'guest')
                    KsField(
                      label: "The guest network's router address",
                      controller: _guestIpController,
                      hint: '192.168.2.1',
                      help: 'Must differ from your home network',
                      keyboardType: TextInputType.number,
                      validator: (val) {
                        if (_selectedNetwork != 'guest') return null;
                        final v = (val ?? '').trim();
                        final parts = v.split('.');
                        if (parts.length != 4 ||
                            parts.any((p) {
                              final n = int.tryParse(p);
                              return n == null || n < 0 || n > 255;
                            })) {
                          return 'Use an address like 192.168.2.1.';
                        }
                        return null;
                      },
                    ),
                  sw(
                    'Keep guests apart',
                    "Guests can't see each other, only the internet",
                    _isolateClients,
                    (v) => setState(() => _isolateClients = v),
                  ),
                  sw(
                    'Hide the network name',
                    'Guests have to type the name to join',
                    _hidden,
                    (v) => setState(() => _hidden = v),
                  ),
                  if (_selectedEncryption != 'none')
                    KsChoice<String>(
                      label: 'Protect the connection itself (802.11w)',
                      value: _selectedPmf,
                      options: const [
                        ('0', 'Off, for very old devices'),
                        ('1', 'When the device can (recommended)'),
                        ('2', 'Always, needed for WPA3'),
                      ],
                      onChanged: (v) => setState(() => _selectedPmf = v),
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
                    ),
                  ],
                  const KsSection('Fine-tuning'),
                  sw(
                    'Put calls and video first (WMM)',
                    'Leave on; many devices need it for full speed',
                    _wmm,
                    (v) => setState(() => _wmm = v),
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
