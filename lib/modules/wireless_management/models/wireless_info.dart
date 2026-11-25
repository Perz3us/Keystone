// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

enum PmfState {
  disabled,
  optional,
  required;

  String get displayName {
    switch (this) {
      case PmfState.disabled:
        return 'PMF Disabled';
      case PmfState.optional:
        return 'PMF Optional';
      case PmfState.required:
        return 'PMF Required';
    }
  }

  static PmfState parse(dynamic rawVal) {
    if (rawVal == null) return PmfState.disabled;
    final str = rawVal.toString().trim();
    if (str == '2' || str.toLowerCase() == 'required') return PmfState.required;
    if (str == '1' || str.toLowerCase() == 'optional') return PmfState.optional;
    return PmfState.disabled;
  }
}

enum WifiSecurityMode {
  saeOnly,
  saeMixed,
  wpa2Psk,
  wpaPsk,
  owe,
  wep,
  open,
  enterprise,
  unknown;

  String get displayName {
    switch (this) {
      case WifiSecurityMode.saeOnly:
        return 'WPA3-SAE (SAE-Only)';
      case WifiSecurityMode.saeMixed:
        return 'WPA2/WPA3 Mixed';
      case WifiSecurityMode.wpa2Psk:
        return 'WPA2-PSK';
      case WifiSecurityMode.wpaPsk:
        return 'WPA-PSK';
      case WifiSecurityMode.owe:
        return 'Enhanced Open (OWE)';
      case WifiSecurityMode.wep:
        return 'WEP';
      case WifiSecurityMode.open:
        return 'Open (None)';
      case WifiSecurityMode.enterprise:
        return 'WPA-Enterprise';
      case WifiSecurityMode.unknown:
        return 'Custom/Unknown';
    }
  }

  String get shortBadgeLabel {
    switch (this) {
      case WifiSecurityMode.saeOnly:
        return 'WPA3-SAE';
      case WifiSecurityMode.saeMixed:
        return 'WPA2/WPA3';
      case WifiSecurityMode.wpa2Psk:
        return 'WPA2-PSK';
      case WifiSecurityMode.wpaPsk:
        return 'WPA-PSK';
      case WifiSecurityMode.owe:
        return 'OWE';
      case WifiSecurityMode.wep:
        return 'WEP';
      case WifiSecurityMode.open:
        return 'OPEN';
      case WifiSecurityMode.enterprise:
        return 'WPA-EAP';
      case WifiSecurityMode.unknown:
        return 'UNKNOWN';
    }
  }

  Color get badgeColor {
    switch (this) {
      case WifiSecurityMode.saeOnly:
        return Colors.deepPurple;
      case WifiSecurityMode.saeMixed:
        return Colors.indigo;
      case WifiSecurityMode.wpa2Psk:
        return Colors.green;
      case WifiSecurityMode.wpaPsk:
        return Colors.orange;
      case WifiSecurityMode.owe:
        return Colors.blue;
      case WifiSecurityMode.wep:
        return Colors.red;
      case WifiSecurityMode.open:
        return Colors.amber.shade800;
      case WifiSecurityMode.enterprise:
        return Colors.teal;
      case WifiSecurityMode.unknown:
        return Colors.grey;
    }
  }

  static WifiSecurityMode parse({
    Map<String, dynamic>? iwinfoEnc,
    String? rawConfigEnc,
  }) {
    final configEnc = (rawConfigEnc ?? '').toLowerCase().trim();
    final description = (iwinfoEnc?['description']?.toString() ?? '')
        .toUpperCase();
    final rawEnabled = iwinfoEnc?['enabled'];
    final enabled =
        rawEnabled == null ||
        rawEnabled == true ||
        rawEnabled == 1 ||
        rawEnabled == '1' ||
        rawEnabled == 'true';

    final authSuitesRaw = iwinfoEnc?['auth_suites'];
    final authSuites = <String>[];
    if (authSuitesRaw is List) {
      authSuites.addAll(authSuitesRaw.map((e) => e.toString().toUpperCase()));
    }

    if (configEnc == 'none' ||
        (!enabled && description.isEmpty && configEnc.isEmpty)) {
      return WifiSecurityMode.open;
    }

    final hasSaeSuite =
        authSuites.contains('SAE') ||
        description.contains('SAE') ||
        configEnc.contains('sae');
    final hasOweSuite =
        description.contains('OWE') ||
        configEnc.contains('owe') ||
        configEnc == 'owe';
    final hasPsk2Suite =
        authSuites.contains('PSK') ||
        description.contains('WPA2') ||
        configEnc.contains('psk2');
    final hasPsk1Suite =
        configEnc == 'psk' ||
        (description.contains('WPA') && !description.contains('WPA2'));

    if (hasSaeSuite) {
      if (configEnc == 'sae' ||
          (!hasPsk2Suite &&
              !description.contains('WPA2') &&
              !description.contains('PSK'))) {
        return WifiSecurityMode.saeOnly;
      }
      return WifiSecurityMode.saeMixed;
    }

    if (hasOweSuite) {
      return WifiSecurityMode.owe;
    }

    if (description.contains('802.1X') ||
        description.contains('EAP') ||
        (configEnc.startsWith('wpa') && !configEnc.contains('psk'))) {
      return WifiSecurityMode.enterprise;
    }

    if (hasPsk2Suite) {
      return WifiSecurityMode.wpa2Psk;
    }

    if (hasPsk1Suite || configEnc.contains('psk')) {
      return WifiSecurityMode.wpaPsk;
    }

    if (configEnc.contains('wep') ||
        description.contains('WEP') ||
        (iwinfoEnc?['wep'] == true)) {
      return WifiSecurityMode.wep;
    }

    if (description.isNotEmpty) {
      return WifiSecurityMode.unknown;
    }

    return WifiSecurityMode.wpa2Psk;
  }
}

