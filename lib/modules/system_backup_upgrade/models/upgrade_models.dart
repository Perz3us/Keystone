// SPDX-License-Identifier: GPL-3.0-or-later

import 'router_upgrade_scan.dart';

enum ImageValidationStatus { passed, failed, inconclusive, unsupported, notRun }

enum ReadinessCheckSeverity { blocking, warning, info, unknown }

class ReadinessCheckItem {
  final String id;
  final String title;
  final String description;
  final ReadinessCheckSeverity severity;

  final String? detail;

  final bool canForce;

  const ReadinessCheckItem({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.detail,
    this.canForce = false,
  });

  bool get isBlocking => severity == ReadinessCheckSeverity.blocking;
  bool get isWarning => severity == ReadinessCheckSeverity.warning;
  bool get isInfo => severity == ReadinessCheckSeverity.info;
  bool get isUnknown => severity == ReadinessCheckSeverity.unknown;
}

class UpgradeReadinessReport {
  final List<ReadinessCheckItem> checks;

  final bool basedOnStaleData;

  final bool isPartial;

  const UpgradeReadinessReport({
    required this.checks,
    this.basedOnStaleData = false,
    this.isPartial = false,
  });

  List<ReadinessCheckItem> get blocking =>
      checks.where((c) => c.isBlocking).toList();
  List<ReadinessCheckItem> get warnings =>
      checks.where((c) => c.isWarning).toList();
  List<ReadinessCheckItem> get infos => checks.where((c) => c.isInfo).toList();
  List<ReadinessCheckItem> get unknowns =>
      checks.where((c) => c.isUnknown).toList();

  bool get hasBlockingIssues => blocking.isNotEmpty;
  bool get hasWarnings => warnings.isNotEmpty;
  int get blockingCount => blocking.length;
  int get warningCount => warnings.length;
  bool get hasForcibleBlockers =>
      blocking.any((c) => c.canForce) && !blocking.any((c) => !c.canForce);

  int get passCount =>
      checks.where((c) => c.severity == ReadinessCheckSeverity.info).length;
}

enum PreservationCategory {
  configuration,
  credentials,
  customScript,
  installedPackage,
  runtimeData,
  externalStorage,
  hardwareCalibration,
  luciExtension,
  kernelModule,
  vpnCredential,
  unknown,
}

enum PreservationOutcome { preserved, lost, conditional, unknown }

class PreservationImpactItem {
  final String path;
  final PreservationCategory category;
  final String? description;

  final String detectionSource;

  final PreservationOutcome outcome;
  final DetectionConfidence confidence;

  final String? recommendedAction;

  final bool coveredByBackup;

  final bool isSensitive;

  const PreservationImpactItem({
    required this.path,
    required this.category,
    this.description,
    required this.detectionSource,
    required this.outcome,
    required this.confidence,
    this.recommendedAction,
    this.coveredByBackup = false,
    this.isSensitive = false,
  });
}

class PreservationImpactInventory {
  final List<PreservationImpactItem> items;

  final bool isPartial;

  final String? limitationNote;

  const PreservationImpactInventory({
    required this.items,
    this.isPartial = false,
    this.limitationNote,
  });

  List<PreservationImpactItem> get preserved =>
      items.where((i) => i.outcome == PreservationOutcome.preserved).toList();

  List<PreservationImpactItem> get lost =>
      items.where((i) => i.outcome == PreservationOutcome.lost).toList();

  List<PreservationImpactItem> get conditional =>
      items.where((i) => i.outcome == PreservationOutcome.conditional).toList();

  List<PreservationImpactItem> get unknown =>
      items.where((i) => i.outcome == PreservationOutcome.unknown).toList();

  List<PreservationImpactItem> get needsAction =>
      items.where((i) => i.recommendedAction != null).toList();
}

enum PackageMigrationTransition {
  opkgToOpkg,
  apkToApk,
  opkgToApk,
  apkToOpkg,
  mixedOrVendor,
  unknown,
}

enum PackageMigrationStatus {
  confirmed,

  possibleEquivalent,

  noEquivalentFound,

  kernelModuleRequiresTargetBuild,

  thirdPartyUnverified,

  unknown,
}

class PackageMigrationItem {
  final String packageName;
  final String? installedVersion;
  final PackageMigrationStatus migrationStatus;
  final String? targetEquivalentName;
  final String? note;
  final bool isKernelModule;
  final bool isLuciExtension;
  final bool isThirdParty;

  const PackageMigrationItem({
    required this.packageName,
    this.installedVersion,
    required this.migrationStatus,
    this.targetEquivalentName,
    this.note,
    this.isKernelModule = false,
    this.isLuciExtension = false,
    this.isThirdParty = false,
  });
}

class PackageMigrationAnalysis {
  final PackageMigrationTransition transition;
  final List<PackageMigrationItem> packages;

  final bool targetPackageManagerKnown;

  final bool targetIndexConsulted;

  final String? targetIndexUnavailableReason;

