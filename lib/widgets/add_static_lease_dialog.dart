// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/utils/error_words.dart';

class AddStaticLeaseDialog extends StatefulWidget {
  final String? macAddress;
  final String? initialIp;
  final String? initialIp6;
  final String? initialDuid;
  final String? initialHostname;
  final Client? client;
  final List<Client>? allClients;
  final DhcpStaticMapping? existingMapping;
  final VoidCallback? onSaved;

  const AddStaticLeaseDialog({
    super.key,
    this.macAddress,
    this.initialIp,
    this.initialIp6,
    this.initialDuid,
    this.initialHostname,
    this.client,
    this.allClients,
    this.existingMapping,
    this.onSaved,
  });

  @override
  State<AddStaticLeaseDialog> createState() => _AddStaticLeaseDialogState();
}

class _AddStaticLeaseDialogState extends State<AddStaticLeaseDialog> {
  late TextEditingController _macController;
  late TextEditingController _nameController;
  late TextEditingController _ipController;
  late TextEditingController _ip6Controller;
  late TextEditingController _duidController;
  late TextEditingController _customLeaseController;

  String _selectedLeasePreset = '12h';
  bool _submittedOnce = false;
  bool _macTouched = false;
  bool _nameTouched = false;
  bool _ipTouched = false;
  bool _ip6Touched = false;
  bool _duidTouched = false;
  bool _customLeaseTouched = false;
  bool _showIp6Section = false;

  String? _rawMacError;
  String? _rawNameError;
  String? _rawIpError;
  String? _rawIp6Error;
  String? _rawDuidError;
  String? _rawLeaseError;

  String? _macError;
  String? _nameError;
  String? _ipError;
  String? _ip6Error;
  String? _duidError;
  String? _leaseTimeError;

  String? _clipboardMac;

  DhcpStaticMapping? _detectedMapping;

  late final String _initialMacText;
  late final String _initialNameText;
  late final String _initialIpText;
  late final String _initialLeasePreset;
  late final String _initialCustomLeaseText;

  bool get _isEditing =>
      _detectedMapping != null ||
      widget.existingMapping != null ||
      (widget.client != null && widget.client!.isStatic);

  bool get _hasChanges => !_isEditing || _edited;

  bool get _edited {
    final currentMac = _normMac(_effectiveMac);
    final currentName = _nameController.text.trim();
    final currentIp = _ipController.text.trim();
    final currentPreset = _selectedLeasePreset;
    final currentCustomLease = _customLeaseController.text.trim();

    if (currentMac != _initialMacText) return true;
    if (currentName != _initialNameText) return true;
    if (currentIp != _initialIpText) return true;
    if (currentPreset != _initialLeasePreset) return true;
    if (currentPreset == 'custom' &&
        currentCustomLease != _initialCustomLeaseText) {
      return true;
    }

    return false;
  }