class WirelessStation {
  final String macAddress;
  final int? signalDbm;
  final int? noiseDbm;
  final num? rxRate;
  final num? txRate;
  final int? inactiveSeconds;

  const WirelessStation({
    required this.macAddress,
    this.signalDbm,
    this.noiseDbm,
    this.rxRate,
    this.txRate,
    this.inactiveSeconds,
  });

  factory WirelessStation.fromJson(String mac, Map<String, dynamic> json) {
    num? parseNum(dynamic val) {
      if (val == null) return null;
      if (val is num) return val;
      return num.tryParse(val.toString().trim());
    }

    int? parseInt(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString().trim());
    }

    final rx =
        parseNum(json['rx_rate']) ??
        parseNum(json['rx_bitrate']) ??
        (json['rx'] is Map
            ? (parseNum(json['rx']['rate']) ?? parseNum(json['rx']['bitrate']))
            : null);
    final tx =
        parseNum(json['tx_rate']) ??
        parseNum(json['tx_bitrate']) ??
        (json['tx'] is Map
            ? (parseNum(json['tx']['rate']) ?? parseNum(json['tx']['bitrate']))
            : null);
    return WirelessStation(
      macAddress: mac,
      signalDbm: parseInt(json['signal']) ?? parseInt(json['signal_dbm']),
      noiseDbm: parseInt(json['noise']) ?? parseInt(json['noise_dbm']),
      rxRate: rx,
      txRate: tx,
      inactiveSeconds: parseInt(json['inactive']),
    );
  }

  String get formattedSignal => signalDbm != null ? '$signalDbm dBm' : 'N/A';

  String get signalQualityLabel {
    if (signalDbm == null) return 'Unknown';
    if (signalDbm! >= -50) return 'Excellent';
    if (signalDbm! >= -65) return 'Good';
    if (signalDbm! >= -75) return 'Fair';
    return 'Weak';
  }
}

String generateWifiQrUri({
  required String ssid,
  required String? password,
  required WifiSecurityMode securityMode,
  required bool isHidden,
}) {
  String escape(String str) {
    return str
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll(':', r'\:')
        .replaceAll('"', r'\"');
  }

  final escapedSsid = escape(ssid);
  final authType = (securityMode == WifiSecurityMode.open)
      ? 'nopass'
      : (securityMode == WifiSecurityMode.wep ? 'WEP' : 'WPA');

  final hiddenVal = isHidden ? 'true' : 'false';

  if (securityMode == WifiSecurityMode.open ||
      password == null ||
      password.isEmpty) {
    return 'WIFI:T:$authType;S:$escapedSsid;;H:$hiddenVal;;';
  } else {
    final escapedPass = escape(password);
    return 'WIFI:T:$authType;S:$escapedSsid;P:$escapedPass;H:$hiddenVal;;';
  }
}

class WirelessInterface {
  final String ifName;
  final String sectionName;
  final String ssid;
  final String mode;
  final String encryption;
  final WifiSecurityMode securityMode;
  final PmfState pmfState;
  final String channel;
  final bool isEnabled;
  final List<WirelessStation> stations;

  final WirelessRadio? radio;

  final String? key;
  final String? cipher;
  final bool isHidden;
  final int? assocSaRetryMax;
  final int? assocSaRetryTimeout;
  final bool ocvEnabled;
  final bool krackCountermeasures;
  final bool gcmp256Enabled;
  final bool saeExtKeyEnabled;
  final String? transitionDisable;
  final bool multiToUnicast;
  final bool isolateClients;
  final bool isolateBridge;
  final int? dtimPeriod;
  final int? gtkRekey;
  final int? inactivityLimit;
  final int? maxListenInterval;
  final bool disassocLowAck;
  final bool fastTransitionEnabled;
  final bool ftOverDs;
  final bool ftPskGenerateLocal;
  final String? mobilityDomain;
  final String? networkBridge;
  final Map<String, dynamic> rawConfig;

  const WirelessInterface({
    required this.ifName,
    required this.sectionName,
    required this.ssid,
    required this.mode,
    required this.encryption,
    required this.securityMode,
    required this.pmfState,
    required this.channel,
    required this.isEnabled,
    required this.stations,
    this.radio,
    this.key,
    this.cipher,
    this.isHidden = false,
    this.assocSaRetryMax,
    this.assocSaRetryTimeout,
    this.ocvEnabled = false,
    this.krackCountermeasures = false,
    this.gcmp256Enabled = false,
    this.saeExtKeyEnabled = false,
    this.transitionDisable,
    this.multiToUnicast = false,
    this.isolateClients = false,
    this.isolateBridge = false,
    this.dtimPeriod,
    this.gtkRekey,
    this.inactivityLimit,
    this.maxListenInterval,
    this.disassocLowAck = true,
    this.fastTransitionEnabled = false,
    this.ftOverDs = false,
    this.ftPskGenerateLocal = false,
    this.mobilityDomain,
    this.networkBridge,
    this.rawConfig = const {},
  });