  const PackageMigrationAnalysis({
    required this.transition,
    required this.packages,
    this.targetPackageManagerKnown = false,
    this.targetIndexConsulted = false,
    this.targetIndexUnavailableReason,
  });

  bool get isOpkgToApkTransition =>
      transition == PackageMigrationTransition.opkgToApk;

  List<PackageMigrationItem> get items => packages;

  String get summary {
    switch (transition) {
      case PackageMigrationTransition.opkgToApk:
        return 'The target firmware uses APK instead of OPKG. '
            'Installed OPKG packages will not carry over automatically. '
            'Review the list below and reinstall via APK after upgrade.';
      case PackageMigrationTransition.apkToOpkg:
        return 'The target firmware uses OPKG instead of APK. '
            'Installed APK packages will not carry over automatically. '
            'Review the list below and reinstall via OPKG after upgrade.';
      case PackageMigrationTransition.opkgToOpkg:
        return 'Both current and target firmware use OPKG. '
            'Installed packages will need to be reinstalled from the OPKG feed after upgrade.';
      case PackageMigrationTransition.apkToApk:
        return 'Both current and target firmware use APK. '
            'Installed packages will need to be reinstalled from the APK feed after upgrade.';
      case PackageMigrationTransition.mixedOrVendor:
        return 'Mixed or vendor-specific package environment detected. '
            'Package migration requires manual assessment.';
      case PackageMigrationTransition.unknown:
        return 'Target package manager is unknown. '
            'Package migration status cannot be assessed automatically.';
    }
  }

  List<PackageMigrationItem> get confirmed => packages
      .where((p) => p.migrationStatus == PackageMigrationStatus.confirmed)
      .toList();

  List<PackageMigrationItem> get needsAttention => packages
      .where((p) => p.migrationStatus != PackageMigrationStatus.confirmed)
      .toList();

  List<PackageMigrationItem> get kernelModules =>
      packages.where((p) => p.isKernelModule).toList();
}

enum UpgradeOperationPhase {
  idle,
  preparing,
  generatingBackup,
  uploadingFirmware,
  verifyingUpload,
  validatingImage,
  awaitingConfirmation,
  flashCommandSubmitted,
  flashAcceptedByRouter,
  routerBecomingUnavailable,
  waitingForReboot,
  reconnecting,
  reconnected,
  postUpgradeVerification,
  completed,
  failed,
  outcomeUnknown,
}

class PostUpgradeVerificationResult {
  final bool routerResponded;
  final DetectedValue<String> detectedFirmwareVersion;
  final DetectedValue<String> detectedBoardName;
  final bool versionMatchesExpected;
  final String? expectedVersion;
  final String? verificationNote;

  const PostUpgradeVerificationResult({
    required this.routerResponded,
    required this.detectedFirmwareVersion,
    required this.detectedBoardName,
    required this.versionMatchesExpected,
    this.expectedVersion,
    this.verificationNote,
  });
}

class FirmwareImageValidationResult {
  final ImageValidationStatus status;

  final String? commandOutput;

  final bool forceApplied;

  final String? forceExplanation;

  const FirmwareImageValidationResult({
    required this.status,
    this.commandOutput,
    this.forceApplied = false,
    this.forceExplanation,
  });

  bool get passed => status == ImageValidationStatus.passed;
  bool get failed => status == ImageValidationStatus.failed;
  bool get isInconclusive => status == ImageValidationStatus.inconclusive;
  bool get isUnsupported => status == ImageValidationStatus.unsupported;
  bool get wasRun => status != ImageValidationStatus.notRun;

  bool get isAcceptableForFlash =>
      status == ImageValidationStatus.passed ||
      status == ImageValidationStatus.inconclusive ||
      status == ImageValidationStatus.unsupported ||
      (status == ImageValidationStatus.failed && forceApplied);
}

enum UpgradeAvailabilityStatus {
  upgradeAvailable,

  currentVersionLatest,

  noMatchingImageFound,

  updateSourceUnavailable,

  compatibilityUnverifiable,

  currentVersionUnknown,

  unsupportedFirmwareSource,

  notChecked,
}

class FirmwareUpgradeAvailability {
  final UpgradeAvailabilityStatus status;

  final String? latestVersion;

  final String? currentVersion;

  final String? channelDescription;

  final String? explanation;

  final String? downloadUrl;

  final String? sha256;

  final int? imageSizeBytes;

  final String? imageName;

  final String? modelTitle;

  const FirmwareUpgradeAvailability({
    required this.status,
    this.latestVersion,
    this.currentVersion,
    this.channelDescription,
    this.explanation,
    this.downloadUrl,
    this.sha256,
    this.imageSizeBytes,
    this.imageName,
    this.modelTitle,
  });

  bool get isUpgradeAvailable =>
      status == UpgradeAvailabilityStatus.upgradeAvailable;
  bool get isCurrent =>
      status == UpgradeAvailabilityStatus.currentVersionLatest;

  String? get formattedImageSize {
    if (imageSizeBytes == null) return null;
    return '${(imageSizeBytes! / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
