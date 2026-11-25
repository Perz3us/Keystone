// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';

enum PartitionMechanism {
  none,
  uBootEnvBootPart,
  uBootEnvBootPartReady,
  dualImageFlag,
  ubiDualBoot,
}

class DeviceProfile {
  final String profileId;

  final String displayName;

  final Set<String> compatibleBoardIds;

  final Set<String> compatibleModels;

  final String targetArchitecture;

  final Set<RebootOperationType> supportedOperations;

  final PartitionMechanism partitionMechanism;

  final Set<String> requiredMtdPartitionNames;

  final Set<String> requiredUtilities;

  final bool poweroffSupported;

  final List<String> validPartitionSlots;

  final String documentationUrl;

  final String notes;

  final String lastReviewed;

  const DeviceProfile({
    required this.profileId,
    required this.displayName,
    required this.compatibleBoardIds,
    this.compatibleModels = const {},
    this.targetArchitecture = '',
    required this.supportedOperations,
    this.partitionMechanism = PartitionMechanism.none,
    this.requiredMtdPartitionNames = const {},
    this.requiredUtilities = const {},
    this.poweroffSupported = false,
    this.validPartitionSlots = const ['1', '2'],
    required this.documentationUrl,
    required this.notes,
    required this.lastReviewed,
  });

  bool matches({required String boardName, String model = ''}) {
    if (boardName.isEmpty) return false;
    final normalizedBoard = boardName.trim().toLowerCase();
    final boardMatches = compatibleBoardIds.any(
      (b) => b.toLowerCase() == normalizedBoard,
    );
    if (!boardMatches) return false;

    if (compatibleModels.isNotEmpty && model.isNotEmpty) {
      final normalizedModel = model.trim().toLowerCase();
      final modelMatches = compatibleModels.any(
        (m) => normalizedModel.contains(m.toLowerCase()),
      );
      if (!modelMatches) return false;
    }

    return true;
  }

  String? getAlternateSlot(String activeSlot) {
    if (validPartitionSlots.length != 2) return null;
    if (activeSlot == validPartitionSlots[0]) return validPartitionSlots[1];
    if (activeSlot == validPartitionSlots[1]) return validPartitionSlots[0];
    return null;
  }

  List<List<String>> getSwitchPartitionCommands(String targetSlot) {
    if (!validPartitionSlots.contains(targetSlot)) {
      throw ArgumentError(
        'Target slot "$targetSlot" is not valid for profile $profileId. Valid slots: $validPartitionSlots',
      );
    }

    switch (partitionMechanism) {
      case PartitionMechanism.uBootEnvBootPart:
        return [
          ['fw_setenv', 'boot_part', targetSlot],
        ];
      case PartitionMechanism.uBootEnvBootPartReady:
        return [
          ['fw_setenv', 'boot_part', targetSlot],
          ['fw_setenv', 'boot_part_ready', targetSlot],
        ];
      case PartitionMechanism.dualImageFlag:
        return [
          ['fw_setenv', 'DualImageFlag', targetSlot],
        ];
      case PartitionMechanism.ubiDualBoot:
        return [
          ['fw_setenv', 'active', targetSlot],
        ];
      case PartitionMechanism.none:
        return [];
    }
  }

  Map<String, dynamic> toJson() => {
    'profileId': profileId,
    'displayName': displayName,
    'compatibleBoardIds': compatibleBoardIds.toList(),
    'compatibleModels': compatibleModels.toList(),
    'targetArchitecture': targetArchitecture,
    'supportedOperations': supportedOperations.map((o) => o.name).toList(),
    'partitionMechanism': partitionMechanism.name,
    'requiredMtdPartitionNames': requiredMtdPartitionNames.toList(),
    'requiredUtilities': requiredUtilities.toList(),
    'poweroffSupported': poweroffSupported,
    'validPartitionSlots': validPartitionSlots,
    'documentationUrl': documentationUrl,
    'notes': notes,
    'lastReviewed': lastReviewed,
  };
}