  WirelessInterface copyWith({
    String? ifName,
    String? sectionName,
    String? ssid,
    String? mode,
    String? encryption,
    WifiSecurityMode? securityMode,
    PmfState? pmfState,
    String? channel,
    bool? isEnabled,
    List<WirelessStation>? stations,
    WirelessRadio? radio,
    String? key,
    String? cipher,
    bool? isHidden,
    int? assocSaRetryMax,
    int? assocSaRetryTimeout,
    bool? ocvEnabled,
    bool? krackCountermeasures,
    bool? gcmp256Enabled,
    bool? saeExtKeyEnabled,
    String? transitionDisable,
    bool? multiToUnicast,
    bool? isolateClients,
    bool? isolateBridge,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool? disassocLowAck,
    bool? fastTransitionEnabled,
    bool? ftOverDs,
    bool? ftPskGenerateLocal,
    String? mobilityDomain,
    String? networkBridge,
    Map<String, dynamic>? rawConfig,
  }) {
    return WirelessInterface(
      ifName: ifName ?? this.ifName,
      sectionName: sectionName ?? this.sectionName,
      ssid: ssid ?? this.ssid,
      mode: mode ?? this.mode,
      encryption: encryption ?? this.encryption,
      securityMode: securityMode ?? this.securityMode,
      pmfState: pmfState ?? this.pmfState,
      channel: channel ?? this.channel,
      isEnabled: isEnabled ?? this.isEnabled,
      stations: stations ?? this.stations,
      radio: radio ?? this.radio,
      key: key ?? this.key,
      cipher: cipher ?? this.cipher,
      isHidden: isHidden ?? this.isHidden,
      assocSaRetryMax: assocSaRetryMax ?? this.assocSaRetryMax,
      assocSaRetryTimeout: assocSaRetryTimeout ?? this.assocSaRetryTimeout,
      ocvEnabled: ocvEnabled ?? this.ocvEnabled,
      krackCountermeasures: krackCountermeasures ?? this.krackCountermeasures,
      gcmp256Enabled: gcmp256Enabled ?? this.gcmp256Enabled,
      saeExtKeyEnabled: saeExtKeyEnabled ?? this.saeExtKeyEnabled,
      transitionDisable: transitionDisable ?? this.transitionDisable,
      multiToUnicast: multiToUnicast ?? this.multiToUnicast,
      isolateClients: isolateClients ?? this.isolateClients,
      isolateBridge: isolateBridge ?? this.isolateBridge,
      dtimPeriod: dtimPeriod ?? this.dtimPeriod,
      gtkRekey: gtkRekey ?? this.gtkRekey,
      inactivityLimit: inactivityLimit ?? this.inactivityLimit,
      maxListenInterval: maxListenInterval ?? this.maxListenInterval,
      disassocLowAck: disassocLowAck ?? this.disassocLowAck,
      fastTransitionEnabled:
          fastTransitionEnabled ?? this.fastTransitionEnabled,
      ftOverDs: ftOverDs ?? this.ftOverDs,
      ftPskGenerateLocal: ftPskGenerateLocal ?? this.ftPskGenerateLocal,
      mobilityDomain: mobilityDomain ?? this.mobilityDomain,
      networkBridge: networkBridge ?? this.networkBridge,
      rawConfig: rawConfig ?? this.rawConfig,
    );
  }

  String get wifiQrUri {
    final rawQr =
        rawConfig['qrcode']?.toString() ?? rawConfig['qr_payload']?.toString();
    if (rawQr != null && rawQr.isNotEmpty) {
      return rawQr;
    }
    return generateWifiQrUri(
      ssid: ssid,
      password: key,
      securityMode: securityMode,
      isHidden: isHidden,
    );
  }

  bool isGuestInterface([
    Set<String>? customGuestSections,
    Set<String>? excludedGuestSections,
  ]) {
    if (excludedGuestSections != null &&
        (excludedGuestSections.contains(sectionName) ||
            excludedGuestSections.contains(ifName))) {
      return false;
    }
    if (customGuestSections != null &&
        (customGuestSections.contains(sectionName) ||
            customGuestSections.contains(ifName))) {
      return true;
    }

    final net = (networkBridge ?? '').toLowerCase();
    final sName = sectionName.toLowerCase();
    final ifcName = ifName.toLowerCase();
    final sSsid = ssid.toLowerCase();

    if (net.contains('guest') || net.contains('gst')) return true;
    if (sName.contains('guest') ||
        sName.contains('gst') ||
        ifcName.contains('guest') ||
        ifcName.contains('gst')) {
      return true;
    }
    if (sSsid.contains('guest') ||
        sSsid.contains('gst') ||
        sSsid.contains('visitor') ||
        sSsid.contains('visit')) {
      return true;
    }
    if (isolateClients && net != 'lan' && net.isNotEmpty) return true;

    return false;
  }

  bool get isGuest => isGuestInterface();

  bool supportsEncryption(
    String encryptionValue, {
    Map<String, List<Map<String, String>>>? hardwareCapabilities,
  }) {
    if (hardwareCapabilities == null ||
        hardwareCapabilities['encryptions'] == null) {
      return _fallbackSupportsEncryption(encryptionValue);
    }

    final supportedEncryptions = hardwareCapabilities['encryptions']!;
    return supportedEncryptions.any((enc) => enc['value'] == encryptionValue);
  }

  bool supportsCipher(
    String cipherValue, {
    Map<String, List<Map<String, String>>>? hardwareCapabilities,
  }) {
    if (hardwareCapabilities == null ||
        hardwareCapabilities['ciphers'] == null) {
      return _fallbackSupportsCipher(cipherValue);
    }

    final supportedCiphers = hardwareCapabilities['ciphers']!;
    return supportedCiphers.any((cipher) => cipher['value'] == cipherValue);
  }

  bool _fallbackSupportsEncryption(String encryptionValue) {
    final band = radio?.bandLabel ?? 'Unknown';
    final is5GHzOr6GHz = band != '2.4 GHz';

    if (encryptionValue == 'sae') return is5GHzOr6GHz;
    if (encryptionValue == 'sae-mixed') {
      return true;
    }
    if (encryptionValue == 'owe') {
      return is5GHzOr6GHz;
    }
    return true;
  }

