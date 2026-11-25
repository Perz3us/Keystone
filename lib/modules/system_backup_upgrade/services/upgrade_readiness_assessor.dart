// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/router_upgrade_scan.dart';
import '../models/upgrade_models.dart';

class UpgradeReadinessAssessor {
  const UpgradeReadinessAssessor();

  UpgradeReadinessReport assess({
    required RouterUpgradeScan scan,
    required String? imageFileName,
    required int? imageSizeBytes,
    required FirmwareImageValidationResult imageValidation,
    required bool keepSettings,
    required bool forceUpgrade,
    required bool backupWasGenerated,
  }) {
    final checks = <ReadinessCheckItem>[];

    if (scan.isStale) {
      checks.add(
        const ReadinessCheckItem(
          id: 'scan_stale',
          title: 'Router scan data is outdated',
          description:
              'The router information was collected more than 5 minutes ago. '
              'Scan again before flashing so the numbers '
              'and configuration are current.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }
    if (scan.isPartial) {
      checks.add(
        ReadinessCheckItem(
          id: 'scan_partial',
          title: 'Router scan was incomplete',
          description:
              'Some probes failed during router scan: ${scan.partialScanReason ?? 'unknown reason'}. '
              'The result may be wrong.',
          severity: ReadinessCheckSeverity.warning,
          detail: scan.partialScanReason,
        ),
      );
    }

    if (imageFileName == null || imageSizeBytes == null) {
      checks.add(
        const ReadinessCheckItem(
          id: 'no_image_selected',
          title: 'No firmware image selected',
          description: 'Pick a sysupgrade image first.',
          severity: ReadinessCheckSeverity.blocking,
        ),
      );
    } else {
      checks.add(
        ReadinessCheckItem(
          id: 'image_selected',
          title: 'Firmware image selected',
          description:
              'Image selected: $imageFileName '
              '(${_formatBytes(imageSizeBytes)})',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    if (imageValidation.status == ImageValidationStatus.notRun) {
      checks.add(
        const ReadinessCheckItem(
          id: 'validation_not_run',
          title: 'Image compatibility test not run',
          description:
              'sysupgrade -t has not been run. Be careful, '
              'the wrong image can stop the router from starting.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.passed) {
      checks.add(
        ReadinessCheckItem(
          id: 'validation_passed',
          title: 'Image compatibility test passed',
          description: 'sysupgrade -t reported a valid image (exit code 0).',
          severity: ReadinessCheckSeverity.info,
          detail: imageValidation.commandOutput,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.failed) {
      if (forceUpgrade && imageValidation.forceApplied) {
        checks.add(
          ReadinessCheckItem(
            id: 'validation_failed_forced',
            title: 'Image check failed, but force is on',
            description:
                'sysupgrade -t indicated an incompatible or invalid image, '
                'but the force upgrade option (-F) is enabled. '
                'The wrong image can break the router for good.',
            severity: ReadinessCheckSeverity.warning,
            detail: imageValidation.commandOutput,
            canForce: true,
          ),
        );
      } else {
        checks.add(
          ReadinessCheckItem(
            id: 'validation_failed',
            title: 'Image compatibility test failed',
            description:
                'sysupgrade -t reported this image as incompatible or invalid. '
                'Don\'t flash it. Check that it\'s the right '
                'sysupgrade image for your router model and board.',
            severity: ReadinessCheckSeverity.blocking,
            detail: imageValidation.commandOutput,
            canForce: true,
          ),
        );
      }
    } else if (imageValidation.status == ImageValidationStatus.inconclusive) {
      checks.add(
        ReadinessCheckItem(
          id: 'validation_inconclusive',
          title: 'Image check gave no clear answer',
          description:
              'sysupgrade -t was executed but the exit code could not be '
              'reliably obtained. The image may or may not be compatible. '
              'Only go on if you know it fits this router.',
          severity: ReadinessCheckSeverity.warning,
          detail: imageValidation.commandOutput,
        ),
      );
    } else if (imageValidation.status == ImageValidationStatus.unsupported) {
      checks.add(
        const ReadinessCheckItem(
          id: 'validation_unsupported',
          title: 'Image compatibility test not supported',
          description:
              'sysupgrade -t is not available on this router. '
              'Keystone can\'t check the image. '
              'Make sure it fits your router model and board.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    if (scan.tmpAvailableBytes.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'tmp_space_unknown',
          title: '/tmp available space unknown',
          description:
              'Available space in /tmp (where the firmware image is stored '
              'before flashing) couldn\'t be read. Make sure there is '
              'enough room first.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (imageSizeBytes != null) {
      final available = scan.tmpAvailableBytes.value!;
      final required = imageSizeBytes + 2 * 1024 * 1024;
      if (available < required) {
        checks.add(
          ReadinessCheckItem(
            id: 'tmp_insufficient',
            title: 'Not enough room in /tmp for the image',
            description:
                'The image requires ${_formatBytes(imageSizeBytes)} plus '
                '2 MB headroom. Only ${_formatBytes(available)} is available '
                'in /tmp. Free space or use a different router with more RAM.',
            severity: ReadinessCheckSeverity.blocking,
            detail:
                'Available: ${_formatBytes(available)}, '
                'Required: ${_formatBytes(required)}',
          ),
        );
      } else {
        checks.add(
          ReadinessCheckItem(
            id: 'tmp_space_ok',
            title: '/tmp has sufficient space',
            description:
                '${_formatBytes(available)} free, '
                'enough for this image (${_formatBytes(imageSizeBytes)}).',
            severity: ReadinessCheckSeverity.info,
          ),
        );
      }
    }

    if (scan.hasSysupgrade.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_unknown',
          title: 'sysupgrade availability unknown',
          description:
              'Could not determine whether sysupgrade is available on this router.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else if (scan.hasSysupgrade.value == false) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_unavailable',
          title: 'sysupgrade not available',
          description:
              'sysupgrade was not detected on this router. '
              'Firmware flashing via this method is not supported.',
          severity: ReadinessCheckSeverity.blocking,
        ),
      );
    }

    if (!backupWasGenerated) {
      checks.add(
        const ReadinessCheckItem(
          id: 'no_backup',
          title: 'No configuration backup generated',
          description:
              'A configuration backup has not been downloaded in this session. '
              'If settings are lost after flashing, there will be no backup to '
              'restore from. Generate a backup before flashing.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else {
      checks.add(
        const ReadinessCheckItem(
          id: 'backup_generated',
          title: 'Configuration backup has been downloaded',
          description:
              'A configuration backup was downloaded in this session. '
              'Keep it in a safe location for recovery.',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    if (keepSettings) {
      checks.add(
        const ReadinessCheckItem(
          id: 'keep_settings_on',
          title: 'Settings preservation enabled (-k)',
          description:
              'Network, Wi-Fi, and user configuration will be retained '
              'during upgrade. Note: preserved settings may not be fully '
              'compatible across major firmware releases or distribution changes.',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    } else {
      checks.add(
        const ReadinessCheckItem(
          id: 'keep_settings_off',
          title: 'Settings preservation disabled (clean install)',
          description:
              'All configuration will be erased. The router will return to '
              'firmware defaults after flashing. Ensure you have a backup '
              'or can reconfigure the router manually.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    if (forceUpgrade) {
      checks.add(
        const ReadinessCheckItem(
          id: 'force_upgrade',
          title: 'Force upgrade mode enabled (-F)',
          description:
              'Force skips the board check and '
              'the image check. The router may not '
              'start if the image is wrong. Use it only '
              'if you are sure the image fits.',
          severity: ReadinessCheckSeverity.warning,
          canForce: true,
        ),
      );
    }

    if (scan.boardName.isUnknown) {
      checks.add(
        const ReadinessCheckItem(
          id: 'board_unknown',
          title: 'Router board identity unknown',
          description:
              'The router\'s board name could not be detected. '
              'This means compatibility between the selected image and the '
              'actual hardware cannot be verified.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    } else {
      checks.add(
        ReadinessCheckItem(
          id: 'board_known',
          title: 'Router board identified',
          description:
              'Board: ${scan.boardName.value} (${scan.boardName.confidence.name})',
          severity: ReadinessCheckSeverity.info,
        ),
      );
    }

    checks.add(
      const ReadinessCheckItem(
        id: 'power_warning',
        title: 'Do not interrupt power or connectivity during flash',
        description:
            'Disconnecting power, Ethernet, or the app during firmware '
            'writing can break the router for good. Make sure it '
            'has steady power first.',
        severity: ReadinessCheckSeverity.info,
      ),
    );

    if (scan.hasSysupgradeTest.value == false) {
      checks.add(
        const ReadinessCheckItem(
          id: 'sysupgrade_test_unsupported',
          title: 'Image pre-validation (sysupgrade -t) not supported',
          description:
              'This router does not support the sysupgrade -t compatibility '
              'test. Image compatibility cannot be verified before flashing.',
          severity: ReadinessCheckSeverity.warning,
        ),
      );
    }

    return UpgradeReadinessReport(
      checks: checks,
      basedOnStaleData: scan.isStale,
      isPartial: scan.isPartial,
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }
}
