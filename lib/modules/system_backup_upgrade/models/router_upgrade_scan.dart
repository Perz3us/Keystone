// SPDX-License-Identifier: GPL-3.0-or-later

enum DetectionConfidence { verified, likely, conditional, unknown }

enum RouterPackageManager { opkg, apk, mixed, vendorSpecific, none, unknown }

enum FirmwareFamily { openWrt, immortalWrt, glINet, gargoyle, lede, unknown }

class DetectedValue<T> {
  final T? value;
  final DetectionConfidence confidence;
  final String? source;

  const DetectedValue({
    required this.value,
    required this.confidence,
    this.source,
  });

  const DetectedValue.verified(this.value, {this.source})
    : confidence = DetectionConfidence.verified;

  const DetectedValue.unknown({this.source})
    : value = null,
      confidence = DetectionConfidence.unknown;

  const DetectedValue.likely(this.value, {this.source})
    : confidence = DetectionConfidence.likely;

  bool get isKnown =>
      confidence != DetectionConfidence.unknown && value != null;
  bool get isUnknown => !isKnown;

  @override
  String toString() => 'DetectedValue($value, $confidence, src=$source)';
}

class RouterUpgradeScan {
  final String routerId;

  final DateTime scannedAt;

  final bool isPartial;

  final String? partialScanReason;

  final DetectedValue<String> modelName;

  final DetectedValue<String> boardName;

  final DetectedValue<FirmwareFamily> firmwareFamily;

  final DetectedValue<String> firmwareFamilyLabel;

  final DetectedValue<String> distribDescription;

  final DetectedValue<String> distribRelease;

  final DetectedValue<String> distribTarget;

  final DetectedValue<String> distribArch;

  final DetectedValue<int> tmpAvailableBytes;

  final DetectedValue<int> tmpTotalBytes;

  final DetectedValue<RouterPackageManager> packageManager;

  final DetectedValue<bool> hasSysupgrade;

  final DetectedValue<bool> hasSysupgradeList;

  final DetectedValue<bool> hasSysupgradeBackup;

  final DetectedValue<bool> hasSysupgradeTest;

  final DetectedValue<bool> hasSysupgradeForce;

  final DetectedValue<List<String>> sysupgradePreservedFiles;

  final DetectedValue<String> sysupgradeConf;

  const RouterUpgradeScan({
    required this.routerId,
    required this.scannedAt,
    this.isPartial = false,
    this.partialScanReason,
    required this.modelName,
    required this.boardName,
    required this.firmwareFamily,
    required this.firmwareFamilyLabel,
    required this.distribDescription,
    required this.distribRelease,
    required this.distribTarget,
    required this.distribArch,
    required this.tmpAvailableBytes,
    required this.tmpTotalBytes,
    required this.packageManager,
    required this.hasSysupgrade,
    required this.hasSysupgradeList,
    required this.hasSysupgradeBackup,
    required this.hasSysupgradeTest,
    required this.hasSysupgradeForce,
    required this.sysupgradePreservedFiles,
    required this.sysupgradeConf,
  });

  factory RouterUpgradeScan.failed(String routerId, {String? reason}) {
    return RouterUpgradeScan(
      routerId: routerId,
      scannedAt: DateTime.now(),
      isPartial: true,
      partialScanReason: reason ?? 'Router scan failed',
      modelName: const DetectedValue.unknown(),
      boardName: const DetectedValue.unknown(),
      firmwareFamily: const DetectedValue.unknown(),
      firmwareFamilyLabel: const DetectedValue.unknown(),
      distribDescription: const DetectedValue.unknown(),
      distribRelease: const DetectedValue.unknown(),
      distribTarget: const DetectedValue.unknown(),
      distribArch: const DetectedValue.unknown(),
      tmpAvailableBytes: const DetectedValue.unknown(),
      tmpTotalBytes: const DetectedValue.unknown(),
      packageManager: const DetectedValue.unknown(),
      hasSysupgrade: const DetectedValue.unknown(),
      hasSysupgradeList: const DetectedValue.unknown(),
      hasSysupgradeBackup: const DetectedValue.unknown(),
      hasSysupgradeTest: const DetectedValue.unknown(),
      hasSysupgradeForce: const DetectedValue.unknown(),
      sysupgradePreservedFiles: const DetectedValue.unknown(),
      sysupgradeConf: const DetectedValue.unknown(),
    );
  }

  bool get isFresh =>
      DateTime.now().difference(scannedAt) < const Duration(minutes: 5);

  bool get isStale => !isFresh;

  String get tmpSpaceLabel {
    final avail = tmpAvailableBytes.value;
    if (avail == null) return 'Unknown';
    if (avail >= 1024 * 1024) {
      return '${(avail / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(avail / 1024).toStringAsFixed(0)} KB';
  }
}