  bool _fallbackSupportsCipher(String cipherValue) {
    final band = radio?.bandLabel ?? 'Unknown';
    final is5GHzOr6GHz = band != '2.4 GHz';

    if (cipherValue == 'gcmp256') return is5GHzOr6GHz;
    if (cipherValue == 'gcmp128') return is5GHzOr6GHz;
    if (cipherValue == 'ccmp') return true;
    if (cipherValue == 'tkip') return true;
    return true;
  }

  bool get isLastEnabledOnRadio {
    return rawConfig['.last_enabled_on_radio'] == true;
  }

  int get minPassphraseLength {
    switch (securityMode) {
      case WifiSecurityMode.saeOnly:
      case WifiSecurityMode.saeMixed:
      case WifiSecurityMode.wpa2Psk:
      case WifiSecurityMode.wpaPsk:
      case WifiSecurityMode.owe:
        return 8;
      case WifiSecurityMode.wep:
        return 10;
      case WifiSecurityMode.open:
      case WifiSecurityMode.enterprise:
        return 0;
      case WifiSecurityMode.unknown:
        return 8;
    }
  }

  int get maxPassphraseLength {
    switch (securityMode) {
      case WifiSecurityMode.saeOnly:
      case WifiSecurityMode.saeMixed:
      case WifiSecurityMode.wpa2Psk:
      case WifiSecurityMode.wpaPsk:
      case WifiSecurityMode.owe:
        return 63;
      case WifiSecurityMode.wep:
        return 26;
      case WifiSecurityMode.open:
      case WifiSecurityMode.enterprise:
        return 0;
      case WifiSecurityMode.unknown:
        return 63;
    }
  }

  String? validatePassphrase(String passphrase) {
    if (securityMode == WifiSecurityMode.open ||
        securityMode == WifiSecurityMode.enterprise) {
      return null;
    }

    if (passphrase.isEmpty) {
      return 'Passphrase is required for ${securityMode.displayName}';
    }

    if (passphrase.length < minPassphraseLength) {
      return 'Passphrase must be at least $minPassphraseLength characters';
    }

    if (passphrase.length > maxPassphraseLength) {
      return 'Passphrase must not exceed $maxPassphraseLength characters';
    }

    if (securityMode == WifiSecurityMode.wep) {
      final hexOnly = RegExp(r'^[0-9A-Fa-f]+$');
      if (!hexOnly.hasMatch(passphrase)) {
        return 'WEP passphrase must be hexadecimal (0-9, A-F)';
      }
      if (passphrase.length != 10 && passphrase.length != 26) {
        return 'WEP passphrase must be 10 (64-bit) or 26 (128-bit) hex characters';
      }
    }

    return null;
  }

  bool isSecurityDowngrade(WifiSecurityMode newMode) {
    final currentIndex = _securityOrder.indexOf(securityMode);
    final newIndex = _securityOrder.indexOf(newMode);
    if (currentIndex == -1 || newIndex == -1) return false;
    return newIndex > currentIndex;
  }

  static const List<WifiSecurityMode> _securityOrder = [
    WifiSecurityMode.saeOnly,
    WifiSecurityMode.saeMixed,
    WifiSecurityMode.wpa2Psk,
    WifiSecurityMode.wpaPsk,
    WifiSecurityMode.owe,
    WifiSecurityMode.wep,
    WifiSecurityMode.open,
    WifiSecurityMode.enterprise,
    WifiSecurityMode.unknown,
  ];

