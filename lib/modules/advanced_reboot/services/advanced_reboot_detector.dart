// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import '../../../models/router_capabilities.dart';
import '../../../services/interfaces/api_service_interface.dart';
import '../../../services/interfaces/ssh_service_interface.dart';
import '../../../utils/logger.dart';
import '../adapters/boot_adapter_registry.dart';
import '../adapters/ubi_dual_boot_adapter.dart';
import '../adapters/uboot_boot_part_adapter.dart';
import '../adapters/uboot_boot_part_ready_adapter.dart';
import '../adapters/uboot_dual_image_flag_adapter.dart';
import '../models/reboot_capability.dart';
import '../profiles/device_profile.dart';
import '../profiles/device_profile_registry.dart';

class AdvancedRebootDetector {
  final IApiService apiService;
  final ISshService? sshService;
  final DeviceProfileRegistry registry;
  final BootAdapterRegistry adapterRegistry;

  AdvancedRebootDetector({
    required this.apiService,
    this.sshService,
    DeviceProfileRegistry? registry,
    BootAdapterRegistry? adapterRegistry,
  }) : registry = registry ?? DeviceProfileRegistry.instance,
       adapterRegistry = adapterRegistry ?? BootAdapterRegistry.instance;

  Future<AdvancedRebootCapabilities> detect({
    required String routerId,
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
    RouterCapabilities? routerCapabilities,
  }) async {
    final now = DateTime.now();

    try {
      final boardInfo = await _queryBoardInfo(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        routerCapabilities: routerCapabilities,
      );

      final boardName = boardInfo['boardName'] ?? '';
      final model = boardInfo['model'] ?? '';
      final releaseVersion = boardInfo['release'] ?? '';
      final targetArch = boardInfo['target'] ?? '';

      final mtdPartitions = await _queryProcMtd(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        sshUsername: sshUsername,
        sshPassword: sshPassword,
        sshPort: sshPort,
      );

      final bootEnvResult = await _queryBootloaderEnv(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
        sshUsername: sshUsername,
        sshPassword: sshPassword,
        sshPort: sshPort,
      );

      final bootloaderEnv = bootEnvResult['env'] as Map<String, String>? ?? {};
      final hasFwPrintenv = bootEnvResult['hasFwPrintenv'] as bool? ?? false;
      final hasFwSetenv = bootEnvResult['hasFwSetenv'] as bool? ?? false;

      final luciAdvInfo = await _queryOpportunisticLuciAdvancedReboot(
        ipAddress: ipAddress,
        sysauth: sysauth,
        useHttps: useHttps,
      );

      String? activeSlot;
      String? alternateSlot;

      if (bootloaderEnv.containsKey('boot_part')) {
        final rawVal = bootloaderEnv['boot_part']?.trim();
        if (rawVal == '1') {
          activeSlot = '1';
          alternateSlot = '2';
        } else if (rawVal == '2') {
          activeSlot = '2';
          alternateSlot = '1';
        }
      } else if (bootloaderEnv.containsKey('DualImageFlag')) {
        final rawVal = bootloaderEnv['DualImageFlag']?.trim();
        if (rawVal == '0' || rawVal == '1') {
          activeSlot = rawVal;
          alternateSlot = rawVal == '0' ? '1' : '0';
        }
      } else if (bootloaderEnv.containsKey('active')) {
        final rawVal = bootloaderEnv['active']?.trim();
        if (rawVal == '0' || rawVal == '1') {
          activeSlot = rawVal;
          alternateSlot = rawVal == '0' ? '1' : '0';
        }
      } else if (bootloaderEnv.containsKey('boot_bank')) {
        final rawVal = bootloaderEnv['boot_bank']?.trim();
        if (rawVal == '0' || rawVal == '1') {
          activeSlot = rawVal;
          alternateSlot = rawVal == '0' ? '1' : '0';
        }
      }

      activeSlot ??= luciAdvInfo?['activeSlot'];
      alternateSlot ??= luciAdvInfo?['alternateSlot'];

      final activeOs =
          luciAdvInfo?['activeOs'] ??
          await _queryActiveOsRelease(
            ipAddress: ipAddress,
            sysauth: sysauth,
            useHttps: useHttps,
            sshUsername: sshUsername,
            sshPassword: sshPassword,
            sshPort: sshPort,
            fallbackRelease: releaseVersion,
          );

      final alternateOs =
          luciAdvInfo?['alternateOs'] ??
          await _queryAlternateOsRelease(
            ipAddress: ipAddress,
            sysauth: sysauth,
            useHttps: useHttps,
            sshUsername: sshUsername,
            sshPassword: sshPassword,
            sshPort: sshPort,
            mtdPartitions: mtdPartitions,
            activeSlot: activeSlot,
          );

      final env = DeviceBootEnvironment(
        boardName: boardName,
        model: model,
        releaseVersion: releaseVersion,
        targetArchitecture: targetArch,
        mtdPartitions: mtdPartitions,
        activeSlot: activeSlot,
        alternateSlot: alternateSlot,
        activeOs: activeOs,
        alternateOs: alternateOs,
        hasFwPrintenv: hasFwPrintenv,
        hasFwSetenv: hasFwSetenv,
        bootloaderEnv: bootloaderEnv,
        rawDiagnostics: {
          'boardQuery': boardInfo,
          'mtdCount': mtdPartitions.length,
          'bootloaderVarsCount': bootloaderEnv.length,
          'activeOs': activeOs,
          'alternateOs': alternateOs,
        },
      );

      final matchResult = registry.findMatchingProfile(
        boardName: boardName,
        model: model,
      );

      final capabilities = <RebootOperationType, OperationCapability>{};

      capabilities[RebootOperationType.standardReboot] =
          await _evaluateStandardReboot(
            env: env,
            routerCapabilities: routerCapabilities,
          );

      capabilities[RebootOperationType.alternatePartitionBoot] =
          await _evaluateAlternatePartitionBoot(
            env: env,
            matchResult: matchResult,
          );

      capabilities[RebootOperationType.powerOff] = await _evaluatePowerOff(
        env: env,
        matchResult: matchResult,
      );

      final altCap = capabilities[RebootOperationType.alternatePartitionBoot];
      final matchedAdapterId = altCap?.mechanismId;

      String? discoveredMechanismName;
      if (altCap?.isSupported == true) {
        if (matchedAdapterId == 'uboot_boot_part_ready') {
          discoveredMechanismName = 'U-Boot (boot_part + ready)';
        } else if (matchedAdapterId == 'uboot_boot_part') {
          discoveredMechanismName = 'U-Boot (boot_part)';
        } else if (matchedAdapterId == 'uboot_dual_image_flag') {
          discoveredMechanismName = 'U-Boot (DualImageFlag)';
        } else if (matchedAdapterId == 'ubi_dual_boot') {
          discoveredMechanismName = 'UBI Dual-Boot';
        } else {
          discoveredMechanismName = 'Native Dual-Boot';
        }
      } else if (!env.hasDualPartitionLayout) {
        discoveredMechanismName = 'Single-Boot Layout';
      } else {
        discoveredMechanismName = 'Dual-Boot (Unverified)';
      }

      final finalEnv = DeviceBootEnvironment(
        boardName: env.boardName,
        model: env.model,
        releaseVersion: env.releaseVersion,
        targetArchitecture: env.targetArchitecture,
        storageType: env.storageType,
        mtdPartitions: env.mtdPartitions,
        activeSlot: env.activeSlot,
        alternateSlot: env.alternateSlot,
        activeOs: env.activeOs,
        alternateOs: env.alternateOs,
        discoveredMechanismName: discoveredMechanismName,
        availableTargets: env.availableTargets,
        hasFwPrintenv: env.hasFwPrintenv,
        hasFwSetenv: env.hasFwSetenv,
        bootloaderEnv: env.bootloaderEnv,
        discoveredMechanisms: env.discoveredMechanisms,
        evidenceProvenance: env.evidenceProvenance,
        cmdline: env.cmdline,
        rawDiagnostics: env.rawDiagnostics,
      );

      return AdvancedRebootCapabilities(
        routerId: routerId,
        detectedAt: now,
        environment: finalEnv,
        capabilities: capabilities,
        matchedAdapterId: matchedAdapterId,
        matchedProfileId: matchResult.profile?.profileId,
      );
    } catch (e, stack) {
      Logger.exception('Advanced Reboot capability detection failed', e, stack);
      return _buildErrorCapabilities(routerId: routerId, error: e.toString());
    }
  }

