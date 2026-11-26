// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/luci_guardrail.dart';
import 'package:yet_another_luci_app/screens/wifi/channel_check_screen.dart';
import '../models/wireless_info.dart';

class EditRadioDialog extends ConsumerStatefulWidget {
  final WirelessRadio radio;

  const EditRadioDialog({super.key, required this.radio});

  @override
  ConsumerState<EditRadioDialog> createState() => _EditRadioDialogState();
}

class _EditRadioDialogState extends ConsumerState<EditRadioDialog> {
  final _formKey = GlobalKey<FormState>();

  late bool _isDisabled;
  late String _selectedChannel;
  late String _selectedHtMode;
  late String _selectedTxPower;
  late String _selectedCountry;

  bool _isSubmitting = false;
  bool _isPrefetching = false;
  List<Map<String, String>> _dynamicCountryCodes = [];
  List<String> _dynamicChannels = [];
  List<String> _dynamicHtModes = [];
  List<String> _dynamicTxPowers = [];

  @override
  void initState() {
    super.initState();
    final radio = widget.radio;
    _selectedCountry = radio.country.toUpperCase();
    if (_selectedCountry.isEmpty) _selectedCountry = '00';
    _isDisabled = radio.isDisabled;
    _selectedChannel = radio.channel;
    _selectedHtMode = radio.htMode ?? _defaultHtModeForBand(radio.bandLabel);
    _selectedTxPower = radio.txPowerDbm?.toString() ?? 'auto';
    _prefetchRadioCapabilities();
  }