  String get _effectiveMac {
    if (widget.macAddress != null && widget.macAddress!.trim().isNotEmpty) {
      return widget.macAddress!.trim();
    }
    if (widget.existingMapping != null &&
        widget.existingMapping!.macAddress.isNotEmpty) {
      return widget.existingMapping!.macAddress.trim();
    }
    if (widget.client != null && widget.client!.macAddress.isNotEmpty) {
      return widget.client!.macAddress.trim();
    }
    try {
      return _macController.text.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _checkClipboardForMac() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.trim().isNotEmpty) {
        final parsed = _parseFlexibleMac(data.text!);
        if (parsed != null && mounted) {
          setState(() {
            _clipboardMac = parsed;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    final client = widget.client;

    final initialMac =
        (widget.macAddress != null && widget.macAddress!.trim().isNotEmpty)
        ? widget.macAddress!.trim()
        : ((widget.existingMapping != null &&
                  widget.existingMapping!.macAddress.isNotEmpty)
              ? widget.existingMapping!.macAddress.trim()
              : ((client != null && client.macAddress.isNotEmpty)
                    ? client.macAddress.trim()
                    : ''));

    if (widget.existingMapping != null) {
      _detectedMapping = widget.existingMapping;
    } else if (initialMac.isNotEmpty) {
      _detectedMapping = AppState.instance.findStaticLeaseByMac(initialMac);
    }
    final mapping = _detectedMapping;
    _macController = TextEditingController(text: initialMac.toUpperCase());

    String cleanInitialName(String? raw) {
      if (raw == null) return '';
      final trimmed = raw.trim();
      if (trimmed.isEmpty ||
          trimmed == 'Anonymous Device' ||
          trimmed == 'Anonymous IPv6 Host' ||
          trimmed == 'Unknown' ||
          trimmed == 'N/A' ||
          trimmed == '*') {
        return '';
      }
      return trimmed.replaceAll(RegExp(r'\s+'), '-');
    }

    final rawNameCandidate = (mapping != null && mapping.hostname.isNotEmpty)
        ? mapping.hostname
        : ((widget.initialHostname != null &&
                  widget.initialHostname!.isNotEmpty)
              ? widget.initialHostname!
              : ((client != null &&
                        client.displayName.isNotEmpty &&
                        client.displayName != client.macAddress &&
                        client.displayName != 'Unknown')
                    ? client.displayName
                    : (client != null && client.hostname != 'Unknown'
                          ? client.hostname
                          : '')));

    final initialName = cleanInitialName(rawNameCandidate);
    _nameController = TextEditingController(text: initialName);

    final initialIpVal =
        (mapping != null &&
            mapping.ipAddress.isNotEmpty &&
            mapping.ipAddress != 'N/A')
        ? mapping.ipAddress
        : ((widget.initialIp != null && _isValidIPv4(widget.initialIp!))
              ? widget.initialIp!
              : ((client != null && _isValidIPv4(client.ipAddress))
                    ? client.ipAddress
                    : ''));
    _ipController = TextEditingController(text: initialIpVal);

    final initialIp6Val = (mapping != null && mapping.ip6Address.isNotEmpty)
        ? mapping.ip6Address.trim()
        : ((widget.initialIp6 != null && widget.initialIp6!.trim().isNotEmpty)
              ? widget.initialIp6!.trim()
              : '');
    _ip6Controller = TextEditingController(text: initialIp6Val);

    final initialDuidVal = (mapping != null && mapping.duid.isNotEmpty)
        ? mapping.duid.trim()
        : ((widget.initialDuid != null && widget.initialDuid!.trim().isNotEmpty)
              ? widget.initialDuid!.trim()
              : '');
    _duidController = TextEditingController(text: initialDuidVal.toUpperCase());

    _showIp6Section = initialIp6Val.isNotEmpty || initialDuidVal.isNotEmpty;

    String initCustomText = '12h';
    if (mapping != null && mapping.leaseTime.trim().isNotEmpty) {
      final rawLt = mapping.leaseTime.trim().toLowerCase();
      if (['12h', '24h', '7d', 'infinite'].contains(rawLt)) {
        _selectedLeasePreset = rawLt;
      } else {
        _selectedLeasePreset = 'custom';
        initCustomText = mapping.leaseTime.trim();
      }
    }
    _customLeaseController = TextEditingController(text: initCustomText);

    _initialMacText = _normMac(initialMac);
    _initialNameText = initialName.trim();
    _initialIpText = initialIpVal.trim();
    _initialLeasePreset = _selectedLeasePreset;
    _initialCustomLeaseText = initCustomText.trim();

    _macController.addListener(() {
      if (!_macTouched && _macController.text.isNotEmpty) {
        _macTouched = true;
      }
      _validateInputs();
    });
    _nameController.addListener(() {
      if (!_nameTouched && _nameController.text.isNotEmpty) {
        _nameTouched = true;
      }
      _validateInputs();
    });
    _ipController.addListener(() {
      if (!_ipTouched && _ipController.text.isNotEmpty) {
        _ipTouched = true;
      }
      _validateInputs();
    });
    _ip6Controller.addListener(() {
      if (!_ip6Touched && _ip6Controller.text.isNotEmpty) {
        _ip6Touched = true;
      }
      _validateInputs();
    });
    _duidController.addListener(() {
      if (!_duidTouched && _duidController.text.isNotEmpty) {
        _duidTouched = true;
      }
      _validateInputs();
    });
    _customLeaseController.addListener(() {
      if (!_customLeaseTouched && _customLeaseController.text.isNotEmpty) {
        _customLeaseTouched = true;
      }
      _validateInputs();
    });

    if (initialMac.isEmpty) _checkClipboardForMac();

    WidgetsBinding.instance.addPostFrameCallback((_) => _validateInputs());
  }

  @override
  void dispose() {
    _macController.dispose();
    _nameController.dispose();
    _ipController.dispose();
    _ip6Controller.dispose();
    _duidController.dispose();
    _customLeaseController.dispose();
    super.dispose();
  }

  bool _isValidIPv4(String ip) {
    if (ip == 'N/A' || ip.trim().isEmpty) return false;
    final reg = RegExp(
      r'^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.){3}(25[0-5]|(2[0-4]|1\d|[1-9]|)\d)$',
    );
    return reg.hasMatch(ip.trim());
  }

  String? _parseFlexibleMac(String input) {
    final trimmed = input.trim();
    final pairReg = RegExp(r'(?:[0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}');
    final matchPair = pairReg.firstMatch(trimmed);
    if (matchPair != null) {
      return matchPair.group(0)!.toUpperCase().replaceAll('-', ':');
    }

    final ciscoReg = RegExp(r'[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}\.[0-9a-fA-F]{4}');
    final matchCisco = ciscoReg.firstMatch(trimmed);
    if (matchCisco != null) {
      final cleaned = matchCisco.group(0)!.replaceAll('.', '');
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    final raw12Reg = RegExp(r'\b[0-9a-fA-F]{12}\b');
    final match12 = raw12Reg.firstMatch(trimmed);
    if (match12 != null) {
      final cleaned = match12.group(0)!;
      final sb = StringBuffer();
      for (int i = 0; i < 12; i += 2) {
        if (i > 0) sb.write(':');
        sb.write(cleaned.substring(i, i + 2).toUpperCase());
      }
      return sb.toString();
    }

    return null;
  }

  bool _isValidMac(String mac) {
    if (mac.trim().isEmpty) return false;
    final parsed = _parseFlexibleMac(mac);
    if (parsed != null) return true;
    final reg = RegExp(r'^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$');
    return reg.hasMatch(mac.trim());
  }

  String _normMac(String mac) {
    final parsed = _parseFlexibleMac(mac);
    if (parsed != null) return parsed;
    return mac.toUpperCase().replaceAll('-', ':');
  }

  Future<void> _pasteMacFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null && data.text!.isNotEmpty) {
        final pasted = data.text!;
        final parsed = _parseFlexibleMac(pasted);
        if (parsed != null) {
          setState(() {
            _macTouched = true;
            _macController.text = parsed;
          });
          _validateInputs();
          if (mounted) {
            unawaited(
              OsPlatformIntegration.triggerHaptic(OsHapticType.selection),
            );
            ksSay(context, 'Pasted $parsed.');
          }
          return;
        }
      }
      if (mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        ksSay(context, 'What you copied isn\'t a MAC address.');
      }
    } catch (_) {
      if (mounted) {
        ksSay(context, 'Couldn\'t read what you copied.');
      }
    }
  }

  bool _isValidIPv6OrHostId(String ip6) {
    final trimmed = ip6.trim();
    if (trimmed.isEmpty) return true;
    if (RegExp(r'^(::)?[0-9a-fA-F]{1,4}$').hasMatch(trimmed)) return true;
    try {
      final unbracketed = (trimmed.startsWith('[') && trimmed.endsWith(']'))
          ? trimmed.substring(1, trimmed.length - 1)
          : trimmed;
      Uri.parseIPv6Address(unbracketed.split('/').first);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isValidDuid(String duid) {
    final trimmed = duid.trim();
    if (trimmed.isEmpty) return true;
    final clean = trimmed.replaceAll(':', '').replaceAll('-', '');
    return clean.length >= 6 &&
        clean.length % 2 == 0 &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
  }

  void _validateInputs() {
    final mac = _effectiveMac;
    final duid = _duidController.text.trim();
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
    final ip6 = _ip6Controller.text.trim();
    final customLease = _customLeaseController.text.trim();

    String? macErr;
    String? duidErr;
    String? nameErr;
    String? ipErr;
    String? ip6Err;
    String? leaseErr;

    if (mac.isEmpty && duid.isEmpty) {
      macErr = 'Provide a MAC address or DUID identifier';
    } else {
      if (mac.isNotEmpty && !_isValidMac(mac) && !mac.startsWith('DUID:')) {
        macErr = 'Enter a valid MAC address (e.g. AA:BB:CC:DD:EE:FF)';
      }
      if (duid.isNotEmpty && !_isValidDuid(duid)) {
        duidErr = 'Enter a valid DUID hex string';
      }
    }

    if (name.isEmpty) {
      nameErr = 'Hostname cannot be empty';
    } else if (RegExp(r'\s').hasMatch(name)) {
      nameErr = 'Hostname cannot contain spaces';
    } else if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(name)) {
      nameErr = 'Use only letters, numbers, hyphens, and dots';
    }

    if (ip.isEmpty && ip6.isEmpty) {
      ipErr = 'Provide at least an IPv4 or IPv6 address reservation';
    } else {
      if (ip.isNotEmpty) {
        if (!_isValidIPv4(ip)) {
          ipErr = 'Enter a valid IPv4 address (e.g. 192.168.1.150)';
        } else {
          final appState = AppState.instance;
          final selectedRouter = appState.selectedRouter;
          final currentMacNorm = _normMac(mac);

          if (selectedRouter != null && selectedRouter.ipAddress.trim() == ip) {
            ipErr = 'Conflict: $ip is the router\'s gateway address';
          }

          if (ipErr == null && widget.allClients != null) {
            for (final other in widget.allClients!) {
              if (_normMac(other.macAddress) != currentMacNorm &&
                  other.ipAddress.trim() == ip) {
                ipErr =
                    'Conflict: $ip is used by "${other.displayName}" (${other.macAddress})';
                break;
              }
            }
          }

          if (ipErr == null) {
            final hostHints =
                appState.dashboardData?['hostHints'] as Map<String, dynamic>? ??
                {};
            hostHints.forEach((hMac, info) {
              if (ipErr != null) return;
              if (_normMac(hMac) != currentMacNorm) {
                final staticIp = info['staticLeaseIp']?.toString();
                final ipaddrs = info['ipaddrs'] as List?;
                final hintName =
                    info['name']?.toString() ??
                    info['staticLeaseName']?.toString() ??
                    hMac;
                if (staticIp == ip ||
                    (ipaddrs != null && ipaddrs.contains(ip))) {
                  ipErr =
                      'Conflict: $ip is reserved for static lease "$hintName" ($hMac)';
                }
              }
            });
          }
        }
      }

      if (ip6.isNotEmpty && !_isValidIPv6OrHostId(ip6)) {
        ip6Err =
            'Enter a valid IPv6 address or Host ID (e.g. 2405:201::100 or ::100)';
      }
    }

    if (_selectedLeasePreset == 'custom') {
      if (customLease.isEmpty) {
        leaseErr = 'Specify custom lease duration (e.g. 2h, 30m, 3d)';
      } else if (customLease.toLowerCase() != 'infinite' &&
          !RegExp(
            r'^\d+[smhdw]$',
            caseSensitive: false,
          ).hasMatch(customLease)) {
        leaseErr =
            'Invalid format (use e.g. 30m, 2h, 12h, 1d, 7w, or infinite)';
      }
    }

    _rawMacError = macErr;
    _rawDuidError = duidErr;
    _rawNameError = nameErr;
    _rawIpError = ipErr;
    _rawIp6Error = ip6Err;
    _rawLeaseError = leaseErr;

    if (mounted) {
      setState(() {
        _macError = (_submittedOnce || _macTouched || mac.isNotEmpty)
            ? macErr
            : null;
        _duidError = (_submittedOnce || _duidTouched || duid.isNotEmpty)
            ? duidErr
            : null;
        _nameError = (_submittedOnce || _nameTouched || name.isNotEmpty)
            ? nameErr
            : null;
        _ipError = (_submittedOnce || _ipTouched || ip.isNotEmpty)
            ? ipErr
            : null;
        _ip6Error = (_submittedOnce || _ip6Touched || ip6.isNotEmpty)
            ? ip6Err
            : null;
        _leaseTimeError =
            (_submittedOnce || _customLeaseTouched || customLease.isNotEmpty)
            ? leaseErr
            : null;
      });
    }
  }

  Future<void> _submit() async {
    if (ActionRateLimiter.isRateLimited(
      'add_static_lease_submit',
      cooldown: const Duration(milliseconds: 1200),
    )) {
      if (mounted) {
        ksSay(context, 'Still saving…');
      }
      return;
    }

    _submittedOnce = true;
    _validateInputs();
    if (_rawMacError != null ||
        _rawDuidError != null ||
        _rawNameError != null ||
        _rawIpError != null ||
        _rawIp6Error != null ||
        _rawLeaseError != null) {
      if (mounted) {
        ksSay(context, 'Fix the marked boxes first.');
      }
      return;
    }

    final targetMac = _effectiveMac;
    final hostname = _nameController.text.trim();
    final targetIp = _ipController.text.trim();
    final targetIp6 = _ip6Controller.text.trim();
    final duid = _duidController.text.trim();
    final leaseTime = _selectedLeasePreset == 'custom'
        ? _customLeaseController.text.trim()
        : _selectedLeasePreset;
    final onSavedCallback = widget.onSaved;

    final liveIp = widget.client?.ipAddress ?? widget.initialIp;
    final hasIpDiscrepancy =
        liveIp != null &&
        liveIp.isNotEmpty &&
        liveIp != 'N/A' &&
        liveIp != targetIp &&
        (widget.client == null || widget.client!.isConnected);

    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));

    final parentContext = Navigator.of(context).context;
    Navigator.of(context).pop();

    if (parentContext.mounted) {}

    try {
      final appState = AppState.instance;
      final success = await appState.addStaticLease(
        macAddress: targetMac,
        targetIp: targetIp,
        hostname: hostname,
        targetIp6: targetIp6.isNotEmpty ? targetIp6 : null,
        duid: duid.isNotEmpty ? duid : null,
        leaseTime: leaseTime,
        context: parentContext.mounted ? parentContext : null,
      );

      if (parentContext.mounted) {
        if (success) {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
          ksSay(parentContext, '$hostname now always gets $targetIp.');
          onSavedCallback?.call();

          if (hasIpDiscrepancy) {
            unawaited(
              _promptLiveClientRefresh(
                parentContext,
                targetMac,
                hostname,
                liveIp,
                targetIp,
              ),
            );
          }
        } else {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
          ksSay(
            parentContext,
            'The router didn\'t save that. Nothing was changed.',
          );
        }
      }
    } catch (e) {
      if (parentContext.mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        ksSay(
          parentContext,
          'The router didn\'t save that. Nothing was changed.',
        );
      }
    }
  }

  Future<void> _deleteLease() async {
    final targetMac = _effectiveMac;
    final hostname = _nameController.text.trim();
    final targetIp = _ipController.text.trim();
    final duid = _duidController.text.trim();

    final confirm = await ksConfirm(
      context,
      title: 'Remove the fixed address?',
      body:
          '$hostname keeps $targetIp until it next reconnects, then '
          'gets whatever address is free.',
      action: 'Remove',
      danger: true,
    );

    if (confirm != true || !mounted) return;

    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
    final parentContext = Navigator.of(context).context;
    final onSavedCallback = widget.onSaved;
    Navigator.of(context).pop();

    if (parentContext.mounted) {}

    try {
      final appState = AppState.instance;
      final success = await appState.deleteStaticLease(
        macAddress: targetMac,
        targetIp: targetIp.isNotEmpty && targetIp != 'N/A' ? targetIp : null,
        hostname: hostname.isNotEmpty && hostname != 'Unknown'
            ? hostname
            : null,
        duid: duid.isNotEmpty && duid != 'N/A' ? duid : null,
        context: parentContext.mounted ? parentContext : null,
      );

      if (parentContext.mounted) {
        if (success) {
          appState.invalidateStaticLeasesCache();
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
          ksSay(parentContext, '$hostname no longer has a fixed address.');
          onSavedCallback?.call();
        } else {
          unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
          ksSay(
            parentContext,
            'The router didn\'t remove it. Nothing was changed.',
          );
        }
      }
    } catch (e) {
      if (parentContext.mounted) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        ksSay(
          parentContext,
          'The router didn\'t remove it. Nothing was changed.',
        );
      }
    }
  }