  factory WirelessInterface.fromJson(
    Map<String, dynamic> json,
    Map<String, dynamic>? assocData,
  ) {
    final config = json['config'] is Map
        ? Map<String, dynamic>.from(json['config'] as Map)
        : <String, dynamic>{};
    final iwinfo = json['iwinfo'] is Map
        ? Map<String, dynamic>.from(json['iwinfo'] as Map)
        : <String, dynamic>{};

    final name =
        json['ifname']?.toString() ?? config['ifname']?.toString() ?? 'wlan';
    final ssidStr =
        iwinfo['ssid']?.toString() ?? config['ssid']?.toString() ?? 'Unnamed';
    final modeStr =
        (iwinfo['mode']?.toString() ?? config['mode']?.toString() ?? 'ap')
            .toUpperCase();
    final encStr =
        iwinfo['encryption']?['description']?.toString() ??
        config['encryption']?.toString() ??
        'WPA2-PSK';
    final chStr = (iwinfo['channel'] ?? config['channel'] ?? 'Auto').toString();

    bool parseDisabledVal(dynamic val) {
      if (val == null) return false;
      if (val is bool) return val;
      final s = val.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }

    final isDisabled = parseDisabledVal(config['disabled'] ?? json['disabled']);
    final enabled = !isDisabled;

    final iwEncMap = iwinfo['encryption'] is Map
        ? Map<String, dynamic>.from(iwinfo['encryption'] as Map)
        : null;
    final rawConfigEnc = config['encryption']?.toString();

    final secMode = WifiSecurityMode.parse(
      iwinfoEnc: iwEncMap,
      rawConfigEnc: rawConfigEnc,
    );

    final rawPmf = config['ieee80211w'] ?? iwinfo['ieee80211w'];
    final pmf = PmfState.parse(rawPmf);

    final passphraseStr =
        config['key']?.toString() ??
        config['passphrase']?.toString() ??
        config['sae_password']?.toString() ??
        config['psk']?.toString() ??
        json['key']?.toString() ??
        json['passphrase']?.toString() ??
        json['sae_password']?.toString() ??
        json['psk']?.toString();

    final cipherStr =
        config['cipher']?.toString() ?? iwEncMap?['ciphers']?.toString();

    bool parseBool(dynamic val) {
      if (val == null) return false;
      final s = val.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }

    int? parseInt(dynamic val) {
      if (val == null) return null;
      return int.tryParse(val.toString().trim());
    }

    final hiddenBool = parseBool(config['hidden'] ?? json['hidden']);
    final ocvBool = parseBool(config['ocv'] ?? json['ocv']);
    final krackBool = parseBool(
      config['wpa_disable_eapol_key_retries'] ??
          json['wpa_disable_eapol_key_retries'],
    );
    final gcmpBool = parseBool(config['gcmp256'] ?? json['gcmp256']);
    final saeExtBool = parseBool(config['sae_ext_key'] ?? json['sae_ext_key']);
    final multi2UniBool = parseBool(
      config['multicast_to_unicast'] ?? json['multicast_to_unicast'],
    );
    final isoClientBool = parseBool(config['isolate'] ?? json['isolate']);
    final isoBridgeBool = parseBool(
      config['isolate_bridge'] ?? json['isolate_bridge'],
    );
    final disassocAckBool = config['disassoc_low_ack'] != null
        ? parseBool(config['disassoc_low_ack'])
        : true;
    final ftBool = parseBool(config['ieee80211r'] ?? json['ieee80211r']);
    final ftDsBool = parseBool(config['ft_over_ds'] ?? json['ft_over_ds']);
    final ftPskLocalBool = parseBool(
      config['ft_psk_generate_local'] ?? json['ft_psk_generate_local'],
    );

    final stationList = <WirelessStation>[];
    if (assocData != null) {
      final candidates = [
        name,
        json['ifname']?.toString(),
        config['ifname']?.toString(),
        json['section']?.toString(),
        config['.name']?.toString(),
        ssidStr,
      ].whereType<String>().toSet();

      dynamic rawStations;
      for (final cand in candidates) {
        if (assocData.containsKey(cand) && assocData[cand] != null) {
          rawStations = assocData[cand];
          break;
        }
      }

      if (rawStations is Map<String, dynamic>) {
        final stationMapOrList =
            rawStations['results'] ?? rawStations['assoclist'] ?? rawStations;
        if (stationMapOrList is List) {
          for (final item in stationMapOrList) {
            if (item is Map<String, dynamic>) {
              final mac =
                  item['mac']?.toString() ??
                  item['macaddr']?.toString() ??
                  'Unknown';
              stationList.add(WirelessStation.fromJson(mac, item));
            } else if (item is String && item.isNotEmpty) {
              stationList.add(WirelessStation.fromJson(item, const {}));
            }
          }
        } else if (stationMapOrList is Map<String, dynamic>) {
          stationMapOrList.forEach((mac, val) {
            if (val is Map<String, dynamic>) {
              stationList.add(WirelessStation.fromJson(mac, val));
            }
          });
        }
      } else if (rawStations is Iterable) {
        for (final item in rawStations) {
          if (item is Map<String, dynamic>) {
            final mac =
                item['mac']?.toString() ??
                item['macaddr']?.toString() ??
                'Unknown';
            stationList.add(WirelessStation.fromJson(mac, item));
          } else if (item is String && item.isNotEmpty) {
            stationList.add(WirelessStation.fromJson(item, const {}));
          }
        }
      }
    }

    final sectionStr =
        json['section']?.toString() ??
        json['.name']?.toString() ??
        config['.name']?.toString() ??
        json['ifname']?.toString() ??
        config['ifname']?.toString() ??
        name;

    return WirelessInterface(
      ifName: name,
      sectionName: sectionStr,
      ssid: ssidStr,
      mode: modeStr,
      encryption: encStr,
      securityMode: secMode,
      pmfState: pmf,
      channel: chStr,
      isEnabled: enabled,
      stations: stationList,
      key: passphraseStr,
      cipher: cipherStr,
      isHidden: hiddenBool,
      assocSaRetryMax: parseInt(config['assoc_sa_retry_max']),
      assocSaRetryTimeout: parseInt(config['assoc_sa_retry_timeout']),
      ocvEnabled: ocvBool,
      krackCountermeasures: krackBool,
      gcmp256Enabled: gcmpBool,
      saeExtKeyEnabled: saeExtBool,
      transitionDisable: config['transition_disable']?.toString(),
      multiToUnicast: multi2UniBool,
      isolateClients: isoClientBool,
      isolateBridge: isoBridgeBool,
      dtimPeriod: parseInt(config['dtim_period']),
      gtkRekey: parseInt(config['gtk_rekey']),
      inactivityLimit: parseInt(config['inactivity_limit']),
      maxListenInterval: parseInt(config['max_listen_interval']),
      disassocLowAck: disassocAckBool,
      fastTransitionEnabled: ftBool,
      ftOverDs: ftDsBool,
      ftPskGenerateLocal: ftPskLocalBool,
      mobilityDomain: config['mobility_domain']?.toString(),
      networkBridge: config['network']?.toString(),
      rawConfig: Map<String, dynamic>.from(config),
    );
  }
}

class WirelessRadio {
  final String name;
  final bool isUp;
  final String channel;
  final int? frequency;
  final int? txPowerDbm;
  final String country;
  final String? htMode;
  final List<String> supportedHtModes;
  final String? hardwareName;
  final bool isDisabled;
  final bool retrySetupFailed;
  final Map<String, dynamic>? rawConfig;
  final List<WirelessInterface> interfaces;

  const WirelessRadio({
    required this.name,
    required this.isUp,
    required this.channel,
    this.frequency,
    this.txPowerDbm,
    required this.country,
    this.htMode,
    this.supportedHtModes = const [],
    this.hardwareName,
    this.isDisabled = false,
    this.retrySetupFailed = false,
    this.rawConfig,
    required this.interfaces,
  });

