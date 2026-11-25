// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async' show unawaited;
import 'dart:io' show Platform, File, Directory, Process;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';

enum OsHapticType { light, medium, heavy, selection }

enum StoragePermissionChoice { preferPublic, preferSandbox, cancelled }

class FileSaveResult {
  final String filePath;
  final bool isPublicDownloads;
  final String storageMethodLabel;

  FileSaveResult({
    required this.filePath,
    required this.isPublicDownloads,
    required this.storageMethodLabel,
  });
}

class OsPlatformIntegration {
  static Future<void> triggerHaptic(OsHapticType type) async {
    if (kIsWeb) return;
    try {
      switch (type) {
        case OsHapticType.light:
          await HapticFeedback.lightImpact();
          return;
        case OsHapticType.medium:
          await HapticFeedback.mediumImpact();
          return;
        case OsHapticType.heavy:
          await HapticFeedback.heavyImpact();
          return;
        case OsHapticType.selection:
          await HapticFeedback.selectionClick();
          return;
      }
    } catch (_) {}
  }

  static Future<void> copyToClipboard(
    BuildContext context, {
    required String text,
    required String label,
  }) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      await triggerHaptic(OsHapticType.light);
      if (context.mounted) {
        ksSay(context, 'Copied $label.');
      }
    } catch (e) {
      if (context.mounted) {
        ksSay(context, 'Couldn\'t copy $label.');
      }
    }
  }

  static Future<bool> openSystemSettings(BuildContext context) async {
    await triggerHaptic(OsHapticType.medium);
    bool launched = false;

    if (kIsWeb) return false;

    try {
      if (Platform.isAndroid) {
        launched = await LocalNetworkPermissionService.openAppSettings();
        if (!launched) {
          final intentUri = Uri.parse('package:com.perz3us.keystone');
          if (await canLaunchUrl(intentUri)) {
            launched = await launchUrl(intentUri);
          }
        }
      } else if (Platform.isIOS) {
        final intentUri = Uri.parse('app-settings:');
        if (await canLaunchUrl(intentUri)) {
          launched = await launchUrl(intentUri);
        }
      }
    } catch (_) {
      launched = false;
    }

    if (!launched && context.mounted) {
      ksSay(
        context,
        Platform.isIOS
            ? 'Open Settings, then Keystone, to change this.'
            : 'Open Settings, Apps, Keystone, Permissions to change this.',
      );
    }

    return launched;
  }

  static bool isPathPublic(String path) {
    if (kIsWeb) return false;
    if (Platform.isIOS) {
      return true;
    }
    final lower = path.toLowerCase();
    if (lower.contains('/android/data/') ||
        lower.contains('/data/user/') ||
        lower.contains('com.perz3us.keystone')) {
      return false;
    }
    return true;
  }

  static Future<Directory?> getPublicDownloadsDirectory() async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      final stdDownload = Directory('/storage/emulated/0/Download');
      if (!stdDownload.existsSync()) {
        try {
          stdDownload.createSync(recursive: true);
        } catch (_) {}
      }
      if (stdDownload.existsSync()) {
        return stdDownload;
      }

      final sdDownload = Directory('/sdcard/Download');
      if (sdDownload.existsSync()) {
        return sdDownload;
      }
    }

    try {
      final d = await getDownloadsDirectory();
      if (d != null) return d;
    } catch (_) {}

    try {
      if (Platform.isLinux || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) {
          final userDownload = Directory('$home/Downloads');
          if (userDownload.existsSync()) return userDownload;
        }
      } else if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final winDownload = Directory('$userProfile\\Downloads');
          if (winDownload.existsSync()) return winDownload;
        }
      }
    } catch (_) {}

    return null;
  }

  static Future<FileSaveResult?> saveDownloadedFileWithResult({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (kIsWeb) return null;

    if (Platform.isIOS) {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        if (!docsDir.existsSync()) docsDir.createSync(recursive: true);
        final file = File('${docsDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return FileSaveResult(
          filePath: file.path,
          isPublicDownloads: true,
          storageMethodLabel: 'Files App (On My iPhone / iPad)',
        );
      } catch (_) {
        try {
          final tempDir = await getTemporaryDirectory();
          if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes, flush: true);
          return FileSaveResult(
            filePath: file.path,
            isPublicDownloads: false,
            storageMethodLabel: 'Temporary Storage',
          );
        } catch (_) {}
        return null;
      }
    }

    try {
      Directory? targetDir = Directory('/storage/emulated/0/Download');
      if (!targetDir.existsSync()) {
        try {
          targetDir.createSync(recursive: true);
        } catch (_) {
          targetDir = await getPublicDownloadsDirectory();
        }
      }
      targetDir ??= await getPublicDownloadsDirectory();

      if (targetDir != null && targetDir.existsSync()) {
        final file = File('${targetDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        if (Platform.isAndroid) {
          try {
            await Process.run('am', [
              'broadcast',
              '-a',
              'android.intent.action.MEDIA_SCANNER_SCAN_FILE',
              '-d',
              'file://${file.path}',
            ]);
          } catch (_) {}
        }
        return FileSaveResult(
          filePath: file.path,
          isPublicDownloads: isPathPublic(file.path),
          storageMethodLabel: 'Public Downloads Folder',
        );
      }
    } catch (_) {}

    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        if (!extDir.existsSync()) extDir.createSync(recursive: true);
        final file = File('${extDir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        return FileSaveResult(
          filePath: file.path,
          isPublicDownloads: isPathPublic(file.path),
          storageMethodLabel: 'External App Storage',
        );
      }
    } catch (_) {}

    try {
      final docsDir = await getApplicationDocumentsDirectory();
      if (!docsDir.existsSync()) docsDir.createSync(recursive: true);
      final file = File('${docsDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return FileSaveResult(
        filePath: file.path,
        isPublicDownloads: Platform.isIOS,
        storageMethodLabel: Platform.isIOS
            ? 'Files App (On My iPhone / iPad)'
            : 'App Storage (Sandbox)',
      );
    } catch (_) {}

    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return FileSaveResult(
        filePath: file.path,
        isPublicDownloads: false,
        storageMethodLabel: 'Temporary Storage',
      );
    } catch (_) {}

    return null;
  }

  static Future<String?> saveDownloadedFile({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final res = await saveDownloadedFileWithResult(
      bytes: bytes,
      fileName: fileName,
    );
    return res?.filePath;
  }

  static Future<void> showFileDownloadedPrompt(
    BuildContext context,
    FileSaveResult saveResult, {
    String? title,
    String? fileLabel,
    IconData icon = Icons.check_circle_outline,
    Color accentColor = Colors.teal,
  }) async {
    if (!context.mounted) return;
    await triggerHaptic(OsHapticType.medium);
    if (!context.mounted) return;

    final file = File(saveResult.filePath);
    int fileSizeInBytes = 0;
    try {
      if (file.existsSync()) {
        fileSizeInBytes = file.lengthSync();
      }
    } catch (_) {}

    final formattedSize = StorageOverview.formatBytes(fileSizeInBytes);

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;
    final fileName = file.path.split(Platform.pathSeparator).last;
    final resolvedTitle =
        title ?? (l10n?.fileSavedSuccessfully ?? 'File saved');
    final resolvedFileLabel = fileLabel ?? (l10n?.filePathLabel ?? 'File Path');

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        icon: Icon(icon, color: accentColor, size: 40),
        title: Text(
          resolvedTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.6,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 20,
                          color: accentColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            fileName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          l10n?.fileSizePrefix(formattedSize) ??
                              'Size: $formattedSize',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                saveResult.isPublicDownloads
                                    ? Icons.folder_special_outlined
                                    : Icons.folder_outlined,
                                size: 11,
                                color: accentColor,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  Platform.isIOS
                                      ? saveResult.storageMethodLabel
                                      : (saveResult.isPublicDownloads
                                            ? (l10n?.backupPublicDownloadsFolder ??
                                                  saveResult.storageMethodLabel)
                                            : (l10n?.backupPrivateAppStorage ??
                                                  saveResult
                                                      .storageMethodLabel)),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: accentColor,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n?.backupSavedFileLocation ?? 'Saved File Location:',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: SelectableText(
                  saveResult.filePath,
                  style: GoogleFonts.geistMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Accessible in the Files app under: On My iPhone/iPad > Keystone',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n?.actionClose ?? 'Close'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(
                copyToClipboard(
                  context,
                  text: saveResult.filePath,
                  label: resolvedFileLabel,
                ),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n?.actionCopyFilePath ?? 'Copy File Path'),
          ),
        ],
      ),
    );
  }

  static Future<void> showBackupDownloadedPrompt(
    BuildContext context,
    FileSaveResult saveResult,
  ) async {
    final l10n = AppLocalizations.of(context);
    return showFileDownloadedPrompt(
      context,
      saveResult,
      title: l10n?.backupDownloadSuccessTitle ?? 'Backup saved',
      fileLabel: l10n?.backupPathLabel ?? 'Backup Path',
      icon: Icons.check_circle_outline,
      accentColor: Colors.teal,
    );
  }

  static Future<void> openSavedDirectoryOrFile(
    BuildContext context,
    String filePath,
  ) async {
    final isPublic = isPathPublic(filePath);
    final saveResult = FileSaveResult(
      filePath: filePath,
      isPublicDownloads: isPublic,
      storageMethodLabel: isPublic
          ? (Platform.isIOS
                ? 'Files App (On My iPhone / iPad)'
                : 'Public Downloads Folder')
          : (Platform.isIOS
                ? 'Files App (On My iPhone / iPad)'
                : 'Private App Storage (/Android/data/)'),
    );
    await showBackupDownloadedPrompt(context, saveResult);
  }

  static bool get isAndroidPlatform {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get supportsEdgeToEdge {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get supportsNativeOsToast {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static bool get isAndroid12OrHigher {
    if (kIsWeb) return false;
    if (!Platform.isAndroid) return false;
    try {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(
        r'(?:API|SDK)\s*(\d+)|Android\s*(\d+)',
      ).firstMatch(version);
      if (match != null) {
        final sdkStr = match.group(1);
        if (sdkStr != null) {
          final sdkInt = int.tryParse(sdkStr);
          if (sdkInt != null) return sdkInt >= 31;
        }
        final verStr = match.group(2);
        if (verStr != null) {
          final verInt = int.tryParse(verStr);
          if (verInt != null) return verInt >= 12;
        }
      }
    } catch (_) {}
    return true;
  }

  static double getSafeAreaTopPadding(
    BuildContext context, {
    double defaultOffset = 12.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final viewTopPadding = mediaQuery.viewPadding.top;
    final safeTop = topPadding > viewTopPadding ? topPadding : viewTopPadding;
    return safeTop + defaultOffset;
  }

  static double getSafeAreaBottomPadding(
    BuildContext context, {
    double defaultOffset = 24.0,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final viewBottomPadding = mediaQuery.viewPadding.bottom;
    final safeBottom = bottomPadding > viewBottomPadding
        ? bottomPadding
        : viewBottomPadding;
    return safeBottom + defaultOffset;
  }

  static String getPlatformInfo() {
    if (kIsWeb) return 'Web Preview Mode';
    if (Platform.isAndroid) {
      final ver = Platform.operatingSystemVersion.toLowerCase();
      final sysVer = Platform.version.toLowerCase();
      if (ver.contains('chrome') || sysVer.contains('chrome')) {
        return 'Chromebook (ChromeOS ARC)';
      }
      if (ver.contains('tv') ||
          ver.contains('atv') ||
          ver.contains('googletv')) {
        return 'Android TV Subsystem';
      }
      if (ver.contains('xr') ||
          ver.contains('spatial') ||
          ver.contains('vision')) {
        return 'Android XR Spatial Subsystem';
      }
      if (ver.contains('graphene') || sysVer.contains('graphene')) {
        return 'GrapheneOS Android Subsystem';
      }
      if (ver.contains('calyx') || sysVer.contains('calyx')) {
        return 'CalyxOS Android Subsystem';
      }
      if (ver.contains('lineage') || sysVer.contains('lineage')) {
        return 'LineageOS Android Subsystem';
      }
      if (ver.contains('fire') || sysVer.contains('fire')) {
        return 'Fire OS Subsystem';
      }
      if (ver.contains('harmony') || sysVer.contains('huawei')) {
        return 'HarmonyOS Android Runtime';
      }
      if (ver.contains('waydroid')) {
        return 'Waydroid Linux-Android Subsystem';
      }
      return 'Android (Phone / Tablet / Foldable)';
    }
    if (Platform.isIOS) {
      return 'Apple (iPhone / iPad / Apple Duo)';
    }
    if (Platform.isMacOS) {
      return 'macOS Desktop (Non-Target Host)';
    }
    if (Platform.isLinux) {
      return 'Linux Desktop (Development Preview)';
    }
    if (Platform.isWindows) {
      return 'Windows Desktop (Non-Target Host)';
    }
    return 'Host Environment';
  }

  static Future<void> exitApp({BuildContext? context}) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.perz3us.keystone/app_lifecycle');
        try {
          await platform.invokeMethod('exitApp');
          return;
        } catch (_) {}
      }
      await SystemNavigator.pop();
    } catch (_) {
      try {
        await SystemNavigator.pop();
      } catch (_) {}
    }
  }

  static Future<bool> minimizeApp() async {
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('com.perz3us.keystone/app_lifecycle');
        final res = await platform.invokeMethod<bool>('moveTaskToBack');
        return res ?? false;
      }
    } catch (_) {}
    return false;
  }
}