  Future<void> _prefetchRadioCapabilities() async {
    setState(() => _isPrefetching = true);
    try {
      final appState = ref.read(appStateProvider);
      final caps = await appState.fetchWirelessRadioCapabilities(
        radioName: widget.radio.name,
        context: context,
      );
      if (!mounted) return;
      setState(() {
        final cCodes = caps['countryCodes'];
        if (cCodes is List && cCodes.isNotEmpty) {
          _dynamicCountryCodes = List<Map<String, String>>.from(
            cCodes.map((e) => Map<String, String>.from(e as Map)),
          );
        }
        final chs = caps['channels'];
        if (chs is List && chs.isNotEmpty) {
          _dynamicChannels = List<String>.from(chs.map((e) => e.toString()));
        }
        final hts = caps['htModes'];
        if (hts is List && hts.isNotEmpty) {
          _dynamicHtModes = List<String>.from(hts.map((e) => e.toString()));
        }
        final txs = caps['txPowers'];
        if (txs is List && txs.isNotEmpty) {
          _dynamicTxPowers = List<String>.from(txs.map((e) => e.toString()));
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isPrefetching = false);
    }
  }

  String _defaultHtModeForBand(String bandLabel) {
    if (bandLabel.contains('5 GHz') || bandLabel.contains('6 GHz')) {
      return 'VHT80';
    }
    return 'HT20';
  }

  bool _hasChanges() {
    final radio = widget.radio;
    final initCountry = radio.country.toUpperCase().isEmpty
        ? '00'
        : radio.country.toUpperCase();
    final initChannel = radio.channel;
    final initHtMode = radio.htMode ?? _defaultHtModeForBand(radio.bandLabel);
    final initTxPower = radio.txPowerDbm?.toString() ?? 'auto';
    if (_isDisabled != radio.isDisabled) return true;
    if (_selectedChannel != initChannel) return true;
    if (_selectedHtMode != initHtMode) return true;
    if (_selectedTxPower != initTxPower) return true;
    if (_selectedCountry != initCountry) return true;
    return false;
  }

  List<Map<String, String>> _getAvailableCountryCodes() {
    final list = _dynamicCountryCodes.isNotEmpty
        ? List<Map<String, String>>.from(_dynamicCountryCodes)
        : _getCuratedCountryCodes();

    if (!list.any((item) => item['code'] == _selectedCountry)) {
      list.insert(0, {
        'code': _selectedCountry,
        'label': '$_selectedCountry, as set on the router',
      });
    }
    return list;
  }

  List<Map<String, String>> _getCuratedCountryCodes() {
    return <Map<String, String>>[
      {'code': '00', 'label': '00 · World / Global (Universal)'},
      {'code': 'US', 'label': 'US · United States'},
      {'code': 'DE', 'label': 'DE · Germany'},
      {'code': 'GB', 'label': 'GB · United Kingdom'},
      {'code': 'IN', 'label': 'IN · India'},
      {'code': 'JP', 'label': 'JP · Japan'},
      {'code': 'CA', 'label': 'CA · Canada'},
      {'code': 'AU', 'label': 'AU · Australia'},
      {'code': 'BR', 'label': 'BR · Brazil'},
      {'code': 'CN', 'label': 'CN · China'},
      {'code': 'FR', 'label': 'FR · France'},
      {'code': 'IT', 'label': 'IT · Italy'},
      {'code': 'ES', 'label': 'ES · Spain'},
      {'code': 'KR', 'label': 'KR · South Korea'},
      {'code': 'NL', 'label': 'NL · Netherlands'},
      {'code': 'PL', 'label': 'PL · Poland'},
      {'code': 'SE', 'label': 'SE · Sweden'},
      {'code': 'TW', 'label': 'TW · Taiwan'},
      {'code': 'NZ', 'label': 'NZ · New Zealand'},
      {'code': 'SG', 'label': 'SG · Singapore'},
      {'code': 'HK', 'label': 'HK · Hong Kong'},
      {'code': 'MX', 'label': 'MX · Mexico'},
      {'code': 'AR', 'label': 'AR · Argentina'},
      {'code': 'CL', 'label': 'CL · Chile'},
      {'code': 'ZA', 'label': 'ZA · South Africa'},
      {'code': 'TH', 'label': 'TH · Thailand'},
      {'code': 'VN', 'label': 'VN · Vietnam'},
      {'code': 'ID', 'label': 'ID · Indonesia'},
      {'code': 'MY', 'label': 'MY · Malaysia'},
      {'code': 'PH', 'label': 'PH · Philippines'},
      {'code': 'AE', 'label': 'AE · United Arab Emirates'},
      {'code': 'SA', 'label': 'SA · Saudi Arabia'},
      {'code': 'IL', 'label': 'IL · Israel'},
      {'code': 'TR', 'label': 'TR · Turkey'},
      {'code': 'CH', 'label': 'CH · Switzerland'},
      {'code': 'AT', 'label': 'AT · Austria'},
      {'code': 'BE', 'label': 'BE · Belgium'},
      {'code': 'DK', 'label': 'DK · Denmark'},
      {'code': 'FI', 'label': 'FI · Finland'},
      {'code': 'NO', 'label': 'NO · Norway'},
      {'code': 'IE', 'label': 'IE · Ireland'},
      {'code': 'PT', 'label': 'PT · Portugal'},
      {'code': 'CZ', 'label': 'CZ · Czech Republic'},
      {'code': 'HU', 'label': 'HU · Hungary'},
      {'code': 'RO', 'label': 'RO · Romania'},
      {'code': 'GR', 'label': 'GR · Greece'},
    ];
  }

  List<String> _getAvailableChannels() {
    final channels = <String>[];
    if (_dynamicChannels.isNotEmpty) {
      channels.addAll(_dynamicChannels);
    } else {
      final band = widget.radio.bandLabel;
      if (band.contains('5 GHz') || band.contains('6 GHz')) {
        channels.addAll([
          'auto',
          '36',
          '40',
          '44',
          '48',
          '52',
          '56',
          '60',
          '64',
          '100',
          '104',
          '108',
          '112',
          '116',
          '120',
          '124',
          '128',
          '132',
          '136',
          '140',
          '144',
          '149',
          '153',
          '157',
          '161',
          '165',
        ]);
      } else {
        channels.addAll([
          'auto',
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
          '9',
          '10',
          '11',
          '12',
          '13',
          '14',
        ]);
      }
    }

    if (!channels.contains(_selectedChannel)) {
      channels.insert(0, _selectedChannel);
    }
    return channels;
  }

  Future<void> _findChannel(List<String> channels) async {
    final app = ref.read(appStateProvider);
    final radio = widget.radio;
    final ifname = radio.interfaces
        .map((i) => i.ifName)
        .where((n) => n.isNotEmpty)
        .firstOrNull;
    final picked = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChannelCheckScreen(
          scan: () => scanWifi(app, ifname ?? radio.name),
          is5g: radio.bandLabel.contains('5 GHz'),
          current: int.tryParse(_selectedChannel) ?? 0,
          allowed: {for (final c in channels) ?int.tryParse(c)},
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedChannel = '$picked');
    }
  }

  bool _isValidChannelForCountry(int channel, String countryCode) {
    final validChannels = widget.radio.getValidChannelsForBand(
      countryCode: countryCode.toUpperCase(),
    );
    return validChannels.contains(channel);
  }

  String? _getChannelValidationMessage([AppLocalizations? l10n]) {
    final countryCode = _selectedCountry;
    if (countryCode.isEmpty || _selectedChannel == 'auto') return null;

    final channel = int.tryParse(_selectedChannel);
    if (channel == null) return null;

    if (!_isValidChannelForCountry(channel, countryCode)) {
      final validChannels = widget.radio.getValidChannelsForBand(
        countryCode: countryCode,
      );
      return l10n?.channelInvalidForCountry(
            _selectedChannel,
            countryCode,
            validChannels.join(', '),
          ) ??
          'Channel $_selectedChannel is not valid for country $countryCode. Valid channels: ${validChannels.join(', ')}';
    }
    return null;
  }

  List<String> _getAvailableHtModes() {
    final htModes = <String>[];
    if (_dynamicHtModes.isNotEmpty) {
      htModes.addAll(_dynamicHtModes);
    } else if (widget.radio.supportedHtModes.isNotEmpty) {
      htModes.addAll(widget.radio.supportedHtModes);
    } else {
      final band = widget.radio.bandLabel;
      if (band.contains('5 GHz') || band.contains('6 GHz')) {
        htModes.addAll([
          'HT20',
          'HT40',
          'VHT20',
          'VHT40',
          'VHT80',
          'VHT160',
          'HE20',
          'HE40',
          'HE80',
          'HE160',
          'EHT320',
        ]);
      } else {
        htModes.addAll(['HT20', 'HT40']);
      }
    }

    if (!htModes.contains(_selectedHtMode)) {
      htModes.insert(0, _selectedHtMode);
    }
    return htModes;
  }

  List<String> _getAvailableTxPowers() {
    final txPowers = <String>[];
    if (_dynamicTxPowers.isNotEmpty) {
      txPowers.addAll(_dynamicTxPowers);
    } else {
      txPowers.addAll(['auto', '30', '23', '20', '17', '14', '10']);
    }
    if (!txPowers.contains(_selectedTxPower)) {
      txPowers.insert(1, _selectedTxPower);
    }
    return txPowers;
  }

  Future<void> _submitChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context);
    final channelValidation = _getChannelValidationMessage(l10n);
    if (channelValidation != null) {
      if (!mounted) return;
      final proceed = await LuciGuardrail.showConfirmation(
        context,
        title: 'Channel Regulatory Warning',
        subtitle: channelValidation,
        confirmLabel: l10n?.btnProceedAnyway ?? 'Proceed Anyway',
        cancelLabel: l10n?.actionCancel ?? 'Cancel',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
      );
      if (!proceed) return;
    }

