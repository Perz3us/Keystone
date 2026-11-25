// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';
import '../models/wireless_info.dart';
import '../screens/wifi_access_control_screen.dart';

class EditSsidDialog extends ConsumerStatefulWidget {
  final WirelessRadio radio;
  final WirelessInterface interface;

  const EditSsidDialog({
    super.key,
    required this.radio,
    required this.interface,
  });

  @override
  ConsumerState<EditSsidDialog> createState() => _EditSsidDialogState();
}

class _EditSsidDialogState extends ConsumerState<EditSsidDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _ssidController;
  late TextEditingController _passphraseController;

  late TextEditingController _mobilityDomainController;
  late TextEditingController _dtimPeriodController;
  late TextEditingController _gtkRekeyController;
  late TextEditingController _inactivityLimitController;
  late TextEditingController _maxListenIntervalController;

  late TextEditingController _dhcpStartController;
  late TextEditingController _dhcpLimitController;
  late TextEditingController _dhcpLeaseController;
  late TextEditingController _dnsServersController;
  String _ipv6Ra = 'server';
  String _dhcpv6Mode = 'server';

  late String _initialPassphrase;
  late String _selectedEncryption;
  late String _selectedCipher;
  late String _selectedPmf;
  late bool _isolateClients;
  late bool _isHidden;

  String _selectedNetwork = 'lan';
  List<String> _availableNetworks = ['lan', 'guest', 'wan'];

  bool _ieee80211r = false;
  bool _ftOverDs = false;
  bool _ftPskGenerateLocal = false;
  bool _ieee80211k = false;
  bool _ieee80211v = false;

  bool _wmmEnabled = true;
  bool _disassocLowAck = true;
  bool _multicastToUnicast = false;
  bool _wds = false;

  List<Map<String, String>> _dynamicEncryptions = [];
  List<Map<String, String>> _dynamicCiphers = [];

  bool _showPassphrase = false;
  bool _isSubmitting = false;
  bool _isPrefetching = false;
  bool _showAdvanced = false;

  bool get isNone =>
      _selectedEncryption == 'none' || _selectedEncryption == 'owe';

  @override
  void initState() {
    super.initState();
    final iface = widget.interface;
    _ssidController = TextEditingController(text: iface.ssid);
    _initialPassphrase = iface.key ?? '';
    _passphraseController = TextEditingController(text: _initialPassphrase);

    _mobilityDomainController = TextEditingController(
      text: iface.mobilityDomain ?? '4f4b',
    );
    _dtimPeriodController = TextEditingController(text: '2');
    _gtkRekeyController = TextEditingController(text: '3600');
    _inactivityLimitController = TextEditingController(text: '300');
    _maxListenIntervalController = TextEditingController(text: '65535');

    _dhcpStartController = TextEditingController(text: '100');
    _dhcpLimitController = TextEditingController(text: '150');
    _dhcpLeaseController = TextEditingController(text: '12h');
    _dnsServersController = TextEditingController();

    _selectedEncryption = _mapEncryptionToUci(
      iface.securityMode,
      iface.encryption,
    );
    _selectedCipher = _sanitizeCipher(iface.cipher);
    _selectedPmf = iface.pmfState == PmfState.required
        ? '2'
        : (iface.pmfState == PmfState.optional ? '1' : '0');
    _isolateClients = iface.isolateClients;
    _isHidden = iface.isHidden;
    _ieee80211r = iface.fastTransitionEnabled;
    _selectedNetwork = iface.networkBridge ?? 'lan';

    if (_selectedEncryption == 'sae') {
      _selectedPmf = '2';
    } else if (_selectedEncryption == 'none') {
      _selectedPmf = '0';
    }

    _loadSubnetDhcpDefaults();
    _captureBaseline();
    _fetchAvailableNetworks();
    _prefetchLiveUciConfig();
  }

  Map<String, dynamic> _initialBaseline = {};

  void _captureBaseline() {
    _initialBaseline = {
      'ssid': _ssidController.text.trim(),
      'passphrase': _passphraseController.text,
      'encryption': _selectedEncryption,
      'cipher': _selectedCipher,
      'pmf': _selectedPmf,
      'isolate': _isolateClients,
      'hidden': _isHidden,
      'network': _selectedNetwork,
      'ieee80211r': _ieee80211r,
      'ftOverDs': _ftOverDs,
      'ftPskGenerateLocal': _ftPskGenerateLocal,
      'mobilityDomain': _mobilityDomainController.text.trim(),
      'ieee80211k': _ieee80211k,
      'ieee80211v': _ieee80211v,
      'wmm': _wmmEnabled,
      'disassocLowAck': _disassocLowAck,
      'multicastToUnicast': _multicastToUnicast,
      'wds': _wds,
      'dtimPeriod': _dtimPeriodController.text.trim(),
      'gtkRekey': _gtkRekeyController.text.trim(),
      'inactivityLimit': _inactivityLimitController.text.trim(),
      'maxListenInterval': _maxListenIntervalController.text.trim(),
      'dhcpStart': _dhcpStartController.text.trim(),
      'dhcpLimit': _dhcpLimitController.text.trim(),
      'dhcpLease': _dhcpLeaseController.text.trim(),
      'dnsServers': _dnsServersController.text.trim(),
      'ipv6Ra': _ipv6Ra,
      'dhcpv6Mode': _dhcpv6Mode,
    };
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

  @override
  void dispose() {
    _ssidController.dispose();
    _passphraseController.dispose();
    _mobilityDomainController.dispose();
    _dtimPeriodController.dispose();
    _gtkRekeyController.dispose();
    _inactivityLimitController.dispose();
    _maxListenIntervalController.dispose();
    _dhcpStartController.dispose();
    _dhcpLimitController.dispose();
    _dhcpLeaseController.dispose();
    _dnsServersController.dispose();
    super.dispose();
  }

  Future<void> _fetchAvailableNetworks() async {
    try {
      final appState = ref.read(appStateProvider);
      final networks = await appState.fetchNetworkInterfaces();
      if (mounted && networks.isNotEmpty) {
        setState(() {
          _availableNetworks = networks;
          if (!_availableNetworks.contains(_selectedNetwork)) {
            _availableNetworks.insert(0, _selectedNetwork);
          }
        });
        _loadSubnetDhcpDefaults();
      }
    } catch (_) {}
  }

  Future<void> _prefetchLiveUciConfig() async {
    if (!mounted) return;
    setState(() => _isPrefetching = true);
    final appState = ref.read(appStateProvider);

    try {
      final caps = await appState.fetchWirelessHardwareCapabilities(
        sectionName: widget.interface.sectionName,
        radioName: widget.radio.name,
      );
      if (mounted) {
        setState(() {
          _dynamicEncryptions = caps['encryptions'] ?? [];
          _dynamicCiphers = caps['ciphers'] ?? [];
        });
      }

      final values = await appState.fetchWirelessSectionConfig(
        widget.interface.sectionName,
      );

      if (mounted && values != null && values.isNotEmpty) {
        if (values.isNotEmpty) {
          final liveKey =
              values['key']?.toString() ??
              values['password']?.toString() ??
              values['passphrase']?.toString() ??
              values['sae_password']?.toString() ??
              values['psk']?.toString();
          final liveSsid = values['ssid']?.toString();
          final liveCipher = values['cipher']?.toString();
          final liveEnc = values['encryption']?.toString();
          final livePmf = values['ieee80211w']?.toString();
          final liveNetwork = values['network']?.toString();

          final liveFt = values['ieee80211r']?.toString();
          final liveFtDs = values['ft_over_ds']?.toString();
          final liveFtLocal = values['ft_psk_generate_local']?.toString();
          final liveMobility = values['mobility_domain']?.toString();
          final liveK = values['ieee80211k']?.toString();
          final liveV = values['ieee80211v']?.toString();
          final liveWmm = values['wmm']?.toString();
          final liveLowAck = values['disassoc_low_ack']?.toString();
          final liveMcast2Ucast = values['multicast_to_unicast']?.toString();
          final liveWds = values['wds']?.toString();
          final liveDtim = values['dtim_period']?.toString();
          final liveRekey = values['gtk_rekey']?.toString();
          final liveInactivity = values['inactivity_limit']?.toString();
          final liveMaxListen = values['max_listen_interval']?.toString();

          setState(() {
            if (liveKey != null && liveKey.isNotEmpty) {
              if (_passphraseController.text.isEmpty ||
                  _passphraseController.text == _initialPassphrase) {
                _passphraseController.text = liveKey;
                _initialPassphrase = liveKey;
              }
            }
            if (liveSsid != null &&
                liveSsid.isNotEmpty &&
                _ssidController.text == widget.interface.ssid) {
              _ssidController.text = liveSsid;
            }
            if (liveCipher != null && liveCipher.isNotEmpty) {
              _selectedCipher = _sanitizeCipher(liveCipher);
            }
            if (liveEnc != null && liveEnc.isNotEmpty) {
              _selectedEncryption = _mapRawEncryptionStringToUci(liveEnc);
            }
            if (livePmf != null && livePmf.isNotEmpty) {
              if (livePmf == '2' || livePmf == '1' || livePmf == '0') {
                _selectedPmf = livePmf;
              }
            }
            if (liveNetwork != null && liveNetwork.isNotEmpty) {
              if (_availableNetworks.contains(liveNetwork)) {
                _selectedNetwork = liveNetwork;
              }
            }
            if (liveFt != null) _ieee80211r = liveFt == '1';
            if (liveFtDs != null) _ftOverDs = liveFtDs == '1';
            if (liveFtLocal != null) _ftPskGenerateLocal = liveFtLocal == '1';
            if (liveK != null) _ieee80211k = liveK == '1';
            if (liveV != null) _ieee80211v = liveV == '1';
            if (liveMobility != null && liveMobility.isNotEmpty) {
              _mobilityDomainController.text = liveMobility;
            }
            if (liveWmm != null) _wmmEnabled = liveWmm == '1';
            if (liveLowAck != null) _disassocLowAck = liveLowAck == '1';
            if (liveMcast2Ucast != null) {
              _multicastToUnicast = liveMcast2Ucast == '1';
            }
            if (liveWds != null) _wds = liveWds == '1';
            if (liveDtim != null && liveDtim.isNotEmpty) {
              _dtimPeriodController.text = liveDtim;
            }
            if (liveRekey != null && liveRekey.isNotEmpty) {
              _gtkRekeyController.text = liveRekey;
            }
            if (liveInactivity != null && liveInactivity.isNotEmpty) {
              _inactivityLimitController.text = liveInactivity;
            }
            if (liveMaxListen != null && liveMaxListen.isNotEmpty) {
              _maxListenIntervalController.text = liveMaxListen;
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        _captureBaseline();
        setState(() => _isPrefetching = false);
      }
    }
  }

  String _sanitizeCipher(String? cipher) {
    if (cipher == null) return 'auto';
    final c = cipher.toLowerCase();
    if (c.contains('gcmp256') || c.contains('gcmp-256')) return 'gcmp256';
    if (c.contains('ccmp') || c.contains('aes')) return 'ccmp';
    if (c.contains('tkip')) return 'tkip';
    return 'auto';
  }

  String _mapRawEncryptionStringToUci(String rawEnc) {
    final raw = rawEnc.toLowerCase();
    if (raw.contains('sae') && raw.contains('psk')) return 'sae-mixed';
    if (raw.contains('sae')) return 'sae';
    if (raw.contains('psk2') || raw.contains('wpa2')) return 'psk2';
    if (raw.contains('psk')) return 'psk';
    if (raw.contains('none') || raw.contains('open')) return 'none';
    return 'psk2';
  }

  String _mapEncryptionToUci(WifiSecurityMode secMode, String rawEnc) {
    switch (secMode) {
      case WifiSecurityMode.saeOnly:
        return 'sae';
      case WifiSecurityMode.saeMixed:
        return 'sae-mixed';
      case WifiSecurityMode.wpa2Psk:
        return 'psk2';
      case WifiSecurityMode.wpaPsk:
        return 'psk';
      case WifiSecurityMode.open:
        return 'none';
      default:
        return _mapRawEncryptionStringToUci(rawEnc);
    }
  }

  int get _ssidByteLength => utf8.encode(_ssidController.text).length;

  Future<void> _submitChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = ref.read(appStateProvider);
    final iface = widget.interface;

    bool isConnectedToThisSsid = false;
    final activeSessionMac = appState.dashboardData?['activeSessionMac']
        ?.toString()
        .toUpperCase();
    for (final st in iface.stations) {
      if (activeSessionMac != null &&
          activeSessionMac.isNotEmpty &&
          st.macAddress.toUpperCase() == activeSessionMac) {
        isConnectedToThisSsid = true;
        break;
      }
    }

    final isSsidNameChanged =
        _ssidController.text.trim() != widget.interface.ssid;
    final isPassphraseChanged =
        _passphraseController.text != _initialPassphrase;
    final isEncryptionChanged =
        _selectedEncryption !=
        _mapEncryptionToUci(
          widget.interface.securityMode,
          widget.interface.encryption,
        );

    if (_isSecurityDowngrade()) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Security Downgrade Warning',
        subtitle:
            'You are lowering the Wi-Fi security standard from ${widget.interface.securityMode.displayName} to ${_selectedEncryption.toUpperCase()}. This weakens encryption protection for connecting clients.',
        confirmLabel: 'Proceed with Downgrade',
        cancelLabel: 'Cancel',
        icon: Icons.shield_outlined,
        iconColor: Colors.amber.shade800,
        isDestructive: false,
      );
      if (!proceed) return;
    }

    if (isConnectedToThisSsid &&
        (isSsidNameChanged || isPassphraseChanged || isEncryptionChanged)) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Self-Disconnection Warning',
        subtitle:
            'You are currently connected via Wi-Fi network "${iface.ssid}". Modifying its name, security mode, or passphrase will sever your active session.',
        confirmLabel: 'Proceed & Disconnect',
        cancelLabel: 'Cancel',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
        isDestructive: true,
      );
      if (!proceed) return;
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    final String resolvedPmf =
        (_selectedEncryption == 'sae' || _selectedEncryption == 'owe')
        ? '2'
        : (_selectedEncryption == 'none' ? '0' : _selectedPmf);

    final newValues = <String, String>{
      'ssid': _ssidController.text.trim(),
      'encryption': _selectedEncryption,
      'cipher': _selectedCipher,
      'ieee80211w': resolvedPmf,
      'isolate': _isolateClients ? '1' : '0',
      'hidden': _isHidden ? '1' : '0',
      'network': _selectedNetwork,
      'ieee80211r': _ieee80211r ? '1' : '0',
      'ft_over_ds': _ftOverDs ? '1' : '0',
      'ft_psk_generate_local': _ftPskGenerateLocal ? '1' : '0',
      'ieee80211k': _ieee80211k ? '1' : '0',
      'ieee80211v': _ieee80211v ? '1' : '0',
      'wmm': _wmmEnabled ? '1' : '0',
      'disassoc_low_ack': _disassocLowAck ? '1' : '0',
      'multicast_to_unicast': _multicastToUnicast ? '1' : '0',
      'wds': _wds ? '1' : '0',
    };

    if (_mobilityDomainController.text.trim().isNotEmpty) {
      newValues['mobility_domain'] = _mobilityDomainController.text
          .trim()
          .toLowerCase();
    }
    if (_dtimPeriodController.text.trim().isNotEmpty) {
      newValues['dtim_period'] = _dtimPeriodController.text.trim();
    }
    if (_gtkRekeyController.text.trim().isNotEmpty) {
      newValues['gtk_rekey'] = _gtkRekeyController.text.trim();
    }
    if (_inactivityLimitController.text.trim().isNotEmpty) {
      newValues['inactivity_limit'] = _inactivityLimitController.text.trim();
    }
    if (_maxListenIntervalController.text.trim().isNotEmpty) {
      newValues['max_listen_interval'] = _maxListenIntervalController.text
          .trim();
    }

    final deleteOptions = <String>[];
    if (_selectedEncryption != 'none') {
      final enteredPass = _passphraseController.text.trim();
      if (enteredPass.isNotEmpty) {
        newValues['key'] = enteredPass;
      } else if (_initialPassphrase.isNotEmpty) {
        newValues['key'] = _initialPassphrase;
      }
    }

    final priorSnapshot = <String, String>{
      'ssid': iface.ssid,
      'encryption': _mapEncryptionToUci(iface.securityMode, iface.encryption),
      'cipher': _sanitizeCipher(iface.cipher),
      'ieee80211w': iface.pmfState == PmfState.required
          ? '2'
          : (iface.pmfState == PmfState.optional ? '1' : '0'),
      'isolate': iface.isolateClients ? '1' : '0',
      'hidden': iface.isHidden ? '1' : '0',
      'network': iface.networkBridge ?? 'lan',
      'ieee80211r': iface.fastTransitionEnabled ? '1' : '0',
    };
    if (iface.key != null && iface.key!.isNotEmpty) {
      priorSnapshot['key'] = iface.key!;
    }

    try {
      final success = await appState.applyWirelessInterfaceConfig(
        sectionName: iface.sectionName,
        newValues: newValues,
        priorValuesSnapshot: priorSnapshot,
        deleteOptions: deleteOptions,
        targetRadio: widget.radio,
        targetInterface: widget.interface,
        context: mounted ? context : null,
      );

      bool dhcpSuccess = true;
      if (success &&
          (_dhcpStartController.text.trim() != _initialBaseline['dhcpStart'] ||
              _dhcpLimitController.text.trim() !=
                  _initialBaseline['dhcpLimit'] ||
              _dhcpLeaseController.text.trim() !=
                  _initialBaseline['dhcpLease'] ||
              _dnsServersController.text.trim() !=
                  _initialBaseline['dnsServers'] ||
              _ipv6Ra != _initialBaseline['ipv6Ra'] ||
              _dhcpv6Mode != _initialBaseline['dhcpv6Mode'])) {
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

      final l10n = mounted ? AppLocalizations.of(context) : null;
      if (mounted) {
        if (success && dhcpSuccess) {
          Navigator.pop(context, true);
          ksSay(
            context,
            l10n?.toastSsidUpdateSuccess ??
                'SSID settings applied directly to router.',
          );
        } else if (success && !dhcpSuccess) {
          Navigator.pop(context, true);
          ksSay(
            context,
            'SSID updated, but subnet DHCP configuration could not be applied.',
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
            ksSay(
              context,
              l10n?.toastSsidUpdateFailed ??
                  'Failed to update wireless section in UCI.',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ksSay(context, 'Failed to update wireless SSID');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  bool _hasChanges() {
    if (_initialBaseline.isEmpty) return false;
    if (_ssidController.text.trim() != _initialBaseline['ssid']) return true;
    if (_passphraseController.text != _initialBaseline['passphrase']) {
      return true;
    }
    if (_selectedEncryption != _initialBaseline['encryption']) return true;
    if (_selectedCipher != _initialBaseline['cipher']) return true;
    if (_selectedPmf != _initialBaseline['pmf']) return true;
    if (_isolateClients != _initialBaseline['isolate']) return true;
    if (_isHidden != _initialBaseline['hidden']) return true;
    if (_selectedNetwork != _initialBaseline['network']) return true;
    if (_ieee80211r != _initialBaseline['ieee80211r']) return true;
    if (_ftOverDs != _initialBaseline['ftOverDs']) return true;
    if (_ftPskGenerateLocal != _initialBaseline['ftPskGenerateLocal']) {
      return true;
    }
    if (_mobilityDomainController.text.trim() !=
        _initialBaseline['mobilityDomain']) {
      return true;
    }
    if (_ieee80211k != _initialBaseline['ieee80211k']) return true;
    if (_ieee80211v != _initialBaseline['ieee80211v']) return true;
    if (_wmmEnabled != _initialBaseline['wmm']) return true;
    if (_disassocLowAck != _initialBaseline['disassocLowAck']) return true;
    if (_multicastToUnicast != _initialBaseline['multicastToUnicast']) {
      return true;
    }
    if (_wds != _initialBaseline['wds']) return true;
    if (_dtimPeriodController.text.trim() != _initialBaseline['dtimPeriod']) {
      return true;
    }
    if (_gtkRekeyController.text.trim() != _initialBaseline['gtkRekey']) {
      return true;
    }
    if (_inactivityLimitController.text.trim() !=
        _initialBaseline['inactivityLimit']) {
      return true;
    }
    if (_maxListenIntervalController.text.trim() !=
        _initialBaseline['maxListenInterval']) {
      return true;
    }
    if (_dhcpStartController.text.trim() != _initialBaseline['dhcpStart']) {
      return true;
    }
    if (_dhcpLimitController.text.trim() != _initialBaseline['dhcpLimit']) {
      return true;
    }
    if (_dhcpLeaseController.text.trim() != _initialBaseline['dhcpLease']) {
      return true;
    }
    if (_dnsServersController.text.trim() != _initialBaseline['dnsServers']) {
      return true;
    }
    if (_ipv6Ra != _initialBaseline['ipv6Ra']) return true;
    if (_dhcpv6Mode != _initialBaseline['dhcpv6Mode']) return true;
    return false;
  }

  bool _isFormValid() {
    final ssid = _ssidController.text.trim();
    if (ssid.isEmpty) return false;
    if (utf8.encode(ssid).length > 32) return false;

    if (!isNone) {
      final pass = _passphraseController.text;
      if (pass.isNotEmpty) {
        if (pass.length < 8 || pass.length > 64) return false;
      } else {
        final String initPass =
            _initialBaseline['passphrase'] ?? _initialPassphrase;
        if (initPass.isEmpty) return false;
      }
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

  bool _isSecurityDowngrade() {
    final curRank = _securityRank(
      _mapEncryptionToUci(
        widget.interface.securityMode,
        widget.interface.encryption,
      ),
    );
    final newRank = _securityRank(_selectedEncryption);
    return newRank < curRank;
  }

  int _securityRank(String enc) {
    switch (enc) {
      case 'sae':
        return 4;
      case 'sae-mixed':
        return 3;
      case 'psk2':
        return 2;
      case 'psk':
        return 1;
      case 'owe':
        return 1;
      case 'none':
      default:
        return 0;
    }
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

  List<(String, String)> _securityOptions() {
    const plain = {
      'sae-mixed': 'WPA2 and WPA3 (recommended)',
      'sae': 'WPA3 only, the strongest',
      'psk2': 'WPA2 only, for older devices',
      'psk': 'WPA, very old devices only',
      'owe': 'Open, but encrypted (no password)',
      'none': 'Open, no password',
    };
    if (_dynamicEncryptions.isEmpty) {
      return [for (final e in plain.entries) (e.key, e.value)];
    }
    return [
      for (final e in _dynamicEncryptions)
        (e['value']!, plain[e['value']] ?? e['label']!),
    ];
  }

  List<(String, String)> _cipherOptions() {
    const plain = {
      'auto': 'Let the router choose',
      'ccmp': 'AES (recommended)',
      'gcmp256': 'GCMP-256, for Wi-Fi 6 devices',
      'tkip': 'TKIP, old and weak',
    };
    if (_dynamicCiphers.isEmpty) {
      return [for (final e in plain.entries) (e.key, e.value)];
    }
    return [
      for (final c in _dynamicCiphers)
        (c['value']!, plain[c['value']] ?? c['label']!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final appState = ref.watch(appStateProvider);
    final hasWriteAccess =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final canSave =
        !_isSubmitting && !_isPrefetching && _hasChanges() && _isFormValid();

    Widget sw(String title, String? sub, bool v, ValueChanged<bool> on) =>
        KsSwitchRow(title: title, subtitle: sub, value: v, onChanged: on);

    Widget numbers(List<(String, TextEditingController, String?)> fields) =>
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, (label, c, help)) in fields.indexed) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(
                child: KsField(
                  label: label,
                  controller: c,
                  help: help,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
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
                onPressed: canSave ? _submitChanges : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
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
                KsTitle(
                  'Edit network',
                  subtitle: [
                    widget.interface.ssid,
                    widget.radio.bandLabel,
                  ].join(' · '),
                ),
                if (_isPrefetching)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: ks.line,
                      color: ks.ac,
                    ),
                  ),
                if (!hasWriteAccess)
                  KsBanner(
                    "You're signed in as '${appState.sessionUsername}', which "
                    "may not be allowed to change Wi-Fi. Sign in as root to "
                    'save.',
                    bad: true,
                  ),
                KsField(
                  label: 'Network name',
                  controller: _ssidController,
                  hint: 'What devices see in their Wi-Fi list',
                  help: _ssidByteLength > 32
                      ? 'Too long: $_ssidByteLength of 32 letters'
                      : null,
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
                KsChoice<String>(
                  label: 'Security',
                  value: _selectedEncryption,
                  options: _securityOptions(),
                  onChanged: (val) => setState(() {
                    _selectedEncryption = val;
                    if (val == 'sae') {
                      _selectedPmf = '2';
                    } else if (val == 'none') {
                      _selectedPmf = '0';
                    } else if (_selectedPmf == '0' && val == 'sae-mixed') {
                      _selectedPmf = '1';
                    }
                  }),
                ),
                if (!isNone) ...[
                  KsField(
                    label: 'Password',
                    controller: _passphraseController,
                    obscure: !_showPassphrase,
                    help: _initialPassphrase.isEmpty
                        ? 'Leave empty to keep the current password'
                        : '8 to 63 characters',
                    onChanged: (_) => setState(() {}),
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
                    validator: (val) {
                      if (val == null || val.isEmpty) return null;
                      if (val.length < 8 || val.length > 64) {
                        return 'Use 8 to 63 characters.';
                      }
                      return null;
                    },
                  ),
                  PasswordStrengthMeter(password: _passphraseController.text),
                ],
                if (_selectedEncryption == 'none')
                  const KsBanner(
                    'Anyone nearby can join an open network and see what '
                    "isn't encrypted by the websites themselves.",
                  ),
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
                              _selectedEncryption == 'none')
                          ? null
                          : (v) => setState(() => _selectedPmf = v),
                    ),
                  if (!isNone)
                    KsChoice<String>(
                      label: 'Encryption',
                      value: _selectedCipher,
                      options: _cipherOptions(),
                      onChanged: (v) => setState(() => _selectedCipher = v),
                    ),
                  const KsSection('Who can join'),
                  KsRow(
                    title: 'Allow or block devices',
                    subtitle: 'Choose which devices may join this network',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (_) => NetworkAccessScreen(
                          radio: widget.radio,
                          interface: widget.interface,
                        ),
                      ),
                    ),
                  ),
                  KsChoice<String>(
                    label: 'Connects to',
                    value: _selectedNetwork,
                    options: [
                      for (final n in _availableNetworks)
                        (n, _getNetworkLabel(n)),
                    ],
                    onChanged: (v) => setState(() {
                      _selectedNetwork = v;
                      _loadSubnetDhcpDefaults();
                    }),
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
                    ('Beacon interval (DTIM)', _dtimPeriodController, null),
                    ('New keys every (seconds)', _gtkRekeyController, null),
                  ]),
                  numbers([
                    (
                      'Drop idle devices after (seconds)',
                      _inactivityLimitController,
                      null,
                    ),
                    (
                      'Power-save listen limit',
                      _maxListenIntervalController,
                      null,
                    ),
                  ]),
                  const KsSection('Addresses on this network'),
                  KsBanner(
                    'These apply to every device on '
                    '${_getNetworkLabel(_selectedNetwork)}, not only this '
                    'Wi-Fi network.',
                  ),
                  numbers([
                    ('First address', _dhcpStartController, null),
                    ('How many', _dhcpLimitController, null),
                  ]),
                  KsField(
                    label: 'Each device keeps its address for',
                    controller: _dhcpLeaseController,
                    hint: '12h',
                    onChanged: (_) => setState(() {}),
                  ),
                  KsField(
                    label: 'Name servers to hand out',
                    controller: _dnsServersController,
                    hint: 'Leave empty to use the router',
                    onChanged: (_) => setState(() {}),
                  ),
                  KsChoice<String>(
                    label: 'IPv6 addresses',
                    value: _ipv6Ra,
                    options: const [
                      ('server', 'The router gives them out'),
                      ('relay', 'Passed on from the provider'),
                      ('disabled', 'Off'),
                    ],
                    onChanged: (v) => setState(() => _ipv6Ra = v),
                  ),
                  KsChoice<String>(
                    label: 'IPv6 details (DHCPv6)',
                    value: _dhcpv6Mode,
                    options: const [
                      ('server', 'The router gives them out'),
                      ('relay', 'Passed on from the provider'),
                      ('disabled', 'Off'),
                    ],
                    onChanged: (v) => setState(() => _dhcpv6Mode = v),
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