  factory WirelessRadio.fromJson(
    String radioName,
    Map<String, dynamic> json,
    Map<String, dynamic>? assocData,
  ) {
    final config = json['config'] is Map
        ? Map<String, dynamic>.from(json['config'] as Map)
        : <String, dynamic>{};
    final iwinfo = json['iwinfo'] is Map
        ? Map<String, dynamic>.from(json['iwinfo'] as Map)
        : <String, dynamic>{};
    final rawUp = json['up'];
    final up =
        rawUp == null ||
        rawUp == true ||
        rawUp == 1 ||
        rawUp == '1' ||
        rawUp == 'true';
    final retryFailed =
        json['retry_setup_failed'] == true ||
        json['retry_setup_failed'] == 1 ||
        json['retry_setup_failed'] == '1';
    int? parseInt(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString().trim());
    }

    final ch =
        (json['channel'] ?? config['channel'] ?? iwinfo['channel'] ?? 'Auto')
            .toString();
    int? freq = parseInt(json['frequency']);
    if ((freq == null || freq == 0) && config.isNotEmpty) {
      freq = parseInt(config['frequency']);
    }
    if ((freq == null || freq == 0) && iwinfo.isNotEmpty) {
      freq = parseInt(iwinfo['frequency']);
    }
    final txp =
        parseInt(json['txpower']) ??
        parseInt(config['txpower']) ??
        parseInt(iwinfo['txpower']);
    final ctry =
        json['country']?.toString() ??
        config['country']?.toString() ??
        iwinfo['country']?.toString() ??
        'Global';
    final ht =
        json['htmode']?.toString() ??
        config['htmode']?.toString() ??
        iwinfo['htmode']?.toString();
    final hwName =
        json['hardware']?['name']?.toString() ??
        iwinfo['hardware']?['name']?.toString();

    final rawDisabled = json['disabled'] ?? config['disabled'];
    bool disabled = false;
    if (rawDisabled != null) {
      final s = rawDisabled.toString().trim().toLowerCase();
      disabled = s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }

    final htModesList = <String>[];
    final htRaw = json['htmodes'] ?? config['htmodes'] ?? iwinfo['htmodes'];
    if (htRaw is List) {
      htModesList.addAll(htRaw.map((e) => e.toString()));
    }

    final ifaceList = <WirelessInterface>[];
    final ifacesRaw = json['interfaces'];

    if (ifacesRaw is List) {
      for (final item in ifacesRaw) {
        if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          ifaceList.add(WirelessInterface.fromJson(itemMap, assocData));
          if ((freq == null || freq == 0) && itemMap['iwinfo'] is Map) {
            final iwFreq = parseInt(itemMap['iwinfo']['frequency']);
            if (iwFreq != null && iwFreq > 0) freq = iwFreq;
          }
        }
      }
    } else if (ifacesRaw is Map) {
      ifacesRaw.forEach((_, item) {
        if (item is Map) {
          final itemMap = Map<String, dynamic>.from(item);
          ifaceList.add(WirelessInterface.fromJson(itemMap, assocData));
          if ((freq == null || freq == 0) && itemMap['iwinfo'] is Map) {
            final iwFreq = parseInt(itemMap['iwinfo']['frequency']);
            if (iwFreq != null && iwFreq > 0) freq = iwFreq;
          }
        }
      });
    }

    return WirelessRadio(
      name: radioName,
      isUp: up,
      channel: ch,
      frequency: (freq != null && freq! > 0) ? freq : null,
      txPowerDbm: txp,
      country: ctry,
      htMode: ht,
      supportedHtModes: htModesList,
      hardwareName: hwName,
      isDisabled: disabled,
      retrySetupFailed: retryFailed,
      rawConfig: Map<String, dynamic>.from(config),
      interfaces: ifaceList,
    );
  }

  String? get formattedFrequency {
    if (frequency != null && frequency! > 0) {
      final ghz = frequency! / 1000.0;
      return '${ghz.toStringAsFixed(3)} GHz';
    }
    return null;
  }

  String get bandLabel {
    if (frequency != null && frequency! > 0) {
      if (frequency! >= 5925) return '6 GHz';
      if (frequency! >= 4900) return '5 GHz';
      if (frequency! >= 2400) return '2.4 GHz';
      if (frequency! >= 900) return '900 MHz';
    }
    final chNum = int.tryParse(channel) ?? 0;
    if (chNum > 14) return '5 GHz';
    if (chNum > 0 && chNum <= 14) return '2.4 GHz';
    for (final ifc in interfaces) {
      final ifcCh = int.tryParse(ifc.channel) ?? 0;
      if (ifcCh > 14) return '5 GHz';
      if (ifcCh > 0 && ifcCh <= 14) return '2.4 GHz';
    }
    return 'Wi-Fi';
  }

  List<int> getValidChannelsForBand({String countryCode = 'US'}) {
    final band = bandLabel;
    if (band == '2.4 GHz') {
      if (countryCode == 'US' || countryCode == 'CA') {
        return List.generate(11, (i) => i + 1);
      }
      return List.generate(13, (i) => i + 1);
    } else if (band == '5 GHz') {
      return [
        36,
        40,
        44,
        48,
        52,
        56,
        60,
        64,
        100,
        104,
        108,
        112,
        116,
        120,
        124,
        128,
        132,
        136,
        140,
        144,
        149,
        153,
        157,
        161,
        165,
      ];
    } else if (band == '6 GHz') {
      return List.generate(59, (i) => 1 + i * 4);
    }
    return [1, 6, 11];
  }

  bool isValidChannel(int channel, {String countryCode = 'US'}) {
    return getValidChannelsForBand(countryCode: countryCode).contains(channel);
  }
}

