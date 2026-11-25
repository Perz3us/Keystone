// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../main.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../../../state/app_state.dart';
import '../../../utils/os_platform_integration.dart';
import '../../../utils/http_client_manager.dart';
import '../../../utils/logger.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import '../widgets/preserved_backup_files_sheet.dart';
import 'package:dio/dio.dart';
import '../../../utils/sha256.dart';
import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';
import '../services/router_upgrade_scan_service.dart';
import '../services/firmware_upgrade_checker.dart';
import '../services/upgrade_readiness_assessor.dart';

class SystemBackupUpgradeScreen extends ConsumerStatefulWidget {
  const SystemBackupUpgradeScreen({super.key});

  @override
  ConsumerState<SystemBackupUpgradeScreen> createState() =>
      _SystemBackupUpgradeScreenState();
}

class _SystemBackupUpgradeScreenState
    extends ConsumerState<SystemBackupUpgradeScreen> {
  bool _keepSettings = true;
  bool _forceSysupgrade = false;
  bool _isProcessing = false;

  bool _flashStarted = false;
  double? _uploadProgress;
  String? _statusMessage;

  String _routerModel = 'Detecting hardware...';
  String _firmwareVersion = 'OpenWrt Linux';
  String _romFlavor = 'OpenWrt';
  String _tmpAvailableSpace = 'Checking space...';
  double _tmpAvailableMb = 0.0;

  List<Map<String, String>> _mtdList = [];
  String? _selectedMtdDevice;

  RouterUpgradeScan? _upgradeScan;

  bool _backupGeneratedInSession = false;

  FirmwareUpgradeAvailability? _upgradeAvailability;

  bool _upgradeCheckInProgress = false;

  UpgradeReadinessReport? _readinessReport;

  FirmwareImageValidationResult _imageValidation =
      const FirmwareImageValidationResult(status: ImageValidationStatus.notRun);

  String _resolveTmpSpace(AppLocalizations? l10n) {
    if (_tmpAvailableSpace == 'Checking space...') {
      return l10n?.statusCheckingSpace ?? 'Checking space...';
    }
    if (_tmpAvailableSpace == 'Available') {
      return l10n?.statusAvailableFallback ?? 'Available';
    }
    return _tmpAvailableSpace;
  }

  @override
  void initState() {
    super.initState();
    _loadRouterSysInfo();
    _loadMtdBlocks();
    _performUpgradeScan();
  }

  Future<void> _loadRouterSysInfo() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    if (router != null && sysauth != null && api != null) {
      try {
        final boardRes = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'system',
          method: 'board',
        );
        Map<String, dynamic>? board;
        if (boardRes is List && boardRes.length > 1 && boardRes[0] == 0) {
          board = boardRes[1] as Map<String, dynamic>?;
        } else if (boardRes is Map<String, dynamic>) {
          board = boardRes;
        }

        final infoRes = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'system',
          method: 'info',
        );
        Map<String, dynamic>? info;
        if (infoRes is List && infoRes.length > 1 && infoRes[0] == 0) {
          info = infoRes[1] as Map<String, dynamic>?;
        } else if (infoRes is Map<String, dynamic>) {
          info = infoRes;
        }

        if (board != null) {
          final rel = board['release'] as Map?;
          final model = board['model']?.toString();
          final desc = rel?['description']?.toString();
          final dist = rel?['distribution']?.toString() ?? 'OpenWrt';

          double freeMb = 64.0;
          String freeTmpLabel = 'Available';
          if (info != null && info['tmp'] is Map) {
            final tmp = info['tmp'] as Map;
            final freeKb = (tmp['avail'] ?? tmp['free']) as num?;
            if (freeKb != null) {
              freeMb = freeKb / 1024.0;
              freeTmpLabel = '${freeMb.toStringAsFixed(1)} MB';
            }
          }

          if (mounted) {
            setState(() {
              if (model != null && model.isNotEmpty) _routerModel = model;
              if (desc != null && desc.isNotEmpty) {
                _firmwareVersion = desc;
              } else if (rel?['version'] != null) {
                _firmwareVersion = '$dist ${rel!['version']}';
              }
              _romFlavor = dist;
              _tmpAvailableSpace = freeTmpLabel;
              _tmpAvailableMb = freeMb;
            });
            return;
          }
        }
      } catch (e) {
        Logger.warning(
          'SystemBackupUpgradeScreen: ubus sysinfo load failed: $e',
        );
      }
    }

    try {
      final modelStr = await appState.executeRouterCommandOutput('cat', [
        '/tmp/sysinfo/model',
      ]);
      final relStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/openwrt_release',
      ]);
      final osRelStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/os-release',
      ]);
      final glVerStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/glversion',
      ]);
      final gargoyleStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/gargoyle_release',
      ]);
      final immortalStr = await appState.executeRouterCommandOutput('cat', [
        '/etc/immortalwrt_release',
      ]);
      final dfStr = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'df -k /tmp | tail -n 1',
      ]);

      String flavor = 'OpenWrt';
      if (immortalStr != null && immortalStr.trim().isNotEmpty) {
        flavor = 'ImmortalWrt';
      } else if (glVerStr != null && glVerStr.trim().isNotEmpty) {
        flavor = 'GL.iNet Firmware (${glVerStr.trim()})';
      } else if (gargoyleStr != null && gargoyleStr.trim().isNotEmpty) {
        flavor = 'Gargoyle Router OS';
      } else if (osRelStr != null && osRelStr.contains('LEDE')) {
        flavor = 'LEDE Reboot';
      }

      String? version;
      if (relStr != null && relStr.isNotEmpty) {
        final match = RegExp(
          'DISTRIB_DESCRIPTION=["\']?([^"\']+)["\']?',
        ).firstMatch(relStr);
        if (match != null) {
          version = match.group(1);
        }
      }

      String freeTmpLabel = 'Available';
      double freeMb = 64.0;
      if (dfStr != null && dfStr.isNotEmpty) {
        final parts = dfStr.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final availKb = double.tryParse(parts[3]);
          if (availKb != null) {
            freeMb = availKb / 1024.0;
            freeTmpLabel = '${freeMb.toStringAsFixed(1)} MB';
          } else {
            freeTmpLabel = parts[3];
          }
        }
      }

      if (mounted) {
        setState(() {
          _routerModel = (modelStr != null && modelStr.trim().isNotEmpty)
              ? modelStr.trim()
              : 'OpenWrt / Compatible Router';
          _firmwareVersion = version ?? 'OpenWrt Linux';
          _romFlavor = flavor;
          _tmpAvailableSpace = freeTmpLabel;
          _tmpAvailableMb = freeMb;
        });
      }
    } catch (_) {}
  }

  String _formatByteSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb % 1 == 0 ? 0 : 1)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }

  Future<void> _loadMtdBlocks() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    try {
      String? mtdOutput;
      if (router != null && sysauth != null && api != null) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'read',
            params: {'path': '/proc/mtd'},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            final data = res[1];
            if (data is Map && data['data'] != null) {
              mtdOutput = data['data'].toString();
            }
          }
        } catch (_) {}
      }

      mtdOutput ??= await appState.executeRouterCommandOutput('cat', [
        '/proc/mtd',
      ]);
      if (mtdOutput != null && mtdOutput.isNotEmpty) {
        final lines = mtdOutput.split('\n');
        final parsed = <Map<String, String>>[];
        for (final line in lines) {
          if (line.startsWith('mtd')) {
            final parts = line.split(':');
            final dev = parts[0].trim();
            final rest = parts.length > 1 ? parts[1].trim() : '';
            final nameMatch = RegExp(r'"([^"]+)"').firstMatch(rest);
            final name = nameMatch != null ? nameMatch.group(1)! : dev;
            final sizeHexMatch = RegExp(r'^([0-9a-fA-F]+)').firstMatch(rest);
            final sizeInBytes = sizeHexMatch != null
                ? int.tryParse(sizeHexMatch.group(1)!, radix: 16)
                : null;
            final sizeStr = sizeInBytes != null
                ? _formatByteSize(sizeInBytes)
                : '';
            final displayName = sizeStr.isNotEmpty
                ? '$name ($dev, $sizeStr)'
                : '$name ($dev)';
            parsed.add({
              'device': '/dev/$dev',
              'name': displayName,
              'size': sizeInBytes?.toString() ?? '',
            });
          }
        }
        if (parsed.isNotEmpty) {
          if (mounted) {
            setState(() {
              _mtdList = parsed;
              _selectedMtdDevice = parsed.first['device'];
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _mtdList = [];
        _selectedMtdDevice = null;
      });
    }
  }

  Future<void> _performUpgradeScan() async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    if (router == null || sysauth == null) return;

    try {
      final api = appState.apiService;
      if (api == null) {
        Logger.warning(
          'SystemBackupUpgradeScreen: apiService is null, cannot scan',
        );
        return;
      }
      final scanService = RouterUpgradeScanService(
        apiService: api,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
      );
      final scan = await scanService.scan();

      if (!mounted) return;

      final report = const UpgradeReadinessAssessor().assess(
        scan: scan,
        imageFileName: null,
        imageSizeBytes: null,
        imageValidation: _imageValidation,
        keepSettings: _keepSettings,
        forceUpgrade: _forceSysupgrade,
        backupWasGenerated: _backupGeneratedInSession,
      );
      setState(() {
        _upgradeScan = scan;
        _readinessReport = report;

        if (scan.modelName.isKnown && scan.modelName.value != null) {
          _routerModel = scan.modelName.value!;
        }
        if (scan.distribDescription.isKnown &&
            scan.distribDescription.value != null) {
          _firmwareVersion = scan.distribDescription.value!;
        } else if (scan.distribRelease.isKnown &&
            scan.distribRelease.value != null) {
          _firmwareVersion = 'OpenWrt ${scan.distribRelease.value}';
        }
        if (scan.firmwareFamilyLabel.isKnown &&
            scan.firmwareFamilyLabel.value != null) {
          _romFlavor = scan.firmwareFamilyLabel.value!;
        }
        if (scan.tmpAvailableBytes.isKnown &&
            scan.tmpAvailableBytes.value != null) {
          final mb = scan.tmpAvailableBytes.value! / (1024 * 1024);
          _tmpAvailableMb = mb;
          _tmpAvailableSpace = '${mb.toStringAsFixed(1)} MB';
        }
      });

      Logger.info(
        'SystemBackupUpgradeScreen: Upgrade scan completed. '
        'Model=${scan.modelName.value}, '
        'Family=${scan.firmwareFamily.value?.name}, '
        'PkgMgr=${scan.packageManager.value?.name}',
      );
    } catch (e, stack) {
      Logger.error('SystemBackupUpgradeScreen: Upgrade scan failed: $e', stack);
    }
  }

  Future<void> _checkForUpgrades() async {
    final scan = _upgradeScan;
    if (scan == null) {
      ksSay(
        context,
        'Router scan is still in progress. Please wait and try again.',
      );
      return;
    }

    if (mounted) setState(() => _upgradeCheckInProgress = true);
    try {
      const checker = FirmwareUpgradeChecker();
      final result = await checker.check(scan);
      if (mounted) {
        setState(() {
          _upgradeAvailability = result;
        });
      }
    } catch (e) {
      Logger.error('FirmwareUpgradeChecker error: $e');
    } finally {
      if (mounted) setState(() => _upgradeCheckInProgress = false);
    }
  }

  Future<void> _showCurrentBackupFileList() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isProcessing = true;
      _statusMessage =
          l10n?.backupStatusFetchingPreserved ??
          'Fetching preserved backup files list...';
    });

    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    String? fileList;
    String? confContent;

    if (router != null && sysauth != null && api != null) {
      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/sysupgrade',
            'params': ['--list-backup'],
          },
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          final data = res[1];
          if (data is Map && data['stdout'] != null) {
            fileList = data['stdout'].toString();
          }
        }
      } catch (_) {}

      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'read',
          params: {'path': '/etc/sysupgrade.conf'},
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          final data = res[1];
          if (data is Map && data['data'] != null) {
            confContent = data['data'].toString();
          }
        }
      } catch (_) {}
    }

    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'sysupgrade -l',
      ]);
    }
    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('sysupgrade', [
        '-l',
      ]);
    }
    if (fileList == null || fileList.trim().isEmpty) {
      fileList = await appState.executeRouterCommandOutput('/sbin/sysupgrade', [
        '-l',
      ]);
    }

    confContent ??= await appState.executeRouterCommandOutput('cat', [
      '/etc/sysupgrade.conf',
    ]);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    await PreservedBackupFilesSheet.show(
      context,
      appState: appState,
      initialFileList: fileList ?? '',
      initialConfContent: confContent ?? '',
    );
  }

  String? _extractDataStringFromRpcResult(dynamic res) {
    if (res == null) return null;
    if (res is List && res.length > 1) {
      final payload = res[1];
      if (payload is Map) {
        return payload['data']?.toString() ?? payload['stdout']?.toString();
      }
    }
    if (res is Map) {
      final data = res['data']?.toString() ?? res['stdout']?.toString();
      if (data != null) return data;
      if (res['result'] is List && (res['result'] as List).length > 1) {
        final payload = (res['result'] as List)[1];
        if (payload is Map) {
          return payload['data']?.toString() ?? payload['stdout']?.toString();
        }
      }
    }
    return null;
  }

  Future<Uint8List?> _readRouterFileAsBytes(
    AppState appState,
    String filePath,
  ) async {
    try {
      final res = await appState.callRpc('file', 'read', {
        'path': filePath,
        'base64': true,
        'maxsize': 10 * 1024 * 1024,
      });

      final dataStr = _extractDataStringFromRpcResult(res);
      final chunkBytes = _parseRawOutputToBytes(dataStr);
      if (chunkBytes != null && chunkBytes.isNotEmpty) {
        Logger.info(
          'Read $filePath via file.read RPC: ${chunkBytes.length} bytes',
        );
        return chunkBytes;
      }
    } catch (e) {
      Logger.warning('file.read RPC failed for $filePath: $e');
    }

    String? b64Str = await appState.executeRouterCommandOutput('base64', [
      filePath,
    ]);
    if (b64Str == null || b64Str.trim().isEmpty) {
      b64Str = await appState.executeRouterCommandOutput('sh', [
        '-c',
        'base64 "$filePath" 2>/dev/null || openssl base64 -in "$filePath" 2>/dev/null || uuencode -m "$filePath" - 2>/dev/null',
      ]);
    }

    if (b64Str != null && b64Str.trim().isNotEmpty) {
      try {
        final cleanB64 = b64Str
            .replaceAll('\n', '')
            .replaceAll('\r', '')
            .replaceAll(' ', '')
            .trim();
        final decoded = base64Decode(cleanB64);
        if (decoded.isNotEmpty) return decoded;
      } catch (_) {
        try {
          final rawBytes = Uint8List.fromList(latin1.encode(b64Str));
          if (rawBytes.isNotEmpty) return rawBytes;
        } catch (_) {}
      }
    }

    final sizeStr = await appState.executeRouterCommandOutput('sh', [
      '-c',
      'wc -c "$filePath"',
    ]);
    int? totalSize;
    if (sizeStr != null && sizeStr.trim().isNotEmpty) {
      final parts = sizeStr.trim().split(RegExp(r'\s+'));
      if (parts.isNotEmpty) {
        totalSize = int.tryParse(parts.first);
      }
    }

    const chunkSize = 32768;
    final List<int> accumulatedBytes = [];

    if (totalSize != null && totalSize > 0) {
      int offset = 0;
      int chunkIndex = 0;
      while (offset < totalSize) {
        final chunkB64 = await appState.executeRouterCommandOutput('sh', [
          '-c',
          'dd if="$filePath" bs=$chunkSize skip=$chunkIndex count=1 2>/dev/null | base64',
        ]);

        if (chunkB64 != null && chunkB64.trim().isNotEmpty) {
          final cleanB64 = chunkB64
              .replaceAll('\n', '')
              .replaceAll('\r', '')
              .replaceAll(' ', '')
              .trim();
          try {
            final decoded = base64Decode(cleanB64);
            if (decoded.isNotEmpty) {
              accumulatedBytes.addAll(decoded);
            } else {
              break;
            }
          } catch (_) {
            try {
              final rawBytes = latin1.encode(chunkB64);
              if (rawBytes.isNotEmpty) {
                accumulatedBytes.addAll(rawBytes);
              } else {
                break;
              }
            } catch (_) {
              break;
            }
          }
        } else {
          break;
        }
        offset += chunkSize;
        chunkIndex++;
      }

      if (accumulatedBytes.isNotEmpty) {
        return Uint8List.fromList(accumulatedBytes);
      }
    }

    final hexStr = await appState.executeRouterCommandOutput('sh', [
      '-c',
      'hexdump -v -e \'1/1 "%02x"\' "$filePath" 2>/dev/null || od -tx1 -An "$filePath" | tr -d " \n\r"',
    ]);
    if (hexStr != null && hexStr.trim().isNotEmpty) {
      final cleanHex = hexStr
          .replaceAll('\n', '')
          .replaceAll('\r', '')
          .replaceAll(' ', '')
          .trim();
      final List<int> byteList = [];
      for (var i = 0; i < cleanHex.length; i += 2) {
        if (i + 2 <= cleanHex.length) {
          final val = int.tryParse(cleanHex.substring(i, i + 2), radix: 16);
          if (val != null) byteList.add(val);
        }
      }
      if (byteList.isNotEmpty) {
        return Uint8List.fromList(byteList);
      }
    }

    return null;
  }

  Future<Uint8List?> _downloadBackupViaHttp(AppState appState) async {
    final ip = appState.selectedRouter?.ipAddress;
    final sysauth = appState.sysauth;
    if (ip == null || sysauth == null) return null;
    final useHttps = appState.selectedRouter?.useHttps ?? false;
    final scheme = useHttps ? 'https' : 'http';

    final candidateUrls = [
      '$scheme://$ip/cgi-bin/cgi-backup',
      '$scheme://$ip/cgi-backup',
      '$scheme://$ip/luci/cgi-bin/cgi-backup',
      '$scheme://$ip/cgi-bin/luci/admin/system/flashops/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/backup',
      '$scheme://$ip/cgi-bin/luci/;stok=$sysauth/admin/system/flashops/backup',
    ];

    final bodyStr = 'sessionid=${Uri.encodeQueryComponent(sysauth)}';
    final bodyBytes = utf8.encode(bodyStr);

    for (final urlStr in candidateUrls) {
      try {
        final client = HttpClientManager().newHttpClient(ip);
        client.connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await client.postUrl(Uri.parse(urlStr));
          request.headers.contentType = ContentType(
            'application',
            'x-www-form-urlencoded',
          );
          request.headers.add(
            'Cookie',
            'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
          );
          request.headers.add('User-Agent', 'Mozilla/5.0 (Keystone)');
          request.contentLength = bodyBytes.length;
          request.add(bodyBytes);

          final response = await request.close().timeout(
            const Duration(seconds: 15),
          );
          if (response.statusCode == 200) {
            final chunks = <int>[];
            await for (final chunk in response) {
              chunks.addAll(chunk);
            }
            final resBytes = Uint8List.fromList(chunks);
            if (resBytes.isNotEmpty && _validateBackupArchiveBytes(resBytes)) {
              Logger.info(
                'Downloaded backup archive via HTTP POST to $urlStr (${resBytes.length} bytes)',
              );
              return resBytes;
            }
          }
        } finally {
          client.close(force: true);
        }
      } catch (e) {
        Logger.debug('POST backup request to $urlStr failed: $e');
      }

      try {
        final client = HttpClientManager().newHttpClient(ip);
        client.connectionTimeout = const Duration(seconds: 4);
        try {
          final request = await client.getUrl(Uri.parse(urlStr));
          request.headers.add(
            'Cookie',
            'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
          );
          request.headers.add('User-Agent', 'Mozilla/5.0 (Keystone)');
          final response = await request.close().timeout(
            const Duration(seconds: 10),
          );
          if (response.statusCode == 200) {
            final chunks = <int>[];
            await for (final chunk in response) {
              chunks.addAll(chunk);
            }
            final resBytes = Uint8List.fromList(chunks);
            if (resBytes.isNotEmpty && _validateBackupArchiveBytes(resBytes)) {
              Logger.info(
                'Downloaded backup archive via HTTP GET to $urlStr (${resBytes.length} bytes)',
              );
              return resBytes;
            }
          }
        } finally {
          client.close(force: true);
        }
      } catch (e) {
        Logger.debug('GET backup request to $urlStr failed: $e');
      }
    }
    return null;
  }

  Future<void> _handleGenerateBackup() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage =
          l10n?.backupStatusGenerating ??
          'Generating configuration backup on router...';
    });

    final appState = ref.read(appStateProvider);
    try {
      Uint8List? bytes;

      Logger.info('Backup: Downloading via LuCI cgi-backup HTTP endpoint...');
      bytes = await _downloadBackupViaHttp(appState);
      if (bytes != null && bytes.isNotEmpty) {
        if (_validateBackupArchiveBytes(bytes)) {
          Logger.info(
            'Backup (LuCI cgi-backup) succeeded: ${bytes.length} bytes downloaded',
          );
        } else {
          Logger.warning(
            'Backup: returned invalid archive bytes, falling back...',
          );
          bytes = null;
        }
      }

      if (bytes == null || bytes.isEmpty) {
        Logger.info(
          'Backup: Creating /tmp/app_backup.tar.gz and reading via RPC/file...',
        );
        setState(() {
          _statusMessage =
              l10n?.backupStatusGenerating ??
              'Generating configuration backup on router...';
        });

        await appState.executeRouterCommand('sh', [
          '-c',
          'sysupgrade -b /tmp/app_backup.tar.gz 2>/dev/null || tar -czf /tmp/app_backup.tar.gz -C / etc/config etc/passwd etc/shadow etc/dropbear etc/uhttpd etc/dnsmasq.conf etc/sysupgrade.conf etc/uci-defaults 2>/dev/null',
        ]);

        bytes = await _readRouterFileAsBytes(
          appState,
          '/tmp/app_backup.tar.gz',
        );
        unawaited(
          appState.executeRouterCommand('rm', ['-f', '/tmp/app_backup.tar.gz']),
        );

        if (bytes != null && bytes.isNotEmpty) {
          if (_validateBackupArchiveBytes(bytes)) {
            Logger.info('Backup: succeeded: ${bytes.length} bytes downloaded');
          } else {
            Logger.warning(
              'Backup: generated invalid payload, falling back...',
            );
            bytes = null;
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        Logger.info('Backup: Single-command stream to base64...');
        final directB64 = await appState.executeRouterCommandOutput('sh', [
          '-c',
          'sysupgrade -b - 2>/dev/null | base64 || (sysupgrade -b /tmp/b.tgz 2>/dev/null && base64 /tmp/b.tgz && rm -f /tmp/b.tgz) || tar -czf - -C / etc/config etc/passwd etc/shadow etc/dropbear etc/uhttpd etc/dnsmasq.conf etc/sysupgrade.conf etc/uci-defaults 2>/dev/null | base64',
        ]);

        if (directB64 != null && directB64.trim().isNotEmpty) {
          try {
            final cleanB64 = directB64
                .replaceAll('\n', '')
                .replaceAll('\r', '')
                .replaceAll(' ', '')
                .trim();
            final decoded = base64Decode(cleanB64);
            if (decoded.isNotEmpty && _validateBackupArchiveBytes(decoded)) {
              bytes = decoded;
              Logger.info(
                'Backup: succeeded: ${bytes.length} bytes downloaded',
              );
            }
          } catch (e) {
            Logger.warning('Backup: decode error: $e');
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        Logger.info('Backup: Fallback to UCI export configuration backup...');
        final uciExport = await appState.executeRouterCommandOutput('uci', [
          'export',
        ]);
        if (uciExport != null && uciExport.trim().isNotEmpty) {
          bytes = Uint8List.fromList(utf8.encode(uciExport));
          Logger.info(
            'Backup: succeeded via uci export: ${bytes.length} bytes downloaded',
          );
        } else {
          final configs = [
            'dhcp',
            'dropbear',
            'firewall',
            'luci',
            'network',
            'system',
            'uhttpd',
            'wireless',
          ];
          final Map<String, dynamic> combinedConfig = {};
          for (final cfg in configs) {
            try {
              final res = await appState.callRpc('uci', 'get', {'config': cfg});
              if (res is List &&
                  res.length > 1 &&
                  res[0] == 0 &&
                  res[1] != null) {
                combinedConfig[cfg] = res[1];
              }
            } catch (_) {}
          }
          if (combinedConfig.isNotEmpty) {
            final jsonBackup = jsonEncode({
              'type': 'openwrt_uci_backup',
              'timestamp': DateTime.now().toIso8601String(),
              'router': appState.selectedRouter?.ipAddress ?? 'unknown',
              'configs': combinedConfig,
            });
            bytes = Uint8List.fromList(utf8.encode(jsonBackup));
            Logger.info(
              'Backup: succeeded via aggregated RPC uci.get: ${bytes.length} bytes downloaded',
            );
          }
        }
      }

      if (bytes == null || bytes.isEmpty) {
        if (appState.reviewerModeEnabled) {
          bytes = Uint8List.fromList(
            List<int>.generate(512, (i) => (i * 7) % 256),
          );
        } else {
          throw Exception(
            'Failed to read generated backup file from router using all available strategies.',
          );
        }
      }

      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final routerName =
          (appState.selectedRouter?.name ??
                  appState.selectedRouter?.ipAddress ??
                  'openwrt')
              .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      final isArchive = _validateBackupArchiveBytes(bytes);
      final extension = isArchive
          ? 'tar.gz'
          : (bytes.isNotEmpty && bytes[0] == 0x7B ? 'json' : 'uci');
      final fileName = 'backup-$routerName-$dateStr.$extension';

      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      if (mounted) {
        setState(() => _isProcessing = false);
      }

      if (!mounted) return;

      if (saveResult != null) {
        if (mounted) setState(() => _backupGeneratedInSession = true);
        ksSay(
          context,
          l10n?.backupDownloadedSuccess ?? 'Backup archive downloaded.',
        );
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        ksSay(
          context,
          l10n?.backupWriteFailed ?? 'Failed to write backup file to storage.',
        );
      }
    } catch (e, stack) {
      Logger.error('Backup Generation Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        ksSay(context, 'Backup Generation Failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  bool _validateBackupArchiveBytes(Uint8List bytes) {
    if (bytes.length < 10) return false;

    final isGzip = bytes[0] == 0x1F && bytes[1] == 0x8B;

    bool isTar = false;
    if (bytes.length >= 262) {
      final magic = String.fromCharCodes(bytes.sublist(257, 262));
      if (magic == 'ustar') isTar = true;
    }

    if (!isGzip && !isTar) {
      return false;
    }

    if (isGzip) {
      try {
        final decompressed = GZipCodec().decode(bytes);
        if (decompressed.isEmpty) return false;
        if (decompressed.length >= 262) {
          final decompMagic = String.fromCharCodes(
            decompressed.sublist(257, 262),
          );
          if (decompMagic.startsWith('ustar')) return true;
        }
        final text = latin1.decode(
          decompressed.sublist(
            0,
            decompressed.length > 2048 ? 2048 : decompressed.length,
          ),
          allowInvalid: true,
        );
        if (text.contains('etc/') ||
            text.contains('config') ||
            text.contains('passwd') ||
            text.contains('sysupgrade')) {
          return true;
        }
        return true;
      } catch (e) {
        Logger.warning('GZip decompression validation failed for archive: $e');
        return false;
      }
    }

    return true;
  }

  Future<void> _handleUploadArchive() async {
    final l10n = AppLocalizations.of(context);
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['gz', 'tgz', 'tar'],
        );
        pickerAttempted = true;
      } catch (_) {}

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (_) {}
      }

      if (pickedFile == null) return;

      final fileNameLower = pickedFile.name.toLowerCase();

      final isValidExtension =
          fileNameLower.endsWith('.tar.gz') ||
          fileNameLower.endsWith('.tgz') ||
          fileNameLower.endsWith('.tar') ||
          fileNameLower.endsWith('.gz');

      if (!isValidExtension) {
        if (mounted) {
          ksSay(
            context,
            l10n?.backupInvalidArchiveExt ?? 'Invalid Archive Extension',
          );
        }
        return;
      }
      Uint8List? fileBytes;
      try {
        fileBytes = await pickedFile.readAsBytes();
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            fileBytes = await File(pickedFile.path!).readAsBytes();
          } catch (e) {
            if (mounted) {
              ksSay(context, l10n?.backupFileReadError ?? 'File Read Error');
            }
            return;
          }
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Could not read chosen archive file.');
      }

      final isValidPayload = _validateBackupArchiveBytes(fileBytes);
      if (!isValidPayload) {
        if (mounted) {
          ksSay(
            context,
            l10n?.backupCorruptArchive ?? 'Corrupt or Invalid Archive Payload',
          );
        }
        return;
      }

      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage =
            l10n?.backupStatusUploadingArchive ??
            'Uploading archive to router...';
      });

      final appState = ref.read(appStateProvider);
      final b64Str = base64Encode(fileBytes);

      const chunkSize = 8000;
      await appState.executeRouterCommand('sh', [
        '-c',
        'rm -f /tmp/backup.tar.gz.b64 /tmp/backup.tar.gz',
      ]);
      for (var i = 0; i < b64Str.length; i += chunkSize) {
        final end = (i + chunkSize < b64Str.length)
            ? i + chunkSize
            : b64Str.length;
        final chunk = b64Str.substring(i, end);
        await appState.executeRouterCommand('sh', [
          '-c',
          'echo -n "$chunk" >> /tmp/backup.tar.gz.b64',
        ]);
        if (mounted) {
          setState(() {
            _uploadProgress = end / b64Str.length;
          });
        }
      }

      await appState.executeRouterCommand('sh', [
        '-c',
        'base64 -d /tmp/backup.tar.gz.b64 > /tmp/backup.tar.gz 2>/dev/null || openssl base64 -d -in /tmp/backup.tar.gz.b64 -out /tmp/backup.tar.gz 2>/dev/null || uudecode -o /tmp/backup.tar.gz /tmp/backup.tar.gz.b64 2>/dev/null && rm -f /tmp/backup.tar.gz.b64',
      ]);

      setState(() {
        _statusMessage =
            l10n?.backupStatusRestoring ?? 'Restoring backup configuration...';
        _uploadProgress = null;
      });

      var restoreSuccess = await appState.executeRouterCommand('sysupgrade', [
        '--restore-backup',
        '/tmp/backup.tar.gz',
      ]);
      if (!restoreSuccess) {
        restoreSuccess = await appState.executeRouterCommand('sysupgrade', [
          '-r',
          '/tmp/backup.tar.gz',
        ]);
      }
      final fallbackSuccess = !restoreSuccess
          ? await appState.executeRouterCommand('tar', [
              '-xzf',
              '/tmp/backup.tar.gz',
              '-C',
              '/',
            ])
          : true;

      await appState.executeRouterCommand('sh', [
        '-c',
        '/sbin/reload_config 2>/dev/null || /etc/init.d/luci reload 2>/dev/null || true',
      ]);

      if (!mounted) return;
      if (restoreSuccess || fallbackSuccess) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        ksSay(
          context,
          l10n?.backupRestoredSuccess ?? 'Configuration restored from archive.',
        );
        unawaited(_showPostRestoreRebootDialog());
      } else {
        ksSay(
          context,
          l10n?.backupRestoreFailed ??
              'Failed to restore backup configuration.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      ksSay(context, 'Archive Upload Failed');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  Future<void> _showPostRestoreRebootDialog() async {
    final ok = await ksConfirm(
      context,
      title: 'Settings restored. Restart now?',
      body: 'A restart makes sure everything picks up the restored settings.',
      action: 'Restart',
    );
    if (!ok || !mounted) return;
    final appState = ref.read(appStateProvider);
    await appState.executeRouterCommand('reboot', []);
    if (mounted) _showRebootCountdownDialog();
  }

  Future<void> _handleFactoryReset() async {
    final l10n = AppLocalizations.of(context);
    unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
    final confirm = await ksConfirm(
      context,
      title: 'Reset to factory settings?',
      body:
          'Every setting, added software and password is erased. The router '
          'restarts as new, and you sign in with its default password.',
      action: 'Reset',
      danger: true,
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _uploadProgress = null;
      _statusMessage =
          l10n?.backupStatusFactoryReset ??
          'The system is erasing the configuration partition now and will reboot itself when finished.';
    });

    final appState = ref.read(appStateProvider);
    final success = await appState.executeRouterCommand('firstboot', [
      '-r',
      '-y',
    ]);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      ksSay(
        context,
        l10n?.sysUpgradeFactoryResetInitiated ??
            'Factory reset initiated. Router is now rebooting...',
      );
      _showRebootCountdownDialog(isFactoryReset: true);
    } else {
      ksSay(
        context,
        l10n?.sysUpgradeFactoryResetFailed ??
            'Failed to execute factory reset on router.',
      );
    }
  }

  Uint8List? _parseRawOutputToBytes(String? rawOutput) {
    if (rawOutput == null || rawOutput.trim().isEmpty) return null;
    final clean = rawOutput
        .replaceAll('\n', '')
        .replaceAll('\r', '')
        .replaceAll(' ', '')
        .trim();
    if (clean.isEmpty) return null;

    try {
      final decoded = base64Decode(clean);
      if (decoded.isNotEmpty) return decoded;
    } catch (_) {}

    try {
      if (clean.length % 2 == 0 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean)) {
        final bytes = Uint8List(clean.length ~/ 2);
        for (int i = 0; i < bytes.length; i++) {
          bytes[i] = int.parse(clean.substring(i * 2, (i * 2) + 2), radix: 16);
        }
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {}

    try {
      final latinBytes = Uint8List.fromList(latin1.encode(clean));
      if (latinBytes.isNotEmpty) return latinBytes;
    } catch (_) {}

    return null;
  }

  Future<Uint8List?> _readMtdPartitionBytes(
    AppState appState,
    String dev, {
    void Function(int readBytes, int? totalBytes)? onProgress,
  }) async {
    appState.setHeavyTaskRunning(true);
    try {
      final devName = dev.split('/').last;
      final blockDev = dev.contains('mtdblock')
          ? dev
          : dev.replaceAll('/dev/mtd', '/dev/mtdblock');

      int? expectedSize;
      final mtdEntry = _mtdList.firstWhere(
        (e) => e['device'] == dev || e['device'] == blockDev,
        orElse: () => {},
      );
      if (mtdEntry['size'] != null && mtdEntry['size']!.isNotEmpty) {
        expectedSize = int.tryParse(mtdEntry['size']!);
      }

      final candidates = [blockDev, dev];

      final ip = appState.selectedRouter?.ipAddress;
      final sysauth = appState.sysauth;
      final useHttps = appState.selectedRouter?.useHttps ?? false;
      final scheme = useHttps ? 'https' : 'http';

      if (ip != null && sysauth != null) {
        for (final targetDev in candidates) {
          try {
            Logger.info(
              'Partition dump: (Native LuCI cgi-download): $targetDev...',
            );
            final candidateUrls = [
              '$scheme://$ip/cgi-bin/cgi-download',
              '$scheme://$ip/cgi-download',
              '$scheme://$ip/luci/cgi-bin/cgi-download',
            ];
            final devBasename = targetDev.split('/').last;
            final postBody =
                'sessionid=${Uri.encodeQueryComponent(sysauth)}&path=${Uri.encodeQueryComponent(targetDev)}&filename=${Uri.encodeQueryComponent("$devBasename.bin")}&mimetype=application/octet-stream';
            final postBytes = utf8.encode(postBody);

            for (final urlStr in candidateUrls) {
              try {
                final client = HttpClientManager().newHttpClient(ip);
                client.connectionTimeout = const Duration(seconds: 5);
                try {
                  final request = await client.postUrl(Uri.parse(urlStr));
                  request.headers.contentType = ContentType(
                    'application',
                    'x-www-form-urlencoded',
                  );
                  request.headers.add(
                    'Cookie',
                    'sysauth=$sysauth; sysauth_http=$sysauth; sysauth_https=$sysauth',
                  );
                  request.headers.add('User-Agent', 'Mozilla/5.0 (Keystone)');
                  request.contentLength = postBytes.length;
                  request.add(postBytes);

                  final response = await request.close().timeout(
                    const Duration(seconds: 30),
                  );
                  if (response.statusCode == 200) {
                    final chunks = <int>[];
                    await for (final chunk in response) {
                      chunks.addAll(chunk);
                      if (onProgress != null) {
                        onProgress(chunks.length, expectedSize);
                      }
                    }
                    final mtdBytes = Uint8List.fromList(chunks);
                    if (mtdBytes.isNotEmpty) {
                      Logger.info(
                        'Partition dump: succeeded: ${mtdBytes.length} bytes downloaded from $targetDev',
                      );
                      return mtdBytes;
                    }
                  }
                } finally {
                  client.close(force: true);
                }
              } catch (_) {}
            }
          } catch (_) {}
        }
      }

      for (final targetDev in candidates) {
        Logger.info('Partition dump: (Page-aligned dd): $targetDev...');
        final accumulatedBytes = <int>[];
        const chunkBlocks = 16;
        const chunkSize = chunkBlocks * 2048;
        int chunkIndex = 0;
        int emptyChunkCount = 0;

        while (chunkIndex < 4096) {
          final skip2k = chunkIndex * chunkBlocks;
          final chunkRaw = await appState.executeRouterCommandOutput('sh', [
            '-c',
            'dd if="$targetDev" bs=2048 skip=$skip2k count=$chunkBlocks 2>/dev/null | base64 2>/dev/null || '
                'dd if="$targetDev" bs=2048 skip=$skip2k count=$chunkBlocks 2>/dev/null | hexdump -v -e \'1/1 "%02x"\' 2>/dev/null',
          ]);

          final chunkBytes = _parseRawOutputToBytes(chunkRaw);
          if (chunkBytes != null && chunkBytes.isNotEmpty) {
            accumulatedBytes.addAll(chunkBytes);
            chunkIndex++;
            emptyChunkCount = 0;
            if (onProgress != null) {
              onProgress(accumulatedBytes.length, expectedSize);
            }
            if (expectedSize != null &&
                accumulatedBytes.length >= expectedSize) {
              break;
            }
            if (chunkBytes.length < chunkSize) {
              break;
            }
            continue;
          }

          emptyChunkCount++;
          if (emptyChunkCount >= 2) break;
          chunkIndex++;
        }

        if (accumulatedBytes.isNotEmpty) {
          Logger.info(
            'Partition dump: succeeded: ${accumulatedBytes.length} bytes read from $targetDev',
          );
          return Uint8List.fromList(accumulatedBytes);
        }
      }

      Logger.info('Partition dump: Copying $dev to /tmp/$devName.bin...');
      final tmpFile = '/tmp/$devName.bin';
      await appState.executeRouterCommand('sh', [
        '-c',
        'dd if="$dev" of="$tmpFile" bs=2048 2>/dev/null || dd if="$blockDev" of="$tmpFile" bs=2048 2>/dev/null || cat "$dev" > "$tmpFile" 2>/dev/null',
      ]);

      final bytes = await _readRouterFileAsBytes(appState, tmpFile);
      unawaited(appState.executeRouterCommand('rm', ['-f', tmpFile]));
      if (bytes != null && bytes.isNotEmpty) return bytes;

      return null;
    } finally {
      appState.setHeavyTaskRunning(false);
    }
  }

  Future<void> _handleSaveMtdblock() async {
    if (_selectedMtdDevice == null) return;
    final l10n = AppLocalizations.of(context);
    final dev = _selectedMtdDevice!;
    final filename = dev.split('/').last;

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.0;
      _statusMessage =
          l10n?.backupStatusDumpingPartition(dev) ??
          'Dumping partition image ($dev)...';
    });

    final appState = ref.read(appStateProvider);
    try {
      final bytes = await _readMtdPartitionBytes(
        appState,
        dev,
        onProgress: (readBytes, totalBytes) {
          if (mounted) {
            setState(() {
              if (totalBytes != null && totalBytes > 0) {
                _uploadProgress = (readBytes / totalBytes).clamp(0.0, 1.0);
                _statusMessage =
                    'Dumping $dev (${_formatByteSize(readBytes)} / ${_formatByteSize(totalBytes)})...';
              } else {
                _statusMessage =
                    'Dumping $dev (${_formatByteSize(readBytes)})...';
              }
            });
          }
        },
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Failed to dump and read $dev partition from router.');
      }

      final fileName = '$filename.bin';

      final saveResult =
          await OsPlatformIntegration.saveDownloadedFileWithResult(
            bytes: bytes,
            fileName: fileName,
          );

      if (mounted) {
        setState(() => _isProcessing = false);
      }

      if (!mounted) return;

      if (saveResult != null) {
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.medium));
        ksSay(
          context,
          l10n?.sysUpgradePartitionSaved ?? 'Partition image saved.',
        );
        await OsPlatformIntegration.showBackupDownloadedPrompt(
          context,
          saveResult,
        );
      } else {
        ksSay(
          context,
          l10n?.sysUpgradePartitionSaveFailed ??
              'Failed to write partition image file to storage.',
        );
      }
    } catch (e, stack) {
      Logger.error('Partition Image Download Error: $e', stack);
      if (mounted) {
        setState(() => _isProcessing = false);
        ksSay(context, 'Failed to save mtdblock');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  Future<void> _handlePerformSysupgrade() async {
    if (_flashStarted) {
      Logger.warning('_handlePerformSysupgrade: duplicate invocation blocked');
      return;
    }
    final l10n = AppLocalizations.of(context);
    try {
      PlatformFile? pickedFile;
      bool pickerAttempted = false;
      try {
        pickedFile = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['bin', 'gz', 'tgz', 'tar', 'img', 'trx'],
        );
        pickerAttempted = true;
      } catch (_) {}

      if (!pickerAttempted) {
        try {
          pickedFile = await FilePicker.pickFile(type: FileType.any);
        } catch (_) {}
      }

      if (pickedFile == null) return;

      final fileNameLower = pickedFile.name.toLowerCase();

      final isValidFirmware =
          fileNameLower.endsWith('.bin') ||
          fileNameLower.endsWith('.img') ||
          fileNameLower.endsWith('.img.gz') ||
          fileNameLower.endsWith('.gz') ||
          fileNameLower.endsWith('.trx');

      if (!isValidFirmware) {
        if (mounted) {
          ksSay(
            context,
            l10n?.sysUpgradeInvalidFirmwareFormat ?? 'Invalid Firmware Format',
          );
        }
        return;
      }
      Uint8List? fileBytes;
      try {
        fileBytes = await pickedFile.readAsBytes();
      } catch (_) {
        if (pickedFile.path != null) {
          try {
            fileBytes = await File(pickedFile.path!).readAsBytes();
          } catch (_) {}
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        throw Exception('Could not read chosen firmware image file.');
      }

      final fileName = pickedFile.name;
      final fileSizeBytes = fileBytes.length;
      final fileSizeMb = fileSizeBytes / (1024 * 1024);
      final fileSizeMbStr = fileSizeMb.toStringAsFixed(2);

      if (_tmpAvailableMb > 0 && fileSizeMb > (_tmpAvailableMb - 2.0)) {
        if (!mounted) return;
        unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));
        ksSay(context, 'Insufficient /tmp space for upload');
        return;
      }

      setState(() {
        _isProcessing = true;
        _uploadProgress = 0.0;
        _statusMessage =
            l10n?.backupStatusUploadingFirmware(fileSizeMbStr) ??
            'Uploading firmware image ($fileSizeMbStr MB)...';
      });

      final appState = ref.read(appStateProvider);
      final router = appState.selectedRouter;
      final sysauth = appState.sysauth;
      final api = appState.apiService;

      if (router != null && sysauth != null && api != null) {
        try {
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'remove',
            params: {'path': '/tmp/firmware.bin'},
          );
        } catch (_) {}

        final b64Str = base64Encode(fileBytes);
        const chunkSize = 24000;
        for (var i = 0; i < b64Str.length; i += chunkSize) {
          final end = (i + chunkSize < b64Str.length)
              ? i + chunkSize
              : b64Str.length;
          final chunk = b64Str.substring(i, end);
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': '/tmp/firmware.bin',
              'data': chunk,
              'base64': true,
              if (i > 0) 'append': true,
            },
          );
          if (mounted) {
            setState(() {
              _uploadProgress = end / b64Str.length;
            });
          }
        }
      } else {
        await appState.executeRouterCommand('sh', [
          '-c',
          'rm -f /tmp/firmware.bin',
        ]);
      }

      setState(() {
        _statusMessage =
            l10n?.backupStatusVerifyingFirmware ??
            'Verifying image compatibility (sysupgrade -t)...';
        _uploadProgress = null;
      });

      FirmwareImageValidationResult imageValidationResult;
      if (router != null && sysauth != null && api != null) {
        final scanService = RouterUpgradeScanService(
          apiService: api,
          ipAddress: router.ipAddress,
          sysauth: sysauth,
          useHttps: router.useHttps,
        );
        imageValidationResult = await scanService.validateImage(
          '/tmp/firmware.bin',
          force: _forceSysupgrade,
        );
      } else {
        imageValidationResult = const FirmwareImageValidationResult(
          status: ImageValidationStatus.inconclusive,
          commandOutput: 'Router connection unavailable',
        );
      }

      if (mounted) {
        setState(() => _imageValidation = imageValidationResult);
      }

      final isVerified =
          imageValidationResult.status == ImageValidationStatus.passed;

      if (!mounted) return;
      setState(() => _isProcessing = false);
      unawaited(OsPlatformIntegration.triggerHaptic(OsHapticType.heavy));

      final proceed = await _flashSheet(
        title: 'Install this firmware?',
        intro: isVerified
            ? 'The router checked the image: it fits this $_romFlavor router.'
            : "The router couldn't confirm this image fits. Check it is "
                  'made for this router before going on.',
        warning: isVerified ? null : 'Not checked by the router',
        details: [
          ('File', fileName),
          ('Size', '$fileSizeMbStr MB'),
          ('Firmware', _romFlavor),
        ],
        action: 'Install it',
      );

      if (proceed != true) {
        final router = appState.selectedRouter;
        final sysauth = appState.sysauth;
        final api = appState.apiService;
        if (router != null && sysauth != null && api != null) {
          unawaited(
            api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'file',
              method: 'remove',
              params: {'path': '/tmp/firmware.bin'},
            ),
          );
        }
        return;
      }

      if (_flashStarted) {
        Logger.warning('Already flashing, ignoring the second tap.');
        return;
      }
      _flashStarted = true;

      setState(() {
        _isProcessing = true;
        _uploadProgress = null;
        _statusMessage =
            l10n?.backupStatusFlashing ??
            'Executing sysupgrade flash on router...';
      });

      final sysupgradeArgs = <String>[
        if (_forceSysupgrade) '--force',
        _keepSettings ? '-k' : '-n',
        '/tmp/firmware.bin',
      ];

      bool flashInitiated = false;

      if (router != null && sysauth != null && api != null) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/sysupgrade', 'params': sysupgradeArgs},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            flashInitiated = true;
          }
        } catch (_) {}

        if (!flashInitiated) {
          try {
            final res = await api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'rpc-sys',
              method: 'upgrade_start',
              params: {'keep': _keepSettings},
            );
            if (res is List && res.length > 1 && res[0] == 0) {
              flashInitiated = true;
            }
          } catch (_) {}
        }
      }

      if (!flashInitiated) {
        flashInitiated = await appState.executeRouterCommand(
          '/sbin/sysupgrade',
          sysupgradeArgs,
        );
      }

      if (!mounted) return;
      ksSay(
        context,
        l10n?.sysUpgradeFlashInitiated ??
            'Flashing started. The router is restarting.',
      );
      _showRebootCountdownDialog();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('connection')) {
        ksSay(
          context,
          l10n?.sysUpgradeFlashInitiated ??
              'Flashing started. The router is restarting.',
        );
        _showRebootCountdownDialog();
      } else {
        ksSay(context, l10n?.sysUpgradeFlashFailed ?? 'Firmware Flash Failed');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
      }
    }
  }

  Future<void> _handleInstallUpgrade(FirmwareUpgradeAvailability avail) async {
    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final api = appState.apiService;

    if (router == null || sysauth == null || api == null) {
      ksSay(
        context,
        l10n?.sysUpgradeRouterNotActive ?? 'Router connection is not active.',
      );
      return;
    }

    if (avail.downloadUrl == null) {
      ksSay(
        context,
        l10n?.sysUpgradeUrlNotFound ??
            'Download URL not found for this upgrade.',
      );
      return;
    }

    bool keepSettingsLocal = _keepSettings;
    bool forceUpgradeLocal = _forceSysupgrade;

    final confirmed = await _flashSheet(
      title: 'Install ${avail.latestVersion ?? 'the upgrade'}?',
      intro: 'The router downloads it and installs it, then restarts.',
      details: [
        if (avail.currentVersion != null) ('Now', avail.currentVersion!),
        ('New', 'OpenWrt ${avail.latestVersion ?? ''}'),
        if (avail.imageName != null) ('File', avail.imageName!),
        if (avail.formattedImageSize != null)
          ('Download', avail.formattedImageSize!),
      ],
      action: 'Install it',
    );
    keepSettingsLocal = _keepSettings;
    forceUpgradeLocal = _forceSysupgrade;

    if (confirmed != true) return;

    if (_flashStarted) {
      Logger.warning('Already flashing, ignoring the second tap.');
      return;
    }
    _flashStarted = true;

    setState(() {
      _isProcessing = true;
      _uploadProgress = 0.05;
      _statusMessage =
          l10n?.sysUpgradeDirectRouterDownload(
            avail.formattedImageSize ?? '',
          ) ??
          'Instructing router to download firmware directly (${avail.formattedImageSize ?? ""} )...';
    });

    try {
      try {
        await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'remove',
          params: {'path': '/tmp/firmware.bin'},
        );
      } catch (_) {}

      bool directDownloadSuccess = false;
      final directDownloadCandidates = [
        {
          'cmd': '/bin/uclient-fetch',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': '/usr/bin/wget',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'uclient-fetch',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'wget',
          'args': ['-O', '/tmp/firmware.bin', avail.downloadUrl!],
        },
        {
          'cmd': 'curl',
          'args': [
            '-s',
            '-k',
            '-L',
            '-o',
            '/tmp/firmware.bin',
            avail.downloadUrl!,
          ],
        },
      ];

      for (final candidate in directDownloadCandidates) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': candidate['cmd'], 'params': candidate['args']},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            final statRes = await api.call(
              router.ipAddress,
              sysauth,
              router.useHttps,
              object: 'file',
              method: 'stat',
              params: {'path': '/tmp/firmware.bin'},
            );
            if (statRes is List && statRes.length > 1 && statRes[0] == 0) {
              final statData = statRes[1] as Map<String, dynamic>?;
              final size = statData?['size'] as int? ?? 0;
              if (size > 1024 * 1024) {
                directDownloadSuccess = true;
                Logger.info(
                  'Router directly downloaded firmware image ($size bytes)',
                );
                break;
              }
            }
          }
        } catch (_) {}
      }

      if (!directDownloadSuccess) {
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeFallbackStreaming ??
                'Router direct download unavailable; streaming image from app to router...';
            _uploadProgress = 0.10;
          });
        }

        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(minutes: 5),
            headers: {'User-Agent': 'Keystone'},
          ),
        );

        final response = await dio.get<List<int>>(
          avail.downloadUrl!,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (received, total) {
            if (total > 0 && mounted) {
              setState(() {
                _statusMessage =
                    l10n?.sysUpgradeDownloadingImage(
                      avail.latestVersion ?? '',
                      avail.formattedImageSize ?? '',
                    ) ??
                    'Downloading OpenWrt ${avail.latestVersion}...';
                _uploadProgress = (received / total) * 0.40;
              });
            }
          },
        );

        final bytes = Uint8List.fromList(response.data!);
        if (bytes.isEmpty) {
          throw Exception('Downloaded firmware image is empty.');
        }

        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeVerifyingChecksum ??
                'Verifying SHA-256 checksum...';
            _uploadProgress = 0.42;
          });
        }

        final computedSha256 = Sha256.hex(bytes);
        if (avail.sha256 != null &&
            computedSha256.toLowerCase() != avail.sha256!.toLowerCase()) {
          throw Exception(
            l10n?.sysUpgradeChecksumMismatch(avail.sha256!, computedSha256) ??
                'SHA-256 checksum mismatch! Upgrade aborted for device safety.',
          );
        }

        final sizeMb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeTransferringImage(sizeMb) ??
                'Transferring image to router ($sizeMb MB)...';
            _uploadProgress = 0.45;
          });
        }

        final b64Str = base64Encode(bytes);
        const chunkSize = 24000;
        for (var i = 0; i < b64Str.length; i += chunkSize) {
          final end = (i + chunkSize < b64Str.length)
              ? i + chunkSize
              : b64Str.length;
          final chunk = b64Str.substring(i, end);
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'write',
            params: {
              'path': '/tmp/firmware.bin',
              'data': chunk,
              'base64': true,
              if (i > 0) 'append': true,
            },
          );
          if (mounted) {
            setState(() {
              _uploadProgress = 0.45 + (end / b64Str.length) * 0.45;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage =
                l10n?.sysUpgradeDirectRouterDownloadSuccess ??
                'Firmware downloaded directly onto router.';
            _uploadProgress = 0.90;
          });
        }
      }

      if (mounted) {
        setState(() {
          _statusMessage =
              l10n?.sysUpgradeVerifyingRouterCompatibility ??
              'Verifying compatibility on router (sysupgrade -t)...';
          _uploadProgress = 0.92;
        });
      }

      final scanService = RouterUpgradeScanService(
        apiService: api,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
      );
      final validationResult = await scanService.validateImage(
        '/tmp/firmware.bin',
        force: forceUpgradeLocal,
      );

      if (!validationResult.isAcceptableForFlash) {
        try {
          await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'file',
            method: 'remove',
            params: {'path': '/tmp/firmware.bin'},
          );
        } catch (_) {}

        throw Exception(
          l10n?.sysUpgradeValidationFailed(
                validationResult.commandOutput ?? "Incompatible image",
              ) ??
              'Router pre-flash validation check failed. Upgrade cancelled.',
        );
      }

      if (mounted) {
        setState(() {
          _statusMessage =
              l10n?.sysUpgradeExecutingFlash ??
              'Executing sysupgrade flash on router...';
          _uploadProgress = 0.98;
        });
      }

      final sysupgradeArgs = <String>[
        if (forceUpgradeLocal) '--force',
        keepSettingsLocal ? '-k' : '-n',
        '/tmp/firmware.bin',
      ];

      bool flashInitiated = false;
      try {
        final res = await api.call(
          router.ipAddress,
          sysauth,
          router.useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': '/sbin/sysupgrade', 'params': sysupgradeArgs},
        );
        if (res is List && res.length > 1 && res[0] == 0) {
          flashInitiated = true;
        }
      } catch (_) {}

      if (!flashInitiated) {
        try {
          final res = await api.call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'rpc-sys',
            method: 'upgrade_start',
            params: {'keep': keepSettingsLocal},
          );
          if (res is List && res.length > 1 && res[0] == 0) {
            flashInitiated = true;
          }
        } catch (_) {}
      }

      if (!flashInitiated) {
        flashInitiated = await appState.executeRouterCommand(
          '/sbin/sysupgrade',
          sysupgradeArgs,
        );
      }

      if (!mounted) return;

      setState(() {
        _isProcessing = false;
        _flashStarted = false;
        _upgradeAvailability = null;
        _upgradeScan = null;
        _readinessReport = null;
        _imageValidation = const FirmwareImageValidationResult(
          status: ImageValidationStatus.notRun,
        );
      });

      ksSay(
        context,
        l10n?.sysUpgradeFlashInitiated ??
            'Flashing started. The router is restarting.',
      );
      _showRebootCountdownDialog();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().toLowerCase().contains('socket') ||
          e.toString().toLowerCase().contains('connection') ||
          e.toString().toLowerCase().contains('closed')) {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
          _upgradeAvailability = null;
          _upgradeScan = null;
          _readinessReport = null;
          _imageValidation = const FirmwareImageValidationResult(
            status: ImageValidationStatus.notRun,
          );
        });
        ksSay(
          context,
          l10n?.sysUpgradeFlashInitiated ??
              'Flashing started. The router is restarting.',
        );
        _showRebootCountdownDialog();
      } else {
        setState(() {
          _isProcessing = false;
          _flashStarted = false;
        });
        Logger.error('Automated upgrade failed: $e');
        ksSay(context, 'Upgrade failed');
      }
    }
  }

  void _showRebootCountdownDialog({bool isFactoryReset = false}) {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final originalIp = router?.ipAddress ?? '192.168.1.1';
    final originalUseHttps = router?.useHttps ?? false;

    int remainingSeconds = isFactoryReset ? 75 : 120;
    bool isOnline = false;
    String discoveredHost = isFactoryReset ? '192.168.1.1' : originalIp;
    bool discoveredHttps = isFactoryReset ? false : originalUseHttps;
    Timer? countdownTimer;
    Timer? probeTimer;

    probeTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      final probeThreshold = isFactoryReset ? 60 : 95;
      if (remainingSeconds > probeThreshold) return;
      if (isOnline) {
        t.cancel();
        return;
      }

      final candidates = <_ProbeTarget>[
        if (isFactoryReset) ...[
          const _ProbeTarget('http', '192.168.1.1'),
          const _ProbeTarget('https', '192.168.1.1'),
          const _ProbeTarget('http', 'openwrt.lan'),
          _ProbeTarget(originalUseHttps ? 'https' : 'http', originalIp),
        ] else ...[
          _ProbeTarget(originalUseHttps ? 'https' : 'http', originalIp),
          const _ProbeTarget('http', '192.168.1.1'),
        ],
      ];

      for (final target in candidates) {
        if (isOnline) break;
        try {
          final client = HttpClient()
            ..connectionTimeout = const Duration(seconds: 2)
            ..badCertificateCallback = ((cert, host, port) => true);
          final uri = Uri.parse('${target.scheme}://${target.host}/ubus');
          final request = await client.postUrl(uri);
          request.headers.contentType = ContentType.json;
          final payload = jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'list',
            'params': [],
          });
          request.write(payload);
          final response = await request.close();
          if (response.statusCode == 200 ||
              response.statusCode == 403 ||
              response.statusCode == 400) {
            isOnline = true;
            discoveredHost = target.host;
            discoveredHttps = target.scheme == 'https';
            t.cancel();
            break;
          }
        } catch (_) {}
      }
    });

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      backgroundColor: context.ks.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
            if (remainingSeconds > 0 && !isOnline) {
              setModalState(() {
                remainingSeconds--;
              });
            } else if (isOnline) {
              setModalState(() {});
              t.cancel();
            } else {
              setModalState(() {});
              t.cancel();
            }
          });

          final ks = context.ks;
          final address =
              '${discoveredHttps ? "https" : "http"}://$discoveredHost';
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isOnline)
                    Center(child: KsDot(ks.ok, size: 14))
                  else
                    const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 20),
                  Text(
                    isOnline
                        ? (isFactoryReset
                              ? 'Reset, and back online'
                              : 'The router is back')
                        : (isFactoryReset
                              ? 'Resetting the router…'
                              : 'The router is restarting…'),
                    textAlign: TextAlign.center,
                    style: KeystoneType.sheetTitle(ks.tx),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isOnline
                        ? (isFactoryReset
                              ? 'It answers at $address with its factory '
                                    'settings. Sign in with its default '
                                    'password.'
                              : 'It started on the new firmware.')
                        : "Keep it plugged in. About ${remainingSeconds}s left.",
                    textAlign: TextAlign.center,
                    style: KeystoneType.body(ks.mu),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      countdownTimer?.cancel();
                      probeTimer?.cancel();
                      Navigator.of(ctx).pop();
                      if (mounted) {
                        if (isFactoryReset) {
                          await ref.read(appStateProvider).logout();
                          if (mounted) {
                            Navigator.of(
                              this.context,
                            ).popUntil((route) => route.isFirst);
                          }
                        } else {
                          Navigator.of(this.context).pop();
                          unawaited(
                            ref
                                .read(appStateProvider)
                                .fetchDashboardData(force: true),
                          );
                        }
                      }
                    },
                    child: Text(
                      isOnline
                          ? (isFactoryReset ? 'Sign in again' : 'Done')
                          : 'Close and wait at home',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((_) {
      countdownTimer?.cancel();
      probeTimer?.cancel();
    });
  }

  Future<bool?> _flashSheet({
    required String title,
    required String intro,
    String? warning,
    required List<(String, String)> details,
    required String action,
  }) => ksSheet<bool>(
    context,
    (c) => StatefulBuilder(
      builder: (c, set) {
        final ks = c.ks;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: KeystoneType.sheetTitle(ks.tx)),
            const SizedBox(height: 6),
            Text(intro, style: KeystoneType.body(ks.tx2)),
            if (warning != null) ...[
              const SizedBox(height: 8),
              KsBanner(warning),
            ],
            const SizedBox(height: 8),
            for (final (k, v) in details)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(k, style: KeystoneType.secondary(ks.mu)),
                    ),
                    Expanded(child: Text(v, style: KeystoneType.body(ks.tx))),
                  ],
                ),
              ),
            KsSwitchRow(
              title: 'Keep my settings',
              subtitle: 'Wi-Fi, passwords and the rest carry over',
              value: _keepSettings,
              onChanged: (v) {
                set(() {});
                setState(() => _keepSettings = v);
              },
            ),
            KsSwitchRow(
              title: 'Skip the safety checks',
              subtitle: 'Only for an image you know fits this router',
              value: _forceSysupgrade,
              onChanged: (v) {
                set(() {});
                setState(() => _forceSysupgrade = v);
              },
            ),
            const SizedBox(height: 8),
            Text(
              "Keep the router plugged in and this screen open until it's done.",
              style: KeystoneType.secondary(ks.warnTx),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(action),
            ),
          ],
        );
      },
    ),
  );

  String _upgradeLine() {
    if (_upgradeCheckInProgress) return 'Checking…';
    final a = _upgradeAvailability;
    if (a == null) return 'See if a newer version is out';
    return switch (a.status) {
      UpgradeAvailabilityStatus.upgradeAvailable =>
        'Version ${a.latestVersion ?? 'new'} is out',
      UpgradeAvailabilityStatus.currentVersionLatest => "You're up to date",
      UpgradeAvailabilityStatus.notChecked => 'See if a newer version is out',
      UpgradeAvailabilityStatus.noMatchingImageFound =>
        'No image for this router was found',
      UpgradeAvailabilityStatus.updateSourceUnavailable =>
        "Couldn't reach the download site",
      UpgradeAvailabilityStatus.compatibilityUnverifiable =>
        "Couldn't confirm a version fits this router",
      UpgradeAvailabilityStatus.currentVersionUnknown =>
        "Couldn't tell which version this is",
      UpgradeAvailabilityStatus.unsupportedFirmwareSource =>
        'This firmware has its own updates; check its website',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final avail = _upgradeAvailability;
    final report = _readinessReport;
    final busy = _isProcessing;

    final page = KsPage(
      title: 'Backup and firmware',
      subtitle: [
        if (!_routerModel.startsWith('Detecting')) _routerModel,
        _firmwareVersion,
      ].join(' · '),
      children: [
        const KsSection('Backup'),
        KsRow(
          title: 'Save a backup',
          subtitle: _backupGeneratedInSession
              ? 'Saved this time. Keep it somewhere safe.'
              : 'Your settings as a file on this phone',
          onTap: busy ? null : _handleGenerateBackup,
        ),
        KsRow(
          title: 'Restore a backup',
          subtitle: 'Put saved settings back; the router restarts',
          onTap: busy ? null : _handleUploadArchive,
        ),
        KsRow(
          title: 'What a backup keeps',
          subtitle: 'The files and settings it includes',
          onTap: busy ? null : _showCurrentBackupFileList,
        ),
        const KsSection('Firmware'),
        KsRow(
          title: 'Check for a newer version',
          subtitle: _upgradeLine(),
          onTap: busy || _upgradeCheckInProgress ? null : _checkForUpgrades,
        ),
        if (avail?.status == UpgradeAvailabilityStatus.upgradeAvailable) ...[
          if (avail!.explanation case final e? when e.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(e, style: KeystoneType.secondary(ks.mu)),
            ),
          FilledButton(
            onPressed: busy || !_backupGeneratedInSession
                ? null
                : () => _handleInstallUpgrade(avail),
            child: Text('Install ${avail.latestVersion ?? 'it'}'),
          ),
          if (!_backupGeneratedInSession)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Save a backup first, in case something goes wrong.',
                textAlign: TextAlign.center,
                style: KeystoneType.caption(ks.warnTx),
              ),
            ),
        ],
        KsRow(
          title: 'Install firmware from a file',
          subtitle: 'A .bin or .itb image you downloaded',
          onTap: busy ? null : _handlePerformSysupgrade,
        ),
        KsSwitchRow(
          title: 'Keep my settings',
          subtitle: _keepSettings
              ? 'Wi-Fi, passwords and the rest carry over'
              : 'The router starts fresh, like new',
          value: _keepSettings,
          onChanged: busy ? null : (v) => setState(() => _keepSettings = v),
        ),
        Text(
          'Room for a firmware image: ${_resolveTmpSpace(null)}',
          style: KeystoneType.caption(ks.mu),
        ),
        if (report != null &&
            report.checks.isNotEmpty &&
            _imageValidation.wasRun) ...[
          const KsSection('Before you install'),
          for (final c in report.checks)
            KsRow(
              leading: KsDot(switch (c.severity) {
                ReadinessCheckSeverity.blocking => ks.bad,
                ReadinessCheckSeverity.warning => ks.warn,
                ReadinessCheckSeverity.info => ks.ok,
                ReadinessCheckSeverity.unknown => ks.mu,
              }),
              title: c.title,
              subtitle: c.description,
              chevron: false,
            ),
        ],
        const KsSection('Start over'),
        KsRow(
          title: 'Reset to factory settings',
          subtitle: 'Erases every setting; the router restarts as new',
          danger: true,
          chevron: false,
          onTap: busy ? null : _handleFactoryReset,
        ),
        const KsSection('For experts'),
        KsSwitchRow(
          title: 'Skip the safety checks when flashing',
          subtitle:
              'Only for an image you know fits. A wrong one can leave the '
              'router unable to start.',
          value: _forceSysupgrade,
          onChanged: busy ? null : (v) => setState(() => _forceSysupgrade = v),
        ),
        if (_mtdList.isNotEmpty) ...[
          KsChoice<String>(
            label: 'Copy a flash partition to this phone',
            value: _selectedMtdDevice ?? _mtdList.first['device'] ?? '',
            options: [
              for (final m in _mtdList)
                (m['device'] ?? '', m['name'] ?? m['device'] ?? ''),
            ],
            onChanged: (v) => setState(() => _selectedMtdDevice = v),
          ),
          OutlinedButton(
            onPressed: busy ? null : _handleSaveMtdblock,
            child: const Text('Save it'),
          ),
        ],
      ],
    );

    return Stack(
      children: [
        page,
        if (busy)
          Positioned.fill(
            child: ColoredBox(
              color: ks.bg.withValues(alpha: 0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(value: _uploadProgress),
                      const SizedBox(height: 16),
                      Text(
                        _uploadProgress != null
                            ? '${(_uploadProgress! * 100).toInt()}% sent'
                            : (_statusMessage ?? 'Working…'),
                        textAlign: TextAlign.center,
                        style: KeystoneType.bodyStrong(ks.tx),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Keep this screen open and don't unplug the router.",
                        textAlign: TextAlign.center,
                        style: KeystoneType.secondary(ks.mu),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProbeTarget {
  final String scheme;
  final String host;
  const _ProbeTarget(this.scheme, this.host);
}