  Future<Map<String, String>> _queryBoardInfo({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    RouterCapabilities? routerCapabilities,
  }) async {
    String boardName = routerCapabilities?.boardName ?? '';
    String model = '';
    String release = routerCapabilities?.releaseVersion ?? '';
    String target = '';

    Object? boardError;

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'system',
        method: 'board',
      );
      final map = _unwrapRpcMap(res);
      if (map != null) {
        final bName =
            map['board_name']?.toString() ?? map['boardname']?.toString();
        if (bName != null && bName.isNotEmpty) {
          boardName = bName;
        }
        final mName = map['model']?.toString();
        if (mName != null && mName.isNotEmpty) {
          model = mName;
        }
        final rel = map['release'];
        if (rel is Map) {
          release =
              rel['description']?.toString() ??
              rel['version']?.toString() ??
              release;
          target = rel['target']?.toString() ?? '';
        }
      }
    } catch (e) {
      boardError = e;
      Logger.debug('ubus system.board call failed during detection: $e');
    }

    if (boardName.isEmpty || boardName.toLowerCase().contains('generic')) {
      try {
        final fileRes = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': '/tmp/sysinfo/board_name'},
        );
        final out = _extractData(fileRes);
        if (out != null && out.trim().isNotEmpty) {
          boardName = out.trim();
          boardError = null;
        }
      } catch (e) {
        boardError ??= e;
      }
    }

    if (boardName.isEmpty && boardError != null) {
      throw boardError;
    }

    if (model.isEmpty) {
      try {
        final fileRes = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': '/tmp/sysinfo/model'},
        );
        final out = _extractData(fileRes);
        if (out != null && out.trim().isNotEmpty) {
          model = out.trim();
        }
      } catch (_) {}
    }

    return {
      'boardName': boardName,
      'model': model,
      'release': release,
      'target': target,
    };
  }

  Future<List<MtdPartitionInfo>> _queryProcMtd({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
  }) async {
    String? rawMtd;

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/proc/mtd'},
      );
      rawMtd = _extractData(res);
    } catch (_) {}

    if ((rawMtd == null || rawMtd.trim().isEmpty) &&
        sshService != null &&
        sshUsername != null &&
        sshPassword != null) {
      try {
        final sshRes = await sshService!.executeCommand(
          host: ipAddress,
          username: sshUsername,
          password: sshPassword,
          port: sshPort,
          command: 'cat /proc/mtd',
        );
        if (sshRes.success) {
          rawMtd = sshRes.stdout;
        }
      } catch (_) {}
    }

    if (rawMtd == null || rawMtd.trim().isEmpty) {
      return [];
    }

    final partitions = <MtdPartitionInfo>[];
    for (final line in LineSplitter.split(rawMtd)) {
      if (line.trim().startsWith('mtd')) {
        final part = MtdPartitionInfo.fromProcMtdLine(line);
        if (part.dev.isNotEmpty) {
          partitions.add(part);
        }
      }
    }
    return partitions;
  }

  Future<Map<String, dynamic>> _queryBootloaderEnv({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
  }) async {
    final env = <String, String>{};
    bool hasFwPrintenv = false;
    bool hasFwSetenv = false;

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/usr/sbin/fw_printenv',
          'params': ['-n', 'boot_part'],
          'args': ['-n', 'boot_part'],
        },
      );
      final rpcMap = _unwrapRpcMap(res);
      if (rpcMap != null && rpcMap['code'] == 0) {
        hasFwPrintenv = true;
      }
      final out = _extractData(res);
      if (out != null && !out.contains('not found')) {
        hasFwPrintenv = true;
        if (out.trim().isNotEmpty) {
          env['boot_part'] = out.trim();
        }
      }
    } catch (_) {}

    if (!hasFwPrintenv) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': 'fw_printenv',
            'params': ['-n', 'boot_part'],
            'args': ['-n', 'boot_part'],
          },
        );
        final rpcMap = _unwrapRpcMap(res);
        if (rpcMap != null && rpcMap['code'] == 0) {
          hasFwPrintenv = true;
        }
        final out = _extractData(res);
        if (out != null && !out.contains('not found')) {
          hasFwPrintenv = true;
          if (out.trim().isNotEmpty) {
            env['boot_part'] = out.trim();
          }
        }
      } catch (_) {}
    }

    if (hasFwPrintenv) {
      for (final varName in const [
        'boot_part_ready',
        'DualImageFlag',
        'active',
        'boot_bank',
      ]) {
        try {
          final res = await apiService.call(
            ipAddress,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: {
              'command': 'fw_printenv',
              'params': ['-n', varName],
              'args': ['-n', varName],
            },
          );
          final out = _extractData(res);
          if (out != null &&
              out.trim().isNotEmpty &&
              !out.contains('not found')) {
            env[varName] = out.trim();
          }
        } catch (_) {}
      }
    }

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'which',
          'params': ['fw_setenv'],
          'args': ['fw_setenv'],
        },
      );
      final out = _extractData(res);
      if (out != null && out.contains('fw_setenv')) {
        hasFwSetenv = true;
      }
    } catch (_) {}

    if (!hasFwPrintenv &&
        sshService != null &&
        sshUsername != null &&
        sshPassword != null) {
      try {
        final sshRes = await sshService!.executeCommand(
          host: ipAddress,
          username: sshUsername,
          password: sshPassword,
          port: sshPort,
          command: 'fw_printenv -n boot_part',
        );
        if (sshRes.success && sshRes.stdout.trim().isNotEmpty) {
          hasFwPrintenv = true;
          env['boot_part'] = sshRes.stdout.trim();

          for (final varName in const [
            'boot_part_ready',
            'DualImageFlag',
            'active',
            'boot_bank',
          ]) {
            final varRes = await sshService!.executeCommand(
              host: ipAddress,
              username: sshUsername,
              password: sshPassword,
              port: sshPort,
              command: 'fw_printenv -n $varName',
            );
            if (varRes.success &&
                varRes.stdout.trim().isNotEmpty &&
                !varRes.stdout.contains('not found')) {
              env[varName] = varRes.stdout.trim();
            }
          }

          final whichRes = await sshService!.executeCommand(
            host: ipAddress,
            username: sshUsername,
            password: sshPassword,
            port: sshPort,
            command: 'which fw_setenv',
          );
          if (whichRes.success && whichRes.stdout.contains('fw_setenv')) {
            hasFwSetenv = true;
          }
        }
      } catch (_) {}
    }

    return {
      'env': env,
      'hasFwPrintenv': hasFwPrintenv,
      'hasFwSetenv': hasFwSetenv,
    };
  }

  Future<OperationCapability> _evaluateStandardReboot({
    required DeviceBootEnvironment env,
    RouterCapabilities? routerCapabilities,
  }) async {
    final standardAdapters = adapterRegistry.adaptersFor(
      RebootOperationType.standardReboot,
    );
    if (standardAdapters.isNotEmpty) {
      return await standardAdapters.first.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.standardReboot,
      );
    }
    return const OperationCapability(
      operation: RebootOperationType.standardReboot,
      status: CapabilityStatus.supported,
      reason: 'Standard reboot is supported via LuCI system.reboot RPC.',
      positiveEvidence: ['LuCI ubus system.reboot available'],
      riskLevel: RiskLevel.low,
      warningMessage:
          'This will restart the router. The network connection will be lost until the router finishes booting.',
    );
  }

  Future<OperationCapability> _evaluateAlternatePartitionBoot({
    required DeviceBootEnvironment env,
    required ProfileMatchResult matchResult,
  }) async {
    if (matchResult.isAmbiguous) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unknown,
        reason: matchResult.message,
        missingOrConflictingEvidence: [
          'Multiple conflicting device profiles matched board "${env.boardName}"',
        ],
        riskLevel: RiskLevel.high,
      );
    }

    final profile = matchResult.profile;
    if (profile != null &&
        !profile.supportedOperations.contains(
          RebootOperationType.alternatePartitionBoot,
        )) {
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason:
            'Profile "${profile.displayName}" does not support alternate partition booting.',
        positiveEvidence: ['Profile "${profile.profileId}" matched'],
        riskLevel: RiskLevel.low,
      );
    }

    if (!env.hasDualPartitionLayout) {
      return const OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason:
            'Single firmware partition layout detected. This router hardware does not support dual-boot switching.',
        positiveEvidence: ['Partition scan confirms single firmware layout'],
        riskLevel: RiskLevel.low,
      );
    }

    if (!env.hasFwPrintenv || !env.hasFwSetenv) {
      final missingUtils = <String>[];
      if (!env.hasFwPrintenv) {
        missingUtils.add('fw_printenv utility missing or inaccessible');
      }
      if (!env.hasFwSetenv) {
        missingUtils.add(
          'fw_setenv utility missing or execution permission denied',
        );
      }
      return OperationCapability(
        operation: RebootOperationType.alternatePartitionBoot,
        status: CapabilityStatus.unsupported,
        reason:
            'Bootloader control utilities are missing on the router (${missingUtils.join("; ")}).',
        positiveEvidence: [
          'Dual-firmware partition layout detected (${env.mtdPartitions.length} partitions)',
        ],
        missingOrConflictingEvidence: missingUtils,
        riskLevel: RiskLevel.high,
      );
    }

    final candidateAdapters = adapterRegistry.adaptersFor(
      RebootOperationType.alternatePartitionBoot,
    );

    OperationCapability? bestUnknownCapability;

    for (final adapter in candidateAdapters) {
      if (profile != null) {
        if (profile.partitionMechanism ==
                PartitionMechanism.uBootEnvBootPartReady &&
            adapter is! UBootBootPartReadyAdapter) {
          continue;
        }
        if (profile.partitionMechanism == PartitionMechanism.uBootEnvBootPart &&
            adapter is! UBootBootPartAdapter) {
          continue;
        }
        if (profile.partitionMechanism == PartitionMechanism.dualImageFlag &&
            adapter is! UBootDualImageFlagAdapter) {
          continue;
        }
        if (profile.partitionMechanism == PartitionMechanism.ubiDualBoot &&
            adapter is! UbiDualBootAdapter) {
          continue;
        }
      }

      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.alternatePartitionBoot,
        matchedProfile: profile,
      );

      if (cap.isSupported) {
        return cap;
      }

      if (cap.status == CapabilityStatus.unknown) {
        bestUnknownCapability ??= cap;
      }
    }

    if (bestUnknownCapability != null) {
      return bestUnknownCapability;
    }

    return OperationCapability(
      operation: RebootOperationType.alternatePartitionBoot,
      status: CapabilityStatus.unknown,
      reason:
          'Dual-firmware partition layout detected, but no supported bootloader variable (boot_part, boot_part_ready, DualImageFlag, or UBI active) could be verified on board "${env.boardName}". Partition switching refused to prevent selecting an invalid partition.',
      positiveEvidence: [
        'Dual partition layout detected in /proc/mtd (${env.mtdPartitions.length} partitions)',
      ],
      missingOrConflictingEvidence: [
        'Bootloader variables could not be mapped to any verified boot mechanism',
      ],
      riskLevel: RiskLevel.critical,
    );
  }

  Future<OperationCapability> _evaluatePowerOff({
    required DeviceBootEnvironment env,
    required ProfileMatchResult matchResult,
  }) async {
    final poweroffAdapters = adapterRegistry.adaptersFor(
      RebootOperationType.powerOff,
    );
    for (final adapter in poweroffAdapters) {
      final cap = await adapter.inspectCapabilities(
        environment: env,
        operation: RebootOperationType.powerOff,
        matchedProfile: matchResult.profile,
      );
      if (cap.isSupported) {
        return cap;
      }
    }

    return OperationCapability(
      operation: RebootOperationType.powerOff,
      status: CapabilityStatus.unsupported,
      reason:
          'Hardware DC power-down is not supported on this platform (${env.boardName.isEmpty ? "embedded router" : env.boardName}). '
          'Executing poweroff halts Linux execution but leaves hardware energized, requiring physical power cycling.',
      riskLevel: RiskLevel.low,
    );
  }

  AdvancedRebootCapabilities _buildErrorCapabilities({
    required String routerId,
    required String error,
  }) {
    const emptyEnv = DeviceBootEnvironment(
      boardName: '',
      model: '',
      releaseVersion: '',
    );
    final errorCap = OperationCapability(
      operation: RebootOperationType.standardReboot,
      status: CapabilityStatus.error,
      reason: 'Capability detection failed: $error',
      riskLevel: RiskLevel.medium,
    );

    return AdvancedRebootCapabilities(
      routerId: routerId,
      detectedAt: DateTime.now(),
      environment: emptyEnv,
      capabilities: {
        RebootOperationType.standardReboot: errorCap,
        RebootOperationType.alternatePartitionBoot: OperationCapability(
          operation: RebootOperationType.alternatePartitionBoot,
          status: CapabilityStatus.error,
          reason: 'Capability detection failed: $error',
          riskLevel: RiskLevel.high,
        ),
        RebootOperationType.powerOff: OperationCapability(
          operation: RebootOperationType.powerOff,
          status: CapabilityStatus.error,
          reason: 'Capability detection failed: $error',
          riskLevel: RiskLevel.medium,
        ),
      },
      detectionError: error,
    );
  }

  Future<String?> _queryActiveOsRelease({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
    String? fallbackRelease,
  }) async {
    String? output;

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'read',
        params: {'path': '/etc/os-release'},
      );
      output = _extractData(res);
    } catch (_) {}

    if (output == null || output.trim().isEmpty) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': '/etc/openwrt_release'},
        );
        output = _extractData(res);
      } catch (_) {}
    }

    if ((output == null || output.trim().isEmpty) &&
        sshService != null &&
        sshUsername != null &&
        sshPassword != null) {
      try {
        final sshRes = await sshService!.executeCommand(
          host: ipAddress,
          username: sshUsername,
          password: sshPassword,
          port: sshPort,
          command:
              'cat /etc/os-release 2>/dev/null || cat /etc/openwrt_release 2>/dev/null',
        );
        if (sshRes.success) {
          output = sshRes.stdout;
        }
      } catch (_) {}
    }

    final parsed = _parseOsRelease(output);
    if (parsed != null && parsed.isNotEmpty) {
      return parsed;
    }
    if (fallbackRelease != null && fallbackRelease.isNotEmpty) {
      return fallbackRelease;
    }
    return null;
  }

  Future<String?> _queryAlternateOsRelease({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
    String? sshUsername,
    String? sshPassword,
    int sshPort = 22,
    required List<MtdPartitionInfo> mtdPartitions,
    required String? activeSlot,
  }) async {
    if (activeSlot == null || mtdPartitions.isEmpty) return null;

    for (final altPath in const [
      '/alt/alt_rom/etc/os-release',
      '/alt/etc/os-release',
      '/rom_alt/etc/os-release',
      '/alt/alt_rom/etc/openwrt_release',
      '/alt/etc/openwrt_release',
    ]) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': altPath},
        );
        final data = _extractData(res);
        final os = _parseOsRelease(data);
        if (os != null && os.isNotEmpty) {
          return os;
        }
      } catch (_) {}
    }

    final inactivePart = _findInactiveRootfsPartition(
      mtdPartitions,
      activeSlot,
    );
    if (inactivePart == null) return null;

    final mtdNumMatch = RegExp(r'mtd(\d+)').firstMatch(inactivePart.dev);
    final mtdBlockDev = mtdNumMatch != null
        ? '/dev/mtdblock${mtdNumMatch.group(1)}'
        : '/dev/${inactivePart.dev}';
    final mtdNum = mtdNumMatch != null ? mtdNumMatch.group(1)! : '';

    final ubiProbe = mtdNum.isNotEmpty
        ? '(ubiattach -m $mtdNum -d 1 2>/dev/null && '
              '(ls /dev/ubiblock1_0 >/dev/null 2>&1 || ubiblock -c /dev/ubi1_0 2>/dev/null) && '
              '(mount -t squashfs -o ro /dev/ubiblock1_0 /tmp/.yala_alt_os 2>/dev/null || '
              'mount -t ubifs -o ro /dev/ubi1_0 /tmp/.yala_alt_os 2>/dev/null || '
              'mount -t ubifs -o ro ubi1:rootfs /tmp/.yala_alt_os 2>/dev/null))'
        : 'false';

    final script =
        'mkdir -p /tmp/.yala_alt_os ; '
        '(mount -o ro $mtdBlockDev /tmp/.yala_alt_os 2>/dev/null || $ubiProbe) && '
        '(cat /tmp/.yala_alt_os/etc/os-release '
        '/tmp/.yala_alt_os/usr/lib/os-release '
        '/tmp/.yala_alt_os/etc/openwrt_release '
        '/tmp/.yala_alt_os/etc/version '
        '/tmp/.yala_alt_os/etc/build_version 2>/dev/null) ; '
        'umount /tmp/.yala_alt_os 2>/dev/null ; '
        'ubiblock -r /dev/ubi1_0 2>/dev/null ; '
        'ubidetach -d 1 2>/dev/null ; '
        'rmdir /tmp/.yala_alt_os 2>/dev/null';

    String? output;

    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', script],
          'args': ['-c', script],
        },
      );
      output = _extractData(res);
    } catch (_) {}

    if (output == null || output.trim().isEmpty) {
      try {
        final res = await apiService.call(
          ipAddress,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': 'sh',
            'params': ['-c', script],
            'args': ['-c', script],
          },
        );
        output = _extractData(res);
      } catch (_) {}
    }

    if ((output == null || output.trim().isEmpty) &&
        sshService != null &&
        sshUsername != null &&
        sshPassword != null) {
      try {
        final sshRes = await sshService!.executeCommand(
          host: ipAddress,
          username: sshUsername,
          password: sshPassword,
          port: sshPort,
          command: "sh -c '$script'",
        );
        if (sshRes.success) {
          output = sshRes.stdout;
        }
      } catch (_) {}
    }

    return _parseOsRelease(output);
  }

  MtdPartitionInfo? _findInactiveRootfsPartition(
    List<MtdPartitionInfo> partitions,
    String? activeSlot,
  ) {
    if (partitions.isEmpty || activeSlot == null) return null;

    if (activeSlot == '1') {
      for (final p in partitions) {
        final lower = p.name.toLowerCase();
        if (lower == 'alt_rootfs' ||
            lower == 'rootfs2' ||
            lower == 'rootfs_1' ||
            lower == 'rootfs_b' ||
            lower == 'image1' ||
            lower == 'firmware2') {
          return p;
        }
      }
      final rootfsPartitions = partitions
          .where(
            (p) =>
                p.name.toLowerCase().contains('rootfs') ||
                p.name.toLowerCase().contains('firmware'),
          )
          .toList();
      if (rootfsPartitions.length >= 2) {
        return rootfsPartitions[1];
      }
    }

    if (activeSlot == '2') {
      for (final p in partitions) {
        final lower = p.name.toLowerCase();
        if (lower == 'rootfs' ||
            lower == 'rootfs1' ||
            lower == 'rootfs_0' ||
            lower == 'rootfs_a' ||
            lower == 'image0' ||
            lower == 'firmware' ||
            lower == 'firmware1' ||
            lower == 'pri_rootfs') {
          return p;
        }
      }
      final rootfsPartitions = partitions
          .where(
            (p) =>
                p.name.toLowerCase().contains('rootfs') ||
                p.name.toLowerCase().contains('firmware'),
          )
          .toList();
      if (rootfsPartitions.length >= 2) {
        return rootfsPartitions[0];
      }
    }

    if (activeSlot == '0') {
      for (final p in partitions) {
        final lower = p.name.toLowerCase();
        if (lower == 'rootfs_1' ||
            lower == 'rootfs1' ||
            lower == 'rootfs2' ||
            lower == 'image1' ||
            lower == 'alt_rootfs') {
          return p;
        }
      }
    }

    return null;
  }

  String? _parseOsRelease(String? content) {
    if (content == null || content.trim().isEmpty) return null;

    final lines = LineSplitter.split(content);
    String? prettyName;
    String? distribDescription;
    String? name;
    String? version;
    String? oemVersion;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('PRETTY_NAME=')) {
        prettyName = _cleanQuotes(line.substring('PRETTY_NAME='.length));
      } else if (line.startsWith('DISTRIB_DESCRIPTION=')) {
        distribDescription = _cleanQuotes(
          line.substring('DISTRIB_DESCRIPTION='.length),
        );
      } else if (line.startsWith('NAME=')) {
        name = _cleanQuotes(line.substring('NAME='.length));
      } else if (line.startsWith('VERSION=')) {
        version = _cleanQuotes(line.substring('VERSION='.length));
      } else if (RegExp(r'^\d+\.\d+\.\d+').hasMatch(line)) {
        oemVersion = line;
      }
    }

    if (prettyName != null && prettyName.isNotEmpty) {
      return prettyName;
    }
    if (distribDescription != null && distribDescription.isNotEmpty) {
      return distribDescription;
    }
    if (name != null && name.isNotEmpty) {
      return version != null && version.isNotEmpty ? '$name $version' : name;
    }
    if (oemVersion != null && oemVersion.isNotEmpty) {
      return 'Stock Firmware v$oemVersion';
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final openwrtMatch = RegExp(
        r'(OpenWrt\s+[0-9\.\-A-Za-z]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (openwrtMatch != null) {
        return openwrtMatch.group(1);
      }

      if (line.toLowerCase().contains('stock')) {
        return line;
      }

      if (!line.contains('=') && !line.contains(':') && line.length < 50) {
        return line;
      }
    }

    return null;
  }

  Map<String, dynamic>? _unwrapRpcMap(dynamic res) {
    if (res == null) return null;
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return res.cast<String, dynamic>();
    if (res is List && res.length > 1 && res[1] is Map) {
      return (res[1] as Map).cast<String, dynamic>();
    }
    if (res is List && res.isNotEmpty && res[0] is Map) {
      return (res[0] as Map).cast<String, dynamic>();
    }
    return null;
  }

  Future<Map<String, String>?> _queryOpportunisticLuciAdvancedReboot({
    required String ipAddress,
    required String sysauth,
    required bool useHttps,
  }) async {
    try {
      final res = await apiService.call(
        ipAddress,
        sysauth,
        useHttps,
        object: 'luci.advanced-reboot',
        method: 'obtain_device_info',
      );
      final data = _unwrapRpcMap(res);
      if (data == null) return null;

      final dev = data['device'] as Map?;
      final activePart = dev?['partition_active']?.toString();
      final partitions = data['partitions'] as List?;

      String? activeOs;
      String? alternateOs;
      final String? activeSlot = activePart;
      String? alternateSlot;

      if (partitions != null && partitions.isNotEmpty) {
        for (final p in partitions) {
          if (p is Map) {
            final num = p['number']?.toString();
            final label = p['label']?.toString();
            final os = p['os']?.toString();
            final parsedOs = _parseOsRelease(label) ?? _parseOsRelease(os);

            if (num != null && num == activeSlot) {
              activeOs = parsedOs ?? label;
            } else if (num != null) {
              alternateSlot = num;
              alternateOs = parsedOs ?? label;
            }
          }
        }
      }

      if (activeOs != null || alternateOs != null || activeSlot != null) {
        return {
          'activeSlot': ?activeSlot,
          'alternateSlot': ?alternateSlot,
          'activeOs': ?activeOs,
          'alternateOs': ?alternateOs,
        };
      }
    } catch (_) {}
    return null;
  }

  String _cleanQuotes(String value) {
    var v = value.trim();
    if ((v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))) {
      v = v.substring(1, v.length - 1).trim();
    }
    return v;
  }

  String? _extractData(dynamic res) {
    if (res == null) return null;
    if (res is String) return res;
    if (res is List) {
      for (final item in res) {
        if (item is Map) {
          final out = item['data'] ?? item['stdout'] ?? item['out'];
          if (out != null) return out.toString();
        } else if (item is String && item != '0') {
          return item;
        }
      }
    } else if (res is Map) {
      final out = res['stdout'] ?? res['data'] ?? res['out'];
      if (out != null) return out.toString();
    }
    return null;
  }
}