  static Future<void> _promptLiveClientRefresh(
    BuildContext context,
    String macAddress,
    String hostname,
    String liveIp,
    String reservedIp,
  ) async {
    final confirmed = await ksConfirm(
      context,
      title: 'Move $hostname now?',
      body:
          'It still uses $liveIp. Reconnecting it moves it to $reservedIp '
          'straight away. Only this device drops for a moment.',
      action: 'Reconnect',
    );

    if (confirmed == true && context.mounted) {
      final res = await AppState.instance.refreshClientConnection(
        macAddress: macAddress,
        context: context,
      );
      if (context.mounted) {
        if (res) {
          ksSay(context, '$hostname is reconnecting.');
        } else {
          ksSay(
            context,
            'Couldn\'t reconnect $hostname. Turn its Wi-Fi off and on.',
          );
        }
      }
    }
  }

  Future<void> _pickLeaseExpiryDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now.add(const Duration(minutes: 5)),
      lastDate: now.add(const Duration(days: 3650)),
      helpText: 'Select Static Lease Expiration Date',
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
      helpText: 'Select Static Lease Expiration Time',
    );

    if (pickedTime == null || !mounted) return;

    final expiryDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    final diff = expiryDateTime.difference(now);
    if (diff.inSeconds < 120) {
      if (mounted) {
        ksSay(context, 'Pick a time at least 2 minutes from now.');
      }
      return;
    }

    String formatted;
    if (diff.inDays >= 7 && diff.inDays % 7 == 0) {
      formatted = '${diff.inDays ~/ 7}w';
    } else if (diff.inDays >= 1) {
      formatted = '${diff.inDays}d';
    } else if (diff.inHours >= 1) {
      formatted = '${diff.inHours}h';
    } else {
      formatted = '${diff.inMinutes}m';
    }

    setState(() {
      _customLeaseController.text = formatted;
    });
    _validateInputs();
  }

  String _findSuggestedFreeIp(DhcpDnsOverview dhcpOverview) {
    final subnets = dhcpOverview.configuredSubnets;

    final targetIp =
        widget.initialIp ??
        widget.existingMapping?.ipAddress ??
        widget.client?.ipAddress ??
        _ipController.text.trim();

    SubnetInfo primarySubnet;
    if (_isValidIPv4(targetIp)) {
      primarySubnet = subnets.firstWhere(
        (s) => s.containsIp(targetIp),
        orElse: () {
          final parts = targetIp.split('.');
          final gw = '${parts[0]}.${parts[1]}.${parts[2]}.1';
          return SubnetInfo(
            interfaceName: 'lan',
            gatewayIp: gw,
            netmask: '255.255.255.0',
            poolStart: 100,
            poolLimit: 150,
          );
        },
      );
    } else {
      primarySubnet = subnets.firstWhere(
        (s) => s.interfaceName.toLowerCase() == 'lan',
        orElse: () => subnets.isNotEmpty
            ? subnets.first
            : const SubnetInfo(
                interfaceName: 'lan',
                gatewayIp: '192.168.1.1',
                netmask: '255.255.255.0',
                poolStart: 100,
                poolLimit: 150,
              ),
      );
    }

    final gwIp = primarySubnet.gatewayIp.trim();
    final parts = gwIp.split('.');
    if (parts.length != 4) return '192.168.1.150';

    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';

    final usedIps = <String>{gwIp};

    for (final lease in dhcpOverview.activeLeases) {
      if (lease.ipAddress.isNotEmpty && lease.ipAddress != 'N/A') {
        usedIps.add(lease.ipAddress.trim());
      }
    }

    for (final mapping in dhcpOverview.staticMappings) {
      if (mapping.ipAddress.isNotEmpty && mapping.ipAddress != 'N/A') {
        usedIps.add(mapping.ipAddress.trim());
      }
    }

    if (widget.allClients != null) {
      for (final client in widget.allClients!) {
        if (client.ipAddress.isNotEmpty && client.ipAddress != 'N/A') {
          usedIps.add(client.ipAddress.trim());
        }
      }
    }

    final hostHints =
        AppState.instance.dashboardData?['hostHints']
            as Map<String, dynamic>? ??
        {};
    hostHints.forEach((_, info) {
      final staticIp = info['staticLeaseIp']?.toString();
      if (staticIp != null && staticIp.isNotEmpty) usedIps.add(staticIp.trim());
      final ipaddrs = info['ipaddrs'] as List?;
      if (ipaddrs != null) {
        for (final ip in ipaddrs) {
          if (ip != null) usedIps.add(ip.toString().trim());
        }
      }
    });

    final startHost = primarySubnet.poolStart ?? 100;
    final limitHost = primarySubnet.poolLimit ?? 150;
    final endHost = (startHost + limitHost - 1).clamp(2, 254);

    for (int host = startHost; host <= endHost; host++) {
      final cand = '$prefix.$host';
      if (!usedIps.contains(cand)) {
        return cand;
      }
    }

    for (int host = 10; host <= 254; host++) {
      final cand = '$prefix.$host';
      if (!usedIps.contains(cand)) {
        return cand;
      }
    }

    return '$prefix.150';
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final hasFixedMac =
        (widget.macAddress != null && widget.macAddress!.isNotEmpty) ||
        (widget.existingMapping != null &&
            widget.existingMapping!.macAddress.isNotEmpty) ||
        (widget.client != null && widget.client!.macAddress.isNotEmpty);
    final canSave =
        _rawMacError == null &&
        _rawNameError == null &&
        _rawIpError == null &&
        _rawLeaseError == null &&
        _hasChanges;

    final dhcpOverview = DhcpDnsOverview.fromDashboardData(
      AppState.instance.dashboardData,
      isReviewerMode: AppState.instance.reviewerModeEnabled,
    );
    final suggestedIp = _findSuggestedFreeIp(dhcpOverview);
    final rawClientDisplay = widget.client?.displayName.trim();
    final suggestedHostname =
        (rawClientDisplay != null &&
            rawClientDisplay.isNotEmpty &&
            rawClientDisplay != 'Unknown' &&
            rawClientDisplay != 'Anonymous Device' &&
            rawClientDisplay != 'Anonymous IPv6 Host')
        ? rawClientDisplay.replaceAll(RegExp(r'\s+'), '-')
        : 'Host-${suggestedIp.split('.').last}';

    SubnetInfo? currentSubnet;
    final currentIp = _ipController.text.trim();
    if (_isValidIPv4(currentIp)) {
      for (final sub in dhcpOverview.configuredSubnets) {
        if (sub.containsIp(currentIp)) {
          currentSubnet = sub;
          break;
        }
      }
    }

    void setIp6(bool v) {
      setState(() {
        _showIp6Section = v;
        if (!v) {
          _ip6Controller.clear();
          _duidController.clear();
          _ip6Touched = false;
          _duidTouched = false;
        }
      });
      _validateInputs();
    }

    return PopScope(
      canPop: !_edited,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await ksConfirm(
          context,
          title: 'Leave without saving?',
          body: 'Your changes to this fixed address are lost.',
          action: 'Leave',
          danger: true,
        );
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: KsFormPage(
        title: _isEditing ? 'Fixed address' : 'Give a fixed address',
        subtitle: 'The router always gives this device the same address',
        action: 'Save',
        onAction: canSave ? _submit : null,
        children: [
          if (hasFixedMac)
            KsRow(title: 'Device', subtitle: _effectiveMac, chevron: false)
          else
            KsField(
              label: 'Device (MAC address)',
              controller: _macController,
              hint: 'AA:BB:CC:DD:EE:FF',
              keyboardType: TextInputType.visiblePassword,
              validator: (_) => _macError,
              help: _clipboardMac == null
                  ? null
                  : 'You copied $_clipboardMac. Tap the paste button.',
              suffix: IconButton(
                tooltip: 'Paste',
                icon: Icon(Icons.content_paste_rounded, color: ks.mu),
                onPressed: _pasteMacFromClipboard,
              ),
            ),
          KsField(
            label: 'Name',
            controller: _nameController,
            hint: suggestedHostname,
            keyboardType: TextInputType.url,
            validator: (_) => _nameError,
            help: 'Letters, numbers and dashes',
          ),
          KsField(
            label: 'Address',
            controller: _ipController,
            hint: suggestedIp,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (_) => _ipError,
            help: currentSubnet != null
                ? (currentSubnet.interfaceName == 'lan'
                      ? 'On your home network'
                      : 'On the ${currentSubnet.interfaceName} network')
                : null,
          ),
          if (suggestedIp.isNotEmpty && currentIp != suggestedIp)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _ipTouched = true;
                    _ipController.text = suggestedIp;
                  });
                  _validateInputs();
                },
                child: Text('Use $suggestedIp, it\'s free'),
              ),
            ),
          KsChoice<String>(
            label: 'Keep it for',
            value: _selectedLeasePreset,
            options: const [
              ('12h', '12 hours'),
              ('24h', 'A day'),
              ('7d', 'A week'),
              ('infinite', 'Always'),
              ('custom', 'Something else'),
            ],
            onChanged: (v) {
              setState(() => _selectedLeasePreset = v);
              _validateInputs();
            },
          ),
          if (_selectedLeasePreset == 'custom')
            KsField(
              label: 'How long',
              controller: _customLeaseController,
              hint: '2h, 30m or 3d',
              validator: (_) => _leaseTimeError,
              suffix: IconButton(
                tooltip: 'Pick a date and time',
                icon: Icon(Icons.calendar_month_rounded, color: ks.mu),
                onPressed: _pickLeaseExpiryDateTime,
              ),
            ),
          const SizedBox(height: 16),
          KsSwitchRow(
            title: 'Fix its IPv6 address too',
            subtitle: 'Only if the device uses IPv6 at home',
            value: _showIp6Section,
            onChanged: setIp6,
          ),
          if (_showIp6Section) ...[
            KsField(
              label: 'IPv6 address or host ID',
              controller: _ip6Controller,
              hint: '::100',
              validator: (_) => _ip6Error,
            ),
            KsField(
              label: 'DUID',
              controller: _duidController,
              hint: '0001000129A1B2C3D4E5F67890AB',
              validator: (_) => _duidError,
              help: 'The device\'s DHCPv6 ID. Leave it empty if unsure.',
            ),
          ],
          if (_isEditing) ...[
            const SizedBox(height: 24),
            KsRow(
              title: 'Remove the fixed address',
              danger: true,
              chevron: false,
              onTap: _deleteLease,
            ),
          ],
        ],
      ),
    );
  }
}