    final appState = ref.read(appStateProvider);
    final radio = widget.radio;

    if (_isDisabled && !radio.isDisabled) {
      final activeMac = appState.dashboardData?['activeSessionMac']
          ?.toString()
          .toUpperCase();
      bool hasActiveSessionOnRadio = false;
      for (final iface in radio.interfaces) {
        for (final st in iface.stations) {
          if (st.macAddress.toUpperCase() == activeMac) {
            hasActiveSessionOnRadio = true;
            break;
          }
        }
      }

      if (hasActiveSessionOnRadio) {
        if (!mounted) return;
        final proceed = await LuciGuardrail.showConfirmation(
          context,
          title:
              l10n?.dialogDisablingActiveRadioTitle ?? 'Disabling Active Radio',
          subtitle:
              l10n?.dialogDisablingActiveRadioMessage(radio.name) ??
              'Disabling physical radio "${radio.name}" will turn off all wireless networks hosted on it and disconnect your active session.',
          confirmLabel: l10n?.btnProceedAndDisable ?? 'Proceed & Disable',
          cancelLabel: l10n?.actionCancel ?? 'Cancel',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          isDestructive: true,
        );
        if (!proceed) return;
      }
    }

    if (!mounted) return;
    setState(() => _isSubmitting = true);

    final newValues = <String, String>{
      'disabled': _isDisabled ? '1' : '0',
      'channel': _selectedChannel,
      'htmode': _selectedHtMode,
      'country': _selectedCountry,
    };
    final deleteOptions = <String>[];
    if (_selectedTxPower == 'auto' || _selectedTxPower.trim().isEmpty) {
      deleteOptions.add('txpower');
    } else {
      newValues['txpower'] = _selectedTxPower.trim();
    }

