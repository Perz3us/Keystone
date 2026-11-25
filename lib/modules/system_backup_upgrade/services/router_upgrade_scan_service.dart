// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';

class RouterUpgradeScanService {
  final IApiService apiService;
  final String ipAddress;
  final String sysauth;
  final bool useHttps;

  Map<String, dynamic>? _cachedSystemBoard;

  RouterUpgradeScanService({
    required this.apiService,
    required this.ipAddress,
    required this.sysauth,
    required this.useHttps,
  });

  Future<Map<String, dynamic>?> _getSystemBoard() async {
    if (_cachedSystemBoard != null) return _cachedSystemBoard;
    try {
      final board = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'board',
      );
      if (board is List && board.length > 1 && board[0] == 0) {
        _cachedSystemBoard = board[1] as Map<String, dynamic>?;
      } else if (board is Map<String, dynamic>) {
        _cachedSystemBoard = board;
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._getSystemBoard failed: $e');
    }
    return _cachedSystemBoard;
  }

  Future<bool> _fileExists(String path) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'stat',
        params: {'path': path},
      );
      if (res is List && res.length > 1 && res[0] == 0) {
        final data = res[1];
        return data is Map && data.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  Future<String?> _execOutput(String command, List<String> args) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': command, 'params': args},
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    final cmdStr = _buildCmdStr(command, args);
    for (final sh in ['/bin/sh', 'sh', '/bin/ash', 'ash']) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': sh,
            'params': ['-c', cmdStr],
          },
        );
        final out = _extractStdout(res);
        if (out != null && out.trim().isNotEmpty) return out;
      } catch (_) {}
    }

    return null;
  }

  Future<String?> _readFile(String path) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': path},
      );
      return _extractStdout(res);
    } catch (_) {
      return null;
    }
  }

  String _buildCmdStr(String command, List<String> args) {
    if ((command == 'sh' ||
            command == '/bin/sh' ||
            command == 'ash' ||
            command == '/bin/ash') &&
        args.length >= 2 &&
        args[0] == '-c') {
      return args[1];
    }
    return [command, ...args].join(' ');
  }

  String? _extractStdout(dynamic res) {
    if (res == null) return null;
    if (res is List) {
      for (final item in res) {
        if (item is Map) {
          final out = item['stdout'] ?? item['data'] ?? item['out'];
          if (out != null) return out.toString();
        } else if (item is String && item.isNotEmpty && item != '0') {
          return item;
        }
      }
    } else if (res is Map) {
      final out = res['stdout'] ?? res['data'] ?? res['out'];
      if (out != null) return out.toString();
    }
    return null;
  }

  Future<DetectedValue<String>> _probeModel() async {
    try {
      final board = await _getSystemBoard();
      final model = board?['model']?.toString();
      if (model != null && model.trim().isNotEmpty) {
        return DetectedValue.verified(
          model.trim(),
          source: 'system.board ubus',
        );
      }

      final val = await _readFile('/tmp/sysinfo/model');
      if (val != null && val.trim().isNotEmpty) {
        return DetectedValue.verified(val.trim(), source: '/tmp/sysinfo/model');
      }

      final boardJson = await _readFile('/etc/board.json');
      if (boardJson != null && boardJson.trim().isNotEmpty) {
        try {
          final data = jsonDecode(boardJson);
          if (data is Map && data['model'] is Map) {
            final name = data['model']['name']?.toString();
            if (name != null && name.trim().isNotEmpty) {
              return DetectedValue.verified(
                name.trim(),
                source: '/etc/board.json',
              );
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._probeModel failed: $e');
    }
    return const DetectedValue.unknown(source: 'probe failed');
  }

  Future<DetectedValue<String>> _probeBoardName() async {
    try {
      final board = await _getSystemBoard();
      final name = board?['board_name']?.toString();
      if (name != null && name.trim().isNotEmpty) {
        return DetectedValue.verified(name.trim(), source: 'system.board ubus');
      }

      final val = await _readFile('/tmp/sysinfo/board_name');
      if (val != null && val.trim().isNotEmpty) {
        return DetectedValue.verified(
          val.trim(),
          source: '/tmp/sysinfo/board_name',
        );
      }

      final boardJson = await _readFile('/etc/board.json');
      if (boardJson != null && boardJson.trim().isNotEmpty) {
        try {
          final data = jsonDecode(boardJson);
          if (data is Map && data['model'] is Map) {
            final id = data['model']['id']?.toString();
            if (id != null && id.trim().isNotEmpty) {
              return DetectedValue.verified(
                id.trim(),
                source: '/etc/board.json',
              );
            }
          }
        } catch (_) {}
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._probeBoardName failed: $e');
    }
    return const DetectedValue.unknown(source: 'probe failed');
  }

  Future<Map<String, String>> _probeReleaseFile() async {
    final result = <String, String>{};
    try {
      String? content = await _readFile('/etc/openwrt_release');
      content ??= await _execOutput('cat', ['/etc/openwrt_release']);
      if (content != null && content.trim().isNotEmpty) {
        for (final line in content.split('\n')) {
          final eq = line.indexOf('=');
          if (eq == -1) continue;
          final key = line.substring(0, eq).trim();
          var val = line.substring(eq + 1).trim();
          if (val.startsWith('"') && val.endsWith('"') && val.length >= 2) {
            val = val.substring(1, val.length - 1);
          } else if (val.startsWith("'") &&
              val.endsWith("'") &&
              val.length >= 2) {
            val = val.substring(1, val.length - 1);
          }
          result[key] = val;
        }
      }

      final board = await _getSystemBoard();
      if (board != null && board['release'] is Map) {
        final rel = board['release'] as Map;
        result.putIfAbsent(
          'DISTRIB_ID',
          () => rel['distribution']?.toString() ?? 'OpenWrt',
        );
        if (rel['version'] != null) {
          result.putIfAbsent(
            'DISTRIB_RELEASE',
            () => rel['version'].toString(),
          );
        }
        if (rel['revision'] != null) {
          result.putIfAbsent(
            'DISTRIB_REVISION',
            () => rel['revision'].toString(),
          );
        }
        if (rel['target'] != null) {
          result.putIfAbsent('DISTRIB_TARGET', () => rel['target'].toString());
        }
        if (rel['description'] != null) {
          result.putIfAbsent(
            'DISTRIB_DESCRIPTION',
            () => rel['description'].toString(),
          );
        }
      }

      if (!result.containsKey('DISTRIB_ARCH') &&
          result.containsKey('DISTRIB_TARGET')) {
        final target = result['DISTRIB_TARGET']!;
        final arch = _deriveTargetArch(target, board?['system']?.toString());
        if (arch != null) {
          result['DISTRIB_ARCH'] = arch;
        }
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._probeReleaseFile failed: $e');
    }
    return result;
  }

  static String? _deriveTargetArch(String target, String? system) {
    if (target.startsWith('ath79/')) return 'mips_24kc';
    if (target.startsWith('ipq40xx/')) return 'arm_cortex-a7_neon-vfpv4';
    if (target.startsWith('ramips/')) return 'mipsel_24kc';
    if (target.startsWith('bcm27xx/bcm2711')) return 'aarch64_cortex-a72';
    if (target.startsWith('bcm27xx/bcm2710')) return 'aarch64_cortex-a53';
    if (target.startsWith('mediatek/filogic')) return 'aarch64_cortex-a53';
    if (target.startsWith('x86/64')) return 'x86_64';
    if (target.startsWith('x86/generic')) return 'i386_pentium4';
    if (target.startsWith('rockchip/armv8')) return 'aarch64_generic';
    if (system != null && system.toLowerCase().contains('mips')) return 'mips';
    if (system != null && system.toLowerCase().contains('arm')) return 'arm';
    return null;
  }

  Future<(DetectedValue<FirmwareFamily>, DetectedValue<String>)>
  _probeFirmwareFamily() async {
    try {
      final board = await _getSystemBoard();
      if (board != null && board['release'] is Map) {
        final rel = board['release'] as Map;
        final dist = (rel['distribution']?.toString() ?? '').toLowerCase();
        final desc = (rel['description']?.toString() ?? '').toLowerCase();

        if (dist.contains('immortal') || desc.contains('immortal')) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.immortalWrt,
              source: 'system.board',
            ),
            const DetectedValue.verified('ImmortalWrt', source: 'system.board'),
          );
        }
        if (dist.contains('gl') ||
            dist.contains('gl-inet') ||
            desc.contains('gl.inet')) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.glINet,
              source: 'system.board',
            ),
            DetectedValue.verified(
              'GL.iNet Firmware (${rel['version'] ?? dist})',
              source: 'system.board',
            ),
          );
        }
        if (dist.contains('gargoyle') || desc.contains('gargoyle')) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.gargoyle,
              source: 'system.board',
            ),
            const DetectedValue.verified(
              'Gargoyle Router OS',
              source: 'system.board',
            ),
          );
        }
        if (dist.contains('lede') || desc.contains('lede')) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.lede,
              source: 'system.board',
            ),
            const DetectedValue.verified('LEDE Reboot', source: 'system.board'),
          );
        }
        if (dist.contains('openwrt') || desc.contains('openwrt')) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.openWrt,
              source: 'system.board',
            ),
            const DetectedValue.verified('OpenWrt', source: 'system.board'),
          );
        }
      }

      final immortal = await _readFile('/etc/immortalwrt_release');
      if (immortal != null && immortal.trim().isNotEmpty) {
        return (
          const DetectedValue.verified(
            FirmwareFamily.immortalWrt,
            source: '/etc/immortalwrt_release',
          ),
          const DetectedValue.verified(
            'ImmortalWrt',
            source: '/etc/immortalwrt_release',
          ),
        );
      }

      final glVersion = await _readFile('/etc/glversion');
      if (glVersion != null && glVersion.trim().isNotEmpty) {
        return (
          const DetectedValue.verified(
            FirmwareFamily.glINet,
            source: '/etc/glversion',
          ),
          DetectedValue.verified(
            'GL.iNet Firmware (${glVersion.trim()})',
            source: '/etc/glversion',
          ),
        );
      }

      final gargoyle = await _readFile('/etc/gargoyle_release');
      if (gargoyle != null && gargoyle.trim().isNotEmpty) {
        return (
          const DetectedValue.verified(
            FirmwareFamily.gargoyle,
            source: '/etc/gargoyle_release',
          ),
          const DetectedValue.verified(
            'Gargoyle Router OS',
            source: '/etc/gargoyle_release',
          ),
        );
      }

      final osRelease = await _readFile('/etc/os-release');
      if (osRelease != null && osRelease.contains('LEDE')) {
        return (
          const DetectedValue.verified(
            FirmwareFamily.lede,
            source: '/etc/os-release',
          ),
          const DetectedValue.verified(
            'LEDE Reboot',
            source: '/etc/os-release',
          ),
        );
      }

      final owrtRelease = await _readFile('/etc/openwrt_release');
      if (owrtRelease != null && owrtRelease.isNotEmpty) {
        return (
          const DetectedValue.verified(
            FirmwareFamily.openWrt,
            source: '/etc/openwrt_release',
          ),
          const DetectedValue.verified(
            'OpenWrt',
            source: '/etc/openwrt_release',
          ),
        );
      }

      try {
        final luciVer = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'luci',
          method: 'getVersion',
        );
        if (luciVer != null) {
          return (
            const DetectedValue.verified(
              FirmwareFamily.openWrt,
              source: 'luci.getVersion',
            ),
            const DetectedValue.verified('OpenWrt', source: 'luci.getVersion'),
          );
        }
      } catch (_) {}
    } catch (e) {
      Logger.warning(
        'RouterUpgradeScanService._probeFirmwareFamily failed: $e',
      );
    }
    return (
      const DetectedValue<FirmwareFamily>.unknown(
        source: 'no vendor file detected',
      ),
      const DetectedValue<String>.unknown(source: 'no vendor file detected'),
    );
  }

  Future<({DetectedValue<int> available, DetectedValue<int> total})>
  _probeTmpSpace() async {
    try {
      final sysInfo = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'info',
        params: const {},
      );
      Map<String, dynamic>? data;
      if (sysInfo is List && sysInfo.length > 1 && sysInfo[0] == 0) {
        data = sysInfo[1] as Map<String, dynamic>?;
      } else if (sysInfo is Map<String, dynamic>) {
        data = sysInfo;
      }

      if (data != null && data['tmp'] is Map) {
        final tmpMap = data['tmp'] as Map;
        final availKb = (tmpMap['avail'] ?? tmpMap['free']) as num?;
        final totalKb = tmpMap['total'] as num?;
        if (availKb != null) {
          return (
            available: DetectedValue.verified(
              availKb.toInt() * 1024,
              source: 'ubus system info',
            ),
            total: totalKb != null
                ? DetectedValue.verified(
                    totalKb.toInt() * 1024,
                    source: 'ubus system info',
                  )
                : const DetectedValue<int>.unknown(),
          );
        }
      }
    } catch (_) {}

    try {
      final dfOut = await _execOutput('sh', ['-c', 'df -k /tmp | tail -n 1']);
      if (dfOut != null && dfOut.trim().isNotEmpty) {
        final parts = dfOut.trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final totalKb = int.tryParse(parts[1]);
          final availKb = int.tryParse(parts[3]);
          if (availKb != null) {
            return (
              available: DetectedValue.verified(
                availKb * 1024,
                source: 'df -k /tmp',
              ),
              total: totalKb != null
                  ? DetectedValue.verified(totalKb * 1024, source: 'df -k /tmp')
                  : const DetectedValue<int>.unknown(),
            );
          }
        }
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._probeTmpSpace failed: $e');
    }
    return (
      available: const DetectedValue<int>.unknown(source: 'tmp probe failed'),
      total: const DetectedValue<int>.unknown(source: 'tmp probe failed'),
    );
  }

  Future<DetectedValue<RouterPackageManager>> _probePackageManager({
    String? distribRelease,
  }) async {
    try {
      try {
        final featRes = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'luci',
          method: 'getFeatures',
        );
        Map? featData;
        if (featRes is List && featRes.length > 1 && featRes[0] == 0) {
          featData = featRes[1] is Map ? featRes[1] as Map : null;
        } else if (featRes is Map) {
          featData = featRes;
        }
        if (featData != null) {
          final hasApk = featData['apk'] == true;
          final hasOpkg = featData['opkg'] == true;
          if (hasApk && hasOpkg) {
            return const DetectedValue.verified(
              RouterPackageManager.mixed,
              source: 'luci.getFeatures',
            );
          }
          if (hasApk) {
            return const DetectedValue.verified(
              RouterPackageManager.apk,
              source: 'luci.getFeatures',
            );
          }
          if (hasOpkg) {
            return const DetectedValue.verified(
              RouterPackageManager.opkg,
              source: 'luci.getFeatures',
            );
          }
        }
      } catch (_) {}

      if (await _fileExists('/etc/apk/repositories.d/distfeeds.list') ||
          await _fileExists('/etc/apk/repositories')) {
        return const DetectedValue.verified(
          RouterPackageManager.apk,
          source: 'apk repositories detected',
        );
      }
      if (await _fileExists('/etc/opkg.conf') ||
          await _fileExists('/etc/opkg/distfeeds.conf')) {
        return const DetectedValue.verified(
          RouterPackageManager.opkg,
          source: 'opkg configuration detected',
        );
      }

      final apkCheck = await _execOutput('sh', [
        '-c',
        'command -v apk 2>/dev/null || which apk 2>/dev/null',
      ]);
      final hasApk = apkCheck != null && apkCheck.trim().isNotEmpty;

      final opkgCheck = await _execOutput('sh', [
        '-c',
        'command -v opkg 2>/dev/null || which opkg 2>/dev/null',
      ]);
      final hasOpkg = opkgCheck != null && opkgCheck.trim().isNotEmpty;

      if (hasApk && hasOpkg) {
        return const DetectedValue.verified(
          RouterPackageManager.mixed,
          source: 'which apk + which opkg',
        );
      }
      if (hasApk) {
        return const DetectedValue.verified(
          RouterPackageManager.apk,
          source: 'which apk',
        );
      }
      if (hasOpkg) {
        return const DetectedValue.verified(
          RouterPackageManager.opkg,
          source: 'which opkg',
        );
      }

      final rel = distribRelease ?? '';
      if (rel.startsWith('25.') ||
          rel.startsWith('26.') ||
          rel.startsWith('27.')) {
        return const DetectedValue.likely(
          RouterPackageManager.apk,
          source: 'OpenWrt 25+ default',
        );
      } else if (rel.startsWith('24.') ||
          rel.startsWith('23.') ||
          rel.startsWith('22.') ||
          rel.startsWith('21.') ||
          rel.startsWith('19.')) {
        return const DetectedValue.likely(
          RouterPackageManager.opkg,
          source: 'OpenWrt <= 24 default',
        );
      }
    } catch (e) {
      Logger.warning(
        'RouterUpgradeScanService._probePackageManager failed: $e',
      );
    }
    return const DetectedValue.unknown(source: 'package manager probe failed');
  }

  Future<DetectedValue<bool>> _probeSysupgrade() async {
    try {
      if (await _fileExists('/sbin/sysupgrade') ||
          await _fileExists('/usr/sbin/sysupgrade') ||
          await _fileExists('/bin/sysupgrade')) {
        return const DetectedValue.verified(
          true,
          source: '/sbin/sysupgrade exists',
        );
      }

      final out = await _execOutput('/sbin/sysupgrade', ['--list-backup']);
      if (out != null) {
        return const DetectedValue.verified(
          true,
          source: '/sbin/sysupgrade --list-backup',
        );
      }

      final cmdCheck = await _execOutput('sh', [
        '-c',
        'command -v sysupgrade 2>/dev/null || which sysupgrade 2>/dev/null',
      ]);
      if (cmdCheck != null && cmdCheck.trim().isNotEmpty) {
        return const DetectedValue.verified(
          true,
          source: 'command -v sysupgrade',
        );
      }

      final board = await _getSystemBoard();
      final dist = board?['release']?['distribution']?.toString().toLowerCase();
      if (dist == 'openwrt' || dist == 'immortalwrt' || dist == 'lede') {
        return const DetectedValue.likely(
          true,
          source: 'OpenWrt base-files standard',
        );
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService._probeSysupgrade failed: $e');
    }
    return const DetectedValue.unknown(source: 'probe failed');
  }

  Future<DetectedValue<bool>> _probeSysupgradeCapability(String flag) async {
    try {
      final helpOut =
          await _execOutput('/sbin/sysupgrade', ['--help']) ??
          await _execOutput('sysupgrade', ['--help']) ??
          await _execOutput('sh', ['-c', 'sysupgrade --help 2>&1']);
      if (helpOut != null && helpOut.trim().isNotEmpty) {
        return DetectedValue.likely(
          helpOut.contains(flag),
          source: 'sysupgrade --help',
        );
      }

      if (flag == '-l' || flag == '-b' || flag == '-t' || flag == '-F') {
        return const DetectedValue.likely(
          true,
          source: 'OpenWrt sysupgrade core capability',
        );
      }
    } catch (e) {
      Logger.warning(
        'RouterUpgradeScanService._probeSysupgradeCapability($flag) failed: $e',
      );
    }
    return const DetectedValue.unknown(source: 'probe failed');
  }

  Future<DetectedValue<List<String>>> _probeSysupgradeList() async {
    try {
      for (final cmd in [
        ['/sbin/sysupgrade', '--list-backup'],
        ['/sbin/sysupgrade', '-l'],
        ['sysupgrade', '--list-backup'],
        ['sysupgrade', '-l'],
        ['sh', '-c', 'sysupgrade -l 2>/dev/null'],
      ]) {
        final out = await _execOutput(cmd[0], cmd.sublist(1));
        if (out != null && out.trim().isNotEmpty) {
          final paths = out
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty && !l.startsWith('#'))
              .toList();
          if (paths.isNotEmpty) {
            return DetectedValue.verified(paths, source: cmd.join(' '));
          }
        }
      }

      final confContent = await _readFile('/etc/sysupgrade.conf');
      if (confContent != null && confContent.trim().isNotEmpty) {
        final paths = confContent
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty && !l.startsWith('#'))
            .toList();
        if (paths.isNotEmpty) {
          return DetectedValue.likely(paths, source: '/etc/sysupgrade.conf');
        }
      }
    } catch (e) {
      Logger.warning(
        'RouterUpgradeScanService._probeSysupgradeList failed: $e',
      );
    }
    return const DetectedValue.unknown(source: 'sysupgrade -l probe failed');
  }

  Future<DetectedValue<String>> _probeSysupgradeConf() async {
    try {
      final content = await _readFile('/etc/sysupgrade.conf');
      if (content != null) {
        return DetectedValue.verified(content, source: '/etc/sysupgrade.conf');
      }
      final catOut = await _execOutput('cat', ['/etc/sysupgrade.conf']);
      if (catOut != null) {
        return DetectedValue.verified(
          catOut,
          source: 'cat /etc/sysupgrade.conf',
        );
      }
    } catch (e) {
      Logger.warning(
        'RouterUpgradeScanService._probeSysupgradeConf failed: $e',
      );
    }
    return const DetectedValue.unknown(
      source: '/etc/sysupgrade.conf not readable',
    );
  }

  Future<RouterUpgradeScan> scan() async {
    Logger.info('RouterUpgradeScanService: Starting scan for $ipAddress');

    final failures = <String>[];

    final results = await Future.wait([
      _probeModel().catchError((e) {
        failures.add('model');
        return const DetectedValue<String>.unknown();
      }),
      _probeBoardName().catchError((e) {
        failures.add('boardName');
        return const DetectedValue<String>.unknown();
      }),
      _probeReleaseFile(),
      _probeFirmwareFamily(),
      _probeTmpSpace(),
      _probeSysupgrade().catchError((e) {
        failures.add('sysupgrade');
        return const DetectedValue<bool>.unknown();
      }),
      _probeSysupgradeList().catchError((e) {
        failures.add('sysupgradeList');
        return const DetectedValue<List<String>>.unknown();
      }),
      _probeSysupgradeConf().catchError((e) {
        failures.add('sysupgradeConf');
        return const DetectedValue<String>.unknown();
      }),
    ]);

    final modelName = results[0] as DetectedValue<String>;
    final boardName = results[1] as DetectedValue<String>;
    final releaseMap = results[2] as Map<String, String>;
    final firmwareFamilyResult =
        results[3] as (DetectedValue<FirmwareFamily>, DetectedValue<String>);
    final tmpResult =
        results[4]
            as ({DetectedValue<int> available, DetectedValue<int> total});
    final hasSysupgrade = results[5] as DetectedValue<bool>;
    final sysupgradePreservedFiles = results[6] as DetectedValue<List<String>>;
    final sysupgradeConf = results[7] as DetectedValue<String>;

    final packageManager =
        await _probePackageManager(
          distribRelease: releaseMap['DISTRIB_RELEASE'],
        ).catchError((e) {
          failures.add('packageManager');
          return const DetectedValue<RouterPackageManager>.unknown();
        });

    final distribDescription = releaseMap['DISTRIB_DESCRIPTION'];
    final distribRelease = releaseMap['DISTRIB_RELEASE'];
    final distribTarget = releaseMap['DISTRIB_TARGET'];
    final distribArch = releaseMap['DISTRIB_ARCH'];

    DetectedValue<bool> hasSysupgradeList = const DetectedValue.unknown();
    DetectedValue<bool> hasSysupgradeBackup = const DetectedValue.unknown();
    DetectedValue<bool> hasSysupgradeTest = const DetectedValue.unknown();
    DetectedValue<bool> hasSysupgradeForce = const DetectedValue.unknown();

    if (hasSysupgrade.value == true) {
      final capResults = await Future.wait([
        _probeSysupgradeCapability(
          '-l',
        ).catchError((_) => const DetectedValue<bool>.unknown()),
        _probeSysupgradeCapability(
          '-b',
        ).catchError((_) => const DetectedValue<bool>.unknown()),
        _probeSysupgradeCapability(
          '-t',
        ).catchError((_) => const DetectedValue<bool>.unknown()),
        _probeSysupgradeCapability(
          '-F',
        ).catchError((_) => const DetectedValue<bool>.unknown()),
      ]);
      // ignore: unnecessary_cast
      hasSysupgradeList = capResults[0] as DetectedValue<bool>;
      // ignore: unnecessary_cast
      hasSysupgradeBackup = capResults[1] as DetectedValue<bool>;
      // ignore: unnecessary_cast
      hasSysupgradeTest = capResults[2] as DetectedValue<bool>;
      // ignore: unnecessary_cast
      hasSysupgradeForce = capResults[3] as DetectedValue<bool>;
    }

    final isPartial = failures.isNotEmpty;

    Logger.info(
      'RouterUpgradeScanService: Scan complete. Partial=$isPartial. '
      'Model=${modelName.value}, Board=${boardName.value}, '
      'Family=${firmwareFamilyResult.$1.value}, '
      'PkgMgr=${packageManager.value}',
    );

    return RouterUpgradeScan(
      routerId: ipAddress,
      scannedAt: DateTime.now(),
      isPartial: isPartial,
      partialScanReason: isPartial
          ? 'Some probes failed: ${failures.join(', ')}'
          : null,
      modelName: modelName,
      boardName: boardName,
      firmwareFamily: firmwareFamilyResult.$1,
      firmwareFamilyLabel: firmwareFamilyResult.$2,
      distribDescription:
          distribDescription != null && distribDescription.isNotEmpty
          ? DetectedValue.verified(
              distribDescription,
              source: releaseMap['_source'] ?? '/etc/openwrt_release',
            )
          : const DetectedValue.unknown(
              source: 'DISTRIB_DESCRIPTION not found',
            ),
      distribRelease: distribRelease != null && distribRelease.isNotEmpty
          ? DetectedValue.verified(
              distribRelease,
              source: releaseMap['_source'] ?? '/etc/openwrt_release',
            )
          : const DetectedValue.unknown(source: 'DISTRIB_RELEASE not found'),
      distribTarget: distribTarget != null && distribTarget.isNotEmpty
          ? DetectedValue.verified(
              distribTarget,
              source: releaseMap['_source'] ?? '/etc/openwrt_release',
            )
          : const DetectedValue.unknown(source: 'DISTRIB_TARGET not found'),
      distribArch: distribArch != null && distribArch.isNotEmpty
          ? DetectedValue.verified(
              distribArch,
              source: releaseMap['_source'] ?? '/etc/openwrt_release',
            )
          : const DetectedValue.unknown(source: 'DISTRIB_ARCH not found'),
      tmpAvailableBytes: tmpResult.available,
      tmpTotalBytes: tmpResult.total,
      packageManager: packageManager,
      hasSysupgrade: hasSysupgrade,
      hasSysupgradeList: hasSysupgradeList,
      hasSysupgradeBackup: hasSysupgradeBackup,
      hasSysupgradeTest: hasSysupgradeTest,
      hasSysupgradeForce: hasSysupgradeForce,
      sysupgradePreservedFiles: sysupgradePreservedFiles,
      sysupgradeConf: sysupgradeConf,
    );
  }

  Future<FirmwareImageValidationResult> validateImage(
    String imagePath, {
    bool force = false,
  }) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'validate_firmware_image',
        params: {'path': imagePath},
      );
      Map<String, dynamic>? data;
      if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
        data = res[1] as Map<String, dynamic>?;
      } else if (res is Map<String, dynamic>) {
        data = res;
      }

      if (data != null && data.containsKey('valid')) {
        final isValid = data['valid'] == true;
        final forceable = data['forceable'] == true;
        if (isValid) {
          return FirmwareImageValidationResult(
            status: ImageValidationStatus.passed,
            commandOutput: jsonEncode(data),
          );
        } else {
          return FirmwareImageValidationResult(
            status: ImageValidationStatus.failed,
            commandOutput: jsonEncode(data),
            forceApplied: force && forceable,
            forceExplanation: force && forceable
                ? 'Firmware image validation check bypassed via force flag'
                : null,
          );
        }
      }
    } catch (e) {
      Logger.warning('RouterUpgradeScanService.validateImage ubus failed: $e');
    }

    for (final cmd in [
      ['/sbin/sysupgrade', '--test', imagePath],
      ['/sbin/sysupgrade', '-t', imagePath],
      ['sysupgrade', '--test', imagePath],
      ['sysupgrade', '-t', imagePath],
    ]) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': cmd[0], 'params': cmd.sublist(1)},
        );
        int? code;
        String? stdout;
        String? stderr;
        if (res is List && res.length > 1 && res[0] == 0 && res[1] is Map) {
          final m = res[1] as Map;
          code = m['code'] as int?;
          stdout = m['stdout']?.toString();
          stderr = m['stderr']?.toString();
        } else if (res is Map) {
          code = res['code'] as int?;
          stdout = res['stdout']?.toString();
          stderr = res['stderr']?.toString();
        }

        final combinedOutput = [
          stdout,
          stderr,
        ].where((s) => s != null && s.trim().isNotEmpty).join('\n');

        if (code != null) {
          if (code == 0) {
            return FirmwareImageValidationResult(
              status: ImageValidationStatus.passed,
              commandOutput: combinedOutput.isNotEmpty
                  ? combinedOutput
                  : 'Verification passed (code 0)',
            );
          } else {
            return FirmwareImageValidationResult(
              status: ImageValidationStatus.failed,
              commandOutput: combinedOutput.isNotEmpty
                  ? combinedOutput
                  : 'sysupgrade test failed (code $code)',
              forceApplied: force,
              forceExplanation: force
                  ? 'Forced override of failed image test'
                  : null,
            );
          }
        }
      } catch (_) {}
    }

    return const FirmwareImageValidationResult(
      status: ImageValidationStatus.inconclusive,
      commandOutput: 'Image validation could not be executed on router',
    );
  }
}