class WirelessOverview {
  final List<WirelessRadio> radios;

  const WirelessOverview({required this.radios});

  factory WirelessOverview.fromDashboardData(
    Map<String, dynamic>? data, {
    bool isReviewerMode = false,
  }) {
    final radioList = <WirelessRadio>[];
    Map<String, dynamic>? assocData;

    if (data != null) {
      assocData = data['wirelessStations'] as Map<String, dynamic>?;

      final wirelessMap = (data['wireless'] is Map
          ? data['wireless'] as Map
          : (data['wirelessInterfaces'] is Map
                ? data['wirelessInterfaces'] as Map
                : null));
      if (wirelessMap != null && wirelessMap.isNotEmpty) {
        wirelessMap.forEach((radioName, radioData) {
          if (radioData is Map) {
            final radioMap = Map<String, dynamic>.from(radioData);
            if (radioMap.containsKey('interfaces') ||
                radioMap.containsKey('up') ||
                radioMap.containsKey('channel')) {
              radioList.add(
                WirelessRadio.fromJson(
                  radioName.toString(),
                  radioMap,
                  assocData,
                ),
              );
            }
          }
        });
      }

      if (data['uciWirelessConfig'] != null) {
        final uciConfig = data['uciWirelessConfig'];
        final uciValues = (uciConfig is Map && uciConfig['values'] is Map)
            ? uciConfig['values'] as Map
            : (uciConfig is Map ? uciConfig : null);

        if (uciValues != null) {
          final uciRadios = <String, Map<String, dynamic>>{};
          final uciIfacesByRadio = <String, List<Map<String, dynamic>>>{};

          uciValues.forEach((key, value) {
            if (value is Map) {
              final mapVal = Map<String, dynamic>.from(value);
              final type = mapVal['.type']?.toString();
              if (type == 'wifi-device') {
                uciRadios[key.toString()] = mapVal;
              } else if (type == 'wifi-iface') {
                final device = mapVal['device']?.toString() ?? 'radio0';
                uciIfacesByRadio.putIfAbsent(device, () => []).add(mapVal);
              }
            }
          });

          if (radioList.isEmpty) {
            uciRadios.forEach((radioName, radioMap) {
              radioList.add(
                WirelessRadio(
                  name: radioName,
                  isUp:
                      radioMap['disabled'] != '1' &&
                      radioMap['disabled'] != true,
                  channel: radioMap['channel']?.toString() ?? 'Auto',
                  frequency: int.tryParse(
                    radioMap['frequency']?.toString() ?? '',
                  ),
                  txPowerDbm: int.tryParse(
                    radioMap['txpower']?.toString() ?? '',
                  ),
                  country: radioMap['country']?.toString() ?? 'Global',
                  interfaces: const [],
                ),
              );
            });
          }

          uciIfacesByRadio.forEach((radioName, ifaceMaps) {
            int rIdx = radioList.indexWhere((r) => r.name == radioName);
            if (rIdx < 0) {
              final newRadio = WirelessRadio(
                name: radioName,
                isUp: true,
                channel: 'Auto',
                country: 'Global',
                interfaces: const [],
              );
              radioList.add(newRadio);
              rIdx = radioList.length - 1;
            }

            final currentRadio = radioList[rIdx];
            final updatedIfaces = List<WirelessInterface>.from(
              currentRadio.interfaces,
            );

            for (final ifaceMap in ifaceMaps) {
              final sectionName =
                  ifaceMap['.name']?.toString() ??
                  ifaceMap['section']?.toString() ??
                  'wifinet';
              final ssid = ifaceMap['ssid']?.toString() ?? 'Unnamed';
              final rawDisabled = ifaceMap['disabled'];
              final isDisabled =
                  rawDisabled == '1' ||
                  rawDisabled == true ||
                  rawDisabled == 'true' ||
                  rawDisabled == 'yes';

              final existingIdx = updatedIfaces.indexWhere(
                (i) =>
                    i.sectionName == sectionName ||
                    (i.ssid.isNotEmpty && i.ssid == ssid),
              );

              if (existingIdx >= 0) {
                final existing = updatedIfaces[existingIdx];
                updatedIfaces[existingIdx] = existing.copyWith(
                  isEnabled: !isDisabled,
                  sectionName: existing.sectionName.isNotEmpty
                      ? existing.sectionName
                      : sectionName,
                  key: existing.key ?? ifaceMap['key']?.toString(),
                  networkBridge:
                      existing.networkBridge ?? ifaceMap['network']?.toString(),
                  rawConfig: {...ifaceMap, ...existing.rawConfig},
                );
              } else {
                final mode = (ifaceMap['mode']?.toString() ?? 'ap')
                    .toUpperCase();
                final enc = ifaceMap['encryption']?.toString() ?? 'WPA2-PSK';
                final ch =
                    ifaceMap['channel']?.toString() ?? currentRadio.channel;

                final newIface = WirelessInterface(
                  ifName: ifaceMap['ifname']?.toString() ?? sectionName,
                  sectionName: sectionName,
                  ssid: ssid,
                  mode: mode,
                  encryption: enc,
                  securityMode: WifiSecurityMode.parse(rawConfigEnc: enc),
                  pmfState: PmfState.parse(ifaceMap['ieee80211w']),
                  channel: ch,
                  isEnabled: !isDisabled,
                  stations: const [],
                  radio: currentRadio,
                  key:
                      ifaceMap['key']?.toString() ??
                      ifaceMap['passphrase']?.toString(),
                  networkBridge: ifaceMap['network']?.toString(),
                  isolateClients:
                      ifaceMap['isolate'] == '1' || ifaceMap['isolate'] == true,
                  isHidden:
                      ifaceMap['hidden'] == '1' || ifaceMap['hidden'] == true,
                  rawConfig: Map<String, dynamic>.from(ifaceMap),
                );
                updatedIfaces.add(newIface);
              }
            }

            radioList[rIdx] = WirelessRadio(
              name: currentRadio.name,
              isUp: currentRadio.isUp,
              channel: currentRadio.channel,
              frequency: currentRadio.frequency,
              txPowerDbm: currentRadio.txPowerDbm,
              country: currentRadio.country,
              htMode: currentRadio.htMode,
              supportedHtModes: currentRadio.supportedHtModes,
              hardwareName: currentRadio.hardwareName,
              isDisabled: currentRadio.isDisabled,
              retrySetupFailed: currentRadio.retrySetupFailed,
              rawConfig: currentRadio.rawConfig,
              interfaces: updatedIfaces,
            );
          });
        }
      }
    }

    if (isReviewerMode && radioList.isEmpty) {
      radioList.addAll([
        const WirelessRadio(
          name: 'radio0',
          isUp: true,
          channel: '6',
          frequency: 2437,
          txPowerDbm: 20,
          country: 'US',
          interfaces: [
            WirelessInterface(
              ifName: 'wlan0',
              sectionName: 'wifinet0',
              ssid: 'OpenWrt-2.4G',
              mode: 'AP',
              encryption: 'psk2',
              securityMode: WifiSecurityMode.wpa2Psk,
              pmfState: PmfState.disabled,
              channel: '6',
              isEnabled: true,
              key: 'SecretPassword123!',
              cipher: 'ccmp',
              dtimPeriod: 2,
              gtkRekey: 3600,
              inactivityLimit: 300,
              disassocLowAck: true,
              isolateClients: false,
              fastTransitionEnabled: true,
              mobilityDomain: '4f57',
              networkBridge: 'lan',
              stations: [
                WirelessStation(
                  macAddress: 'AA:BB:CC:11:22:33',
                  signalDbm: -48,
                  noiseDbm: -95,
                  rxRate: 144,
                  txRate: 72,
                ),
                WirelessStation(
                  macAddress: 'AA:BB:CC:44:55:66',
                  signalDbm: -62,
                  noiseDbm: -92,
                  rxRate: 108,
                  txRate: 54,
                ),
              ],
            ),
            WirelessInterface(
              ifName: 'wlan0-1',
              sectionName: 'wifinet_guest',
              ssid: 'OpenWrt-Guest',
              mode: 'AP',
              encryption: 'psk2',
              securityMode: WifiSecurityMode.wpa2Psk,
              pmfState: PmfState.disabled,
              channel: '6',
              isEnabled: false,
              key: 'GuestPass2026',
              cipher: 'ccmp',
              isolateClients: true,
              networkBridge: 'guest',
              stations: [],
            ),
          ],
        ),
        const WirelessRadio(
          name: 'radio1',
          isUp: true,
          channel: '36',
          frequency: 5180,
          txPowerDbm: 23,
          country: 'US',
          interfaces: [
            WirelessInterface(
              ifName: 'wlan1',
              sectionName: 'wifinet1',
              ssid: 'OpenWrt-5G',
              mode: 'AP',
              encryption: 'sae',
              securityMode: WifiSecurityMode.saeOnly,
              pmfState: PmfState.required,
              channel: '36',
              isEnabled: true,
              key: 'SuperSecureWpa3Passphrase#2026',
              cipher: 'ccmp',
              dtimPeriod: 2,
              gtkRekey: 3600,
              inactivityLimit: 300,
              disassocLowAck: true,
              isolateClients: true,
              fastTransitionEnabled: true,
              mobilityDomain: '4f57',
              networkBridge: 'lan',
              stations: [
                WirelessStation(
                  macAddress: 'AA:BB:CC:77:88:99',
                  signalDbm: -38,
                  noiseDbm: -98,
                  rxRate: 433,
                  txRate: 433,
                ),
              ],
            ),
          ],
        ),
      ]);
    }

    for (int i = 0; i < radioList.length; i++) {
      final r = radioList[i];
      final sortedInterfaces = List<WirelessInterface>.from(r.interfaces)
        ..sort((a, b) {
          if (a.isEnabled != b.isEnabled) {
            return a.isEnabled ? -1 : 1;
          }
          return a.ssid.compareTo(b.ssid);
        });

      for (int j = 0; j < sortedInterfaces.length; j++) {
        final ifc = sortedInterfaces[j];
        final sortedStations = List<WirelessStation>.from(ifc.stations)
          ..sort((a, b) {
            final aSig = a.signalDbm ?? -999;
            final bSig = b.signalDbm ?? -999;
            return aSig.compareTo(bSig);
          });
        sortedInterfaces[j] = ifc.copyWith(stations: sortedStations);
      }

      radioList[i] = WirelessRadio(
        name: r.name,
        isUp: r.isUp,
        channel: r.channel,
        frequency: r.frequency,
        txPowerDbm: r.txPowerDbm,
        country: r.country,
        htMode: r.htMode,
        supportedHtModes: r.supportedHtModes,
        hardwareName: r.hardwareName,
        isDisabled: r.isDisabled,
        retrySetupFailed: r.retrySetupFailed,
        rawConfig: r.rawConfig,
        interfaces: sortedInterfaces,
      );
    }

    radioList.sort((a, b) {
      if (a.isUp != b.isUp) {
        return a.isUp ? -1 : 1;
      }
      return a.name.compareTo(b.name);
    });

    return WirelessOverview(radios: radioList);
  }

  int get totalConnectedStations {
    int count = 0;
    for (final radio in radios) {
      for (final iface in radio.interfaces) {
        count += iface.stations.length;
      }
    }
    return count;
  }
}