    final priorSnapshot = <String, String>{
      'disabled': radio.isDisabled ? '1' : '0',
      'channel': radio.channel,
      'htmode': radio.htMode ?? 'HT20',
      'country': radio.country,
    };
    if (radio.txPowerDbm != null) {
      priorSnapshot['txpower'] = radio.txPowerDbm.toString();
    }

    try {
      final success = await appState.applyWirelessRadioConfig(
        sectionName: radio.name,
        newValues: newValues,
        deleteOptions: deleteOptions,
        priorValuesSnapshot: priorSnapshot,
        targetRadio: radio,
        context: mounted ? context : null,
      );

      if (mounted) {
        if (success) {
          Navigator.pop(context, true);
          ksSay(
            context,
            l10n?.toastRadioSettingsSuccess ??
                'Radio settings applied directly to router.',
          );
        } else {
          final username = appState.sessionUsername;
          if ((appState.capabilities?.hasUciWriteAccess ?? true) == false ||
              !appState.isAdministrativeUser) {
            ksSay(
              context,
              'Access Denied: Account \'$username\' lacks ubus UCI write authorization.',
            );
          } else {
            ksSay(
              context,
              l10n?.toastRadioSettingsFailed ??
                  'Failed to apply radio settings to router.',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ksSay(
          context,
          l10n?.toastRadioSettingsFailed ?? 'Failed to apply radio settings',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  static String widthWords(String mode) {
    final m = RegExp(r'^(HT|VHT|HE|EHT)(\d+)').firstMatch(mode.toUpperCase());
    if (m == null) return mode;
    final gen = switch (m.group(1)) {
      'HT' => 'Wi-Fi 4',
      'VHT' => 'Wi-Fi 5',
      'HE' => 'Wi-Fi 6',
      _ => 'Wi-Fi 7',
    };
    return '${m.group(2)} MHz, $gen';
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final appState = ref.watch(appStateProvider);
    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final channels = _getAvailableChannels();
    final htModes = _getAvailableHtModes();
    final txPowers = _getAvailableTxPowers();
    final countryCodes = _getAvailableCountryCodes();
    final channelProblem = _getChannelValidationMessage();
    final canSave = !_isSubmitting && _hasChanges();

    String power(String tx) {
      if (tx == 'auto') return 'As strong as allowed';
      const mw = {
        '30': '1000',
        '23': '200',
        '20': '100',
        '17': '50',
        '14': '25',
        '10': '10',
      };
      return mw[tx] == null ? '$tx dBm' : '$tx dBm (${mw[tx]} mW)';
    }

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
                  widget.radio.bandLabel,
                  subtitle: 'Channel, width and strength for this band',
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
                if (!hasUciWrite)
                  KsBanner(
                    "You're signed in as '${appState.sessionUsername}', which "
                    "may not be allowed to change Wi-Fi. Sign in as root to "
                    'save.',
                    bad: true,
                  ),
                const KsBanner(
                  'Devices on this band drop for a few seconds while the '
                  'router applies a change.',
                ),
                const SizedBox(height: 8),
                KsSwitchRow(
                  title: 'Band on',
                  subtitle: _isDisabled
                      ? 'Every network on this band is off'
                      : 'Networks on this band can be joined',
                  value: !_isDisabled,
                  onChanged: (on) => setState(() => _isDisabled = !on),
                ),
                KsChoice<String>(
                  label: 'Channel',
                  value: _selectedChannel,
                  help: channelProblem,
                  options: [
                    for (final ch in channels)
                      (
                        ch,
                        ch == 'auto'
                            ? 'Pick the quietest one (recommended)'
                            : 'Channel $ch',
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedChannel = v),
                ),
                if (!widget.radio.bandLabel.contains('6 GHz'))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _findChannel(channels),
                      child: const Text('Find a quieter channel'),
                    ),
                  ),
                KsChoice<String>(
                  label: 'Width',
                  value: _selectedHtMode,
                  help: 'Wider is faster up close; narrower is steadier',
                  options: [for (final m in htModes) (m, widthWords(m))],
                  onChanged: (v) => setState(() => _selectedHtMode = v),
                ),
                KsChoice<String>(
                  label: 'Strength',
                  value: _selectedTxPower,
                  options: [for (final tx in txPowers) (tx, power(tx))],
                  onChanged: (v) => setState(() => _selectedTxPower = v),
                ),
                KsChoice<String>(
                  label: 'Country',
                  value: _selectedCountry,
                  help: 'Sets which channels and strength are legal here',
                  options: [
                    for (final c in countryCodes) (c['code']!, c['label']!),
                  ],
                  onChanged: (v) => setState(() => _selectedCountry = v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
