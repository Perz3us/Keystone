// SPDX-License-Identifier: GPL-3.0-or-later

enum StorageDataSource { rpcJson, dfKBlocks, dfHuman }

class MountPointItem {
  final String mountPath;
  final String device;
  final String filesystemType;
  final int sizeBytes;
  final int usedBytes;
  final int availableBytes;
  final bool isReadOnly;

  const MountPointItem({
    required this.mountPath,
    required this.device,
    required this.filesystemType,
    required this.sizeBytes,
    required this.usedBytes,
    required this.availableBytes,
    this.isReadOnly = false,
  });

  factory MountPointItem.fromJson(
    Map<String, dynamic> json, {
    StorageDataSource dataSource = StorageDataSource.rpcJson,
    bool datasetHasByteScale = false,
  }) {
    final mount =
        json['mount']?.toString() ??
        json['target']?.toString() ??
        json['mountpoint']?.toString() ??
        json['dest']?.toString() ??
        json['path']?.toString() ??
        '/';
    final dev =
        json['device']?.toString() ??
        json['dev']?.toString() ??
        json['src']?.toString() ??
        json['source']?.toString() ??
        'unknown';

    String fs =
        json['fs']?.toString() ??
        json['fstype']?.toString() ??
        json['type']?.toString() ??
        json['filesystem']?.toString() ??
        '';

    if (fs.isEmpty || fs.toLowerCase() == 'unknown') {
      if (dev.contains('ubi')) {
        fs = 'ubifs';
      } else if (dev.contains('overlay') || mount.contains('overlay')) {
        fs = 'overlayfs';
      } else if (dev == 'tmpfs' || mount == '/tmp' || mount == '/dev') {
        fs = 'tmpfs';
      } else if (dev.contains('root') || mount == '/rom') {
        fs = 'squashfs';
      } else if (dev.contains('mtdblock')) {
        fs = 'jffs2';
      } else {
        fs = 'ext4';
      }
    }

    bool hasUnitSuffix = false;
    int parseNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) {
        final clean = val.replaceAll(',', '').trim();
        final lower = clean.toLowerCase();
        if (lower.endsWith('g') || lower.endsWith('gb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024 * 1024).toInt();
        }
        if (lower.endsWith('m') || lower.endsWith('mb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024).toInt();
        }
        if (lower.endsWith('k') || lower.endsWith('kb')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024).toInt();
        }
        if (lower.endsWith('b')) {
          hasUnitSuffix = true;
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return n.toInt();
        }
        return int.tryParse(clean) ?? (double.tryParse(clean)?.toInt() ?? 0);
      }
      return 0;
    }

    final int rawSize = parseNum(
      json['size'] ??
          json['total'] ??
          json['blocks'] ??
          json['sizeBytes'] ??
          json['bytes'] ??
          json['capacity'],
    );
    final int rawAvail = parseNum(
      json['avail'] ??
          json['available'] ??
          json['free'] ??
          json['availableBytes'] ??
          json['freeBytes'],
    );
    final int rawUsed = parseNum(json['used'] ?? json['usedBytes']);

    final bsize = parseNum(
      json['bsize'] ?? json['block_size'] ?? json['blockSize'],
    );
    final unitStr = json['unit']?.toString().toLowerCase() ?? '';

    final isExplicitBytes =
        hasUnitSuffix ||
        json.containsKey('sizeBytes') ||
        json.containsKey('bytes') ||
        json.containsKey('usedBytes') ||
        json.containsKey('availableBytes') ||
        json.containsKey('size_bytes') ||
        json.containsKey('used_bytes') ||
        json.containsKey('avail_bytes') ||
        json.containsKey('total_bytes') ||
        unitStr == 'bytes' ||
        unitStr == 'b';

    final options =
        json['options']?.toString() ??
        json['opts']?.toString() ??
        json['mode']?.toString() ??
        '';
    final optionsList = options.split(RegExp(r'[,\s]+'));
    final bool isExplicitRo =
        optionsList.contains('ro') ||
        json['read_only'] == true ||
        json['isReadOnly'] == true ||
        json['ro'] == true;
    final bool isRo =
        isExplicitRo || mount == '/rom' || fs.toLowerCase() == 'squashfs';

    final multiplier = determineByteMultiplier(
      rawSize: rawSize,
      rawUsed: rawUsed,
      rawAvail: rawAvail,
      bsize: bsize,
      hasExplicitByteKey: isExplicitBytes,
      hasUnitSuffix: hasUnitSuffix,
      unitStr: unitStr,
      mountPath: mount,
      dataSource: dataSource,
      datasetHasByteScale: datasetHasByteScale,
    );

    final int sizeBytes = rawSize * multiplier;
    int availBytes = rawAvail * multiplier;
    int usedBytes = rawUsed * multiplier;

    if (mount == '/rom' || fs.toLowerCase() == 'squashfs') {
      availBytes = 0;
      if (usedBytes == 0) {
        usedBytes = sizeBytes;
      }
    } else {
      if (usedBytes == 0 && sizeBytes > availBytes && availBytes > 0) {
        usedBytes = sizeBytes - availBytes;
      } else if (availBytes == 0 && sizeBytes > usedBytes && usedBytes > 0) {
        availBytes = sizeBytes - usedBytes;
      }
    }

    return MountPointItem(
      mountPath: mount,
      device: dev,
      filesystemType: fs,
      sizeBytes: sizeBytes,
      usedBytes: usedBytes,
      availableBytes: availBytes < 0 ? 0 : availBytes,
      isReadOnly: isRo,
    );
  }

  static int determineByteMultiplier({
    required int rawSize,
    required int rawUsed,
    required int rawAvail,
    required int bsize,
    required bool hasExplicitByteKey,
    required bool hasUnitSuffix,
    required String unitStr,
    required String mountPath,
    required StorageDataSource dataSource,
    bool datasetHasByteScale = false,
  }) {
    if (bsize > 0) {
      return bsize;
    }

    if (dataSource == StorageDataSource.rpcJson) {
      if (hasExplicitByteKey ||
          hasUnitSuffix ||
          unitStr == 'bytes' ||
          unitStr == 'b' ||
          datasetHasByteScale) {
        return 1;
      }
      if (rawSize > 0 && rawSize <= 8192) {
        return 1024 * 1024;
      }
      if (rawSize > 8192 && rawSize <= 1048576) {
        return 1024;
      }
      return 1;
    }

    if (hasExplicitByteKey ||
        hasUnitSuffix ||
        unitStr == 'bytes' ||
        unitStr == 'b') {
      return 1;
    }

    if (unitStr == 'kb' || unitStr == 'k' || unitStr == 'kblocks') {
      return 1024;
    }
    if (unitStr == 'mb' || unitStr == 'm') {
      return 1024 * 1024;
    }
    if (unitStr == 'gb' || unitStr == 'g') {
      return 1024 * 1024 * 1024;
    }

    if (rawSize <= 0) {
      return 1024;
    }

    if (dataSource == StorageDataSource.dfKBlocks) {
      return 1024;
    }

    if (dataSource == StorageDataSource.dfHuman) {
      return 1;
    }

    final bool isSystemMount =
        mountPath == '/' ||
        mountPath == '/overlay' ||
        mountPath == '/rom' ||
        mountPath == '/tmp' ||
        mountPath == '/dev';

    if (rawSize >= 1048576) {
      if (isSystemMount) {
        return 1;
      }
      final bool isExactMbMultiple = (rawSize % 1048576 == 0);
      final double ifKbToGb =
          (rawSize.toDouble() * 1024.0) / (1024.0 * 1024.0 * 1024.0);

      if (ifKbToGb > 100000.0 || (isExactMbMultiple && rawSize >= 16777216)) {
        return 1;
      }
      return 1;
    }

    if (rawSize > 0 && rawSize <= 8192) {
      if (rawSize == 16 ||
          rawSize == 32 ||
          rawSize == 64 ||
          rawSize == 128 ||
          rawSize == 256 ||
          rawSize == 384 ||
          rawSize == 512 ||
          rawSize == 1024 ||
          rawSize == 2048 ||
          rawSize == 4096 ||
          rawSize == 8192) {
        return 1024 * 1024;
      }
    }

    return 1024;
  }

  double get usedPercent {
    if (sizeBytes <= 0) return 0.0;
    return ((usedBytes / sizeBytes) * 100).clamp(0.0, 100.0);
  }

  bool get isOverlay =>
      mountPath == '/overlay' ||
      mountPath.contains('overlay') ||
      device.contains('overlay') ||
      device.contains('ubi');

  bool get isRoot =>
      mountPath == '/' ||
      mountPath == '/rom' ||
      device == '/dev/root' ||
      device.contains('root');

  bool get isTmp =>
      mountPath == '/tmp' ||
      mountPath == '/dev' ||
      mountPath.contains('/tmp') ||
      filesystemType == 'tmpfs' ||
      device == 'tmpfs';

  bool get isExternal {
    if (isTmp) return false;
    if (mountPath.startsWith('/proc') ||
        mountPath.startsWith('/sys') ||
        mountPath.startsWith('/dev/pts') ||
        mountPath == '/dev/shm') {
      return false;
    }

    if (mountPath == '/rom' || filesystemType.toLowerCase() == 'squashfs') {
      return false;
    }
    if (device == '/dev/root' ||
        device.contains('mtdblock') ||
        device.contains('ubi')) {
      return false;
    }

    final devLower = device.toLowerCase().trim();
    final mountLower = mountPath.toLowerCase().trim();
    final fsLower = filesystemType.toLowerCase().trim();

    if (mountLower == '/') {
      final isExternalExtroot =
          devLower.contains('/dev/sd') ||
          devLower.contains('/dev/nvme') ||
          RegExp(r'(^|/)sd[a-z][0-9]*').hasMatch(devLower) ||
          RegExp(r'(^|/)nvme[0-9]').hasMatch(devLower);
      return isExternalExtroot;
    }

    if (mountLower == '/overlay') {
      final isExternalExtroot =
          devLower.contains('/dev/sd') ||
          devLower.contains('/dev/nvme') ||
          RegExp(r'(^|/)sd[a-z][0-9]*').hasMatch(devLower) ||
          RegExp(r'(^|/)nvme[0-9]').hasMatch(devLower);
      return isExternalExtroot;
    }

    if (devLower.contains('/dev/sd') ||
        RegExp(r'(^|/)sd[a-z][0-9]*').hasMatch(devLower) ||
        devLower.contains('/dev/nvme') ||
        RegExp(r'(^|/)nvme[0-9]').hasMatch(devLower)) {
      return true;
    }

    if (devLower.contains('mmcblk1') ||
        (devLower.contains('mmcblk') &&
            (mountLower.startsWith('/mnt') ||
                mountLower.startsWith('/media')))) {
      return true;
    }

    if (devLower.startsWith('//') ||
        devLower.contains(':/') ||
        fsLower == 'cifs' ||
        fsLower == 'smbfs' ||
        fsLower == 'nfs' ||
        fsLower == 'nfs4' ||
        fsLower == 'sshfs') {
      return true;
    }

    if (mountLower.startsWith('/mnt/') ||
        mountLower == '/mnt' ||
        mountLower.startsWith('/media/') ||
        mountLower == '/media' ||
        mountLower.startsWith('/share/') ||
        mountLower.startsWith('/volume') ||
        mountLower.startsWith('/srv/')) {
      return true;
    }

    if (fsLower == 'ntfs' ||
        fsLower == 'ntfs3' ||
        fsLower == 'exfat' ||
        fsLower == 'vfat' ||
        fsLower == 'fat' ||
        fsLower == 'msdos' ||
        fsLower == 'fuseblk') {
      return true;
    }

    return false;
  }

  bool get isInbuilt => !isExternal && !isTmp;
}

class StorageOverview {
  final List<MountPointItem> mountPoints;

  const StorageOverview({required this.mountPoints});

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final double b = bytes.toDouble();
    if (b < 1024) {
      return '$bytes B';
    }
    final double kb = b / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final double mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  factory StorageOverview.fromRpcData(
    dynamic data, {
    bool isReviewerMode = false,
  }) {
    final list = <MountPointItem>[];

    int parseNum(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      if (val is String) {
        final clean = val.replaceAll(',', '').trim();
        if (clean.endsWith('G') ||
            clean.endsWith('GB') ||
            clean.endsWith('g') ||
            clean.endsWith('gb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024 * 1024).toInt();
        }
        if (clean.endsWith('M') ||
            clean.endsWith('MB') ||
            clean.endsWith('m') ||
            clean.endsWith('mb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024 * 1024).toInt();
        }
        if (clean.endsWith('K') ||
            clean.endsWith('KB') ||
            clean.endsWith('k') ||
            clean.endsWith('kb')) {
          final n =
              double.tryParse(clean.replaceAll(RegExp(r'[a-zA-Z]'), '')) ?? 0;
          return (n * 1024).toInt();
        }
        return int.tryParse(clean) ?? (double.tryParse(clean)?.toInt() ?? 0);
      }
      return 0;
    }

    if (data is String) {
      final rawLines = data.split('\n');
      final lines = <String>[];

      bool isHumanFormat = false;
      for (final l in rawLines) {
        if (l.contains('Size') || l.contains('Used') || l.contains('Avail')) {
          if (l.contains('Human') || l.contains('-h') || l.contains('Size')) {
            isHumanFormat = true;
          }
        }
      }

      String pendingDev = '';
      for (final l in rawLines) {
        final trimmed = l.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('Filesystem') ||
            trimmed.startsWith('Sys.') ||
            trimmed.startsWith('1K-blocks')) {
          continue;
        }

        final parts = trimmed.split(RegExp(r'\s+'));
        if (parts.length == 1 &&
            (parts[0].startsWith('/') ||
                parts[0].contains(':') ||
                parts[0] == 'tmpfs' ||
                parts[0].startsWith('overlay'))) {
          pendingDev = parts[0];
          continue;
        }
        if (pendingDev.isNotEmpty) {
          lines.add('$pendingDev $trimmed');
          pendingDev = '';
        } else {
          lines.add(trimmed);
        }
      }

      for (final line in lines) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;

        if (parts.length >= 3 &&
            int.tryParse(parts[1]) == null &&
            (parts[1].startsWith('/') || parts[1] == 'swap')) {
          final dev = parts[0];
          final target = parts[1];
          final fs = parts[2];

          if (target.startsWith('/proc') ||
              target.startsWith('/sys') ||
              target.startsWith('/dev/pts') ||
              target == '/dev/shm') {
            continue;
          }

          final options = parts.length > 3 ? parts[3] : '';
          final bool isRo =
              options.split(',').contains('ro') ||
              target == '/rom' ||
              fs == 'squashfs';

          list.add(
            MountPointItem(
              mountPath: target,
              device: dev,
              filesystemType: fs,
              sizeBytes: 0,
              usedBytes: 0,
              availableBytes: 0,
              isReadOnly: isRo,
            ),
          );
          continue;
        }

        int percentIdx = -1;
        for (int i = 0; i < parts.length; i++) {
          if (parts[i].endsWith('%') || parts[i].contains('%')) {
            percentIdx = i;
            break;
          }
        }

        if (percentIdx >= 1) {
          final dev = parts[0];
          String fs = '';
          int blockIdx = 1;

          if (percentIdx >= 5 &&
              int.tryParse(parts[1]) == null &&
              !parts[1].contains('%')) {
            fs = parts[1];
            blockIdx = 2;
          }

          final sizeRawStr = parts[blockIdx];
          final hasUnitSuffix = RegExp(
            r'[a-zA-Z]$',
          ).hasMatch(sizeRawStr.trim());
          final lineDataSource = (hasUnitSuffix || isHumanFormat)
              ? StorageDataSource.dfHuman
              : StorageDataSource.dfKBlocks;

          final int rawSize = parseNum(sizeRawStr);
          final int rawUsed = percentIdx - blockIdx >= 2
              ? parseNum(parts[blockIdx + 1])
              : 0;
          final int rawAvail = percentIdx - blockIdx >= 3
              ? parseNum(parts[blockIdx + 2])
              : 0;

          final target = parts.sublist(percentIdx + 1).join(' ');
          final mountPath = target.isEmpty ? '/' : target;

          final multiplier = MountPointItem.determineByteMultiplier(
            rawSize: rawSize,
            rawUsed: rawUsed,
            rawAvail: rawAvail,
            bsize: 0,
            hasExplicitByteKey: hasUnitSuffix,
            hasUnitSuffix: hasUnitSuffix,
            unitStr: hasUnitSuffix ? 'human' : '',
            mountPath: mountPath,
            dataSource: lineDataSource,
          );

          final int sizeBytes = rawSize * multiplier;
          int usedBytes = rawUsed * multiplier;
          int availBytes = rawAvail * multiplier;

          if (fs.isEmpty || fs.toLowerCase() == 'unknown') {
            if (dev.contains('ubi')) {
              fs = 'ubifs';
            } else if (dev.contains('overlay') ||
                mountPath.contains('overlay')) {
              fs = 'overlayfs';
            } else if (dev == 'tmpfs' ||
                mountPath == '/tmp' ||
                mountPath == '/dev') {
              fs = 'tmpfs';
            } else if (dev.contains('root') || mountPath == '/rom') {
              fs = 'squashfs';
            } else if (dev.contains('mtdblock')) {
              fs = 'jffs2';
            } else {
              fs = 'ext4';
            }
          }

          if (mountPath == '/rom' || fs.toLowerCase() == 'squashfs') {
            availBytes = 0;
            if (usedBytes == 0) {
              usedBytes = sizeBytes;
            }
          }

          list.add(
            MountPointItem(
              mountPath: mountPath,
              device: dev,
              filesystemType: fs,
              sizeBytes: sizeBytes,
              usedBytes: usedBytes,
              availableBytes: availBytes < 0 ? 0 : availBytes,
            ),
          );
        }
      }
    } else if (data is List) {
      bool hasByteScale = false;
      for (final item in data) {
        if (item is Map) {
          final s = parseNum(
            item['size'] ?? item['total'] ?? item['sizeBytes'],
          );
          if (s > 1048576) {
            hasByteScale = true;
            break;
          }
        }
      }
      for (final item in data) {
        if (item is Map) {
          list.add(
            MountPointItem.fromJson(
              Map<String, dynamic>.from(item),
              dataSource: StorageDataSource.rpcJson,
              datasetHasByteScale: hasByteScale,
            ),
          );
        }
      }
    } else if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);

      if (mapData['root'] is Map) {
        final rootMap = Map<String, dynamic>.from(mapData['root']);
        final totalKb = parseNum(rootMap['total']);
        final usedKb = parseNum(rootMap['used']);
        final availKb = parseNum(rootMap['avail'] ?? rootMap['free']);
        list.add(
          MountPointItem(
            mountPath: '/',
            device: '/dev/root',
            filesystemType: 'overlayfs',
            sizeBytes: totalKb * 1024,
            usedBytes: usedKb * 1024,
            availableBytes: availKb * 1024,
          ),
        );
      }
      if (mapData['tmp'] is Map) {
        final tmpMap = Map<String, dynamic>.from(mapData['tmp']);
        final totalKb = parseNum(tmpMap['total']);
        final usedKb = parseNum(tmpMap['used']);
        final availKb = parseNum(tmpMap['avail'] ?? tmpMap['free']);
        list.add(
          MountPointItem(
            mountPath: '/tmp',
            device: 'tmpfs',
            filesystemType: 'tmpfs',
            sizeBytes: totalKb * 1024,
            usedBytes: usedKb * 1024,
            availableBytes: availKb * 1024,
          ),
        );
      }

      final inner =
          mapData['mountPoints'] ??
          mapData['mounts'] ??
          mapData['result'] ??
          mapData['values'] ??
          mapData['data'] ??
          mapData['fs'];

      bool hasByteScale = false;
      if (inner is List) {
        for (final item in inner) {
          if (item is Map) {
            final s = parseNum(
              item['size'] ?? item['total'] ?? item['sizeBytes'],
            );
            if (s > 1048576) {
              hasByteScale = true;
              break;
            }
          }
        }
        for (final item in inner) {
          if (item is Map) {
            list.add(
              MountPointItem.fromJson(
                Map<String, dynamic>.from(item),
                dataSource: StorageDataSource.rpcJson,
                datasetHasByteScale: hasByteScale,
              ),
            );
          }
        }
      } else if (inner is Map) {
        inner.forEach((_, val) {
          if (val is Map) {
            final s = parseNum(val['size'] ?? val['total'] ?? val['sizeBytes']);
            if (s > 1048576) hasByteScale = true;
          }
        });
        final targetMap = Map<String, dynamic>.from(inner);
        targetMap.forEach((key, val) {
          if (val is Map) {
            final copy = Map<String, dynamic>.from(val);
            if (copy['mount'] == null &&
                copy['target'] == null &&
                copy['mountpoint'] == null &&
                copy['dest'] == null) {
              copy['mount'] = key;
            }
            list.add(
              MountPointItem.fromJson(
                copy,
                dataSource: StorageDataSource.rpcJson,
                datasetHasByteScale: hasByteScale,
              ),
            );
          }
        });
      } else {
        mapData.forEach((_, val) {
          if (val is Map) {
            final s = parseNum(val['size'] ?? val['total'] ?? val['sizeBytes']);
            if (s > 1048576) hasByteScale = true;
          }
        });
        mapData.forEach((key, val) {
          if (key == 'root' || key == 'tmp') return;
          if (val is Map) {
            final copy = Map<String, dynamic>.from(val);
            final typeStr = copy['.type']?.toString();
            if (typeStr != null && typeStr != 'mount' && typeStr != 'swap') {
              return;
            }
            if (copy['mount'] == null &&
                copy['target'] == null &&
                copy['mountpoint'] == null &&
                copy['dest'] == null) {
              copy['mount'] = key;
            }
            list.add(
              MountPointItem.fromJson(
                copy,
                dataSource: StorageDataSource.rpcJson,
                datasetHasByteScale: hasByteScale,
              ),
            );
          }
        });
      }
    }

    if (isReviewerMode && list.isEmpty) {
      list.addAll([
        const MountPointItem(
          mountPath: '/',
          device: '/dev/root',
          filesystemType: 'squashfs',
          sizeBytes: 134217728,
          usedBytes: 47185920,
          availableBytes: 87031808,
        ),
        const MountPointItem(
          mountPath: '/overlay',
          device: '/dev/mtdblock6',
          filesystemType: 'ext4',
          sizeBytes: 67108864,
          usedBytes: 16777216,
          availableBytes: 50331648,
        ),
        const MountPointItem(
          mountPath: '/tmp',
          device: 'tmpfs',
          filesystemType: 'tmpfs',
          sizeBytes: 268435456,
          usedBytes: 2097152,
          availableBytes: 266338304,
        ),
      ]);
    }

    return StorageOverview(mountPoints: list);
  }

  MountPointItem? get rootFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/') return m;
    }
    for (final m in mountPoints) {
      if (m.mountPath == '/rom' || m.device == '/dev/root') return m;
    }
    for (final m in mountPoints) {
      if (m.isRoot) return m;
    }
    return mountPoints.first;
  }

  MountPointItem? get overlayFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/overlay' ||
          m.device.contains('ubi') ||
          m.device.contains('overlay')) {
        return m;
      }
    }
    return null;
  }

  MountPointItem? get tmpFs {
    if (mountPoints.isEmpty) return null;
    for (final m in mountPoints) {
      if (m.mountPath == '/tmp') return m;
    }
    for (final m in mountPoints) {
      if (m.isTmp) return m;
    }
    return null;
  }

  List<MountPointItem> get priorityDisplayMounts {
    if (mountPoints.isEmpty) return [];

    final selected = <MountPointItem>[];

    MountPointItem? overlayItem;
    for (final m in mountPoints) {
      if (m.mountPath == '/overlay' || m.isOverlay) {
        overlayItem = m;
        break;
      }
    }
    overlayItem ??= overlayFs;
    if (overlayItem != null && mountPoints.contains(overlayItem)) {
      selected.add(overlayItem);
    }

    MountPointItem? tmpItem;
    for (final m in mountPoints) {
      if ((m.mountPath == '/tmp' || m.isTmp) && !selected.contains(m)) {
        tmpItem = m;
        break;
      }
    }
    tmpItem ??= tmpFs;
    if (tmpItem != null &&
        !selected.contains(tmpItem) &&
        mountPoints.contains(tmpItem)) {
      selected.add(tmpItem);
    }

    for (final m in mountPoints) {
      if (selected.length >= 2) break;
      if (!selected.contains(m)) {
        selected.add(m);
      }
    }

    return selected.take(2).toList();
  }

  List<MountPointItem> get mountedDevices {
    return mountPoints;
  }

  bool get hasExternalStorage => externalMounts.isNotEmpty;

  List<MountPointItem> get externalMounts =>
      mountPoints.where((m) => m.isExternal).toList();

  List<MountPointItem> get inbuiltMounts =>
      mountPoints.where((m) => m.isInbuilt).toList();

  int get externalStorageTotalBytes =>
      externalMounts.fold<int>(0, (sum, m) => sum + m.sizeBytes);

  int get externalStorageUsedBytes =>
      externalMounts.fold<int>(0, (sum, m) => sum + m.usedBytes);

  int get externalStorageAvailableBytes =>
      externalMounts.fold<int>(0, (sum, m) => sum + m.availableBytes);

  int get inbuiltStorageTotalBytes {
    final primary = overlayFs ?? rootFs;
    final primarySize = primary?.sizeBytes ?? 0;
    int extraSize = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          !m.isExternal &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraSize += m.sizeBytes;
      }
    }
    return primarySize + extraSize;
  }

  int get inbuiltStorageUsedBytes {
    final primary = overlayFs ?? rootFs;
    final primaryUsed = primary?.usedBytes ?? 0;
    int extraUsed = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          !m.isExternal &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraUsed += m.usedBytes;
      }
    }
    return primaryUsed + extraUsed;
  }

  int get totalSizeBytes {
    final primary = overlayFs ?? rootFs;
    final primarySize = primary?.sizeBytes ?? 0;
    int extraSize = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraSize += m.sizeBytes;
      }
    }
    return primarySize + extraSize;
  }

  int get totalUsedBytes {
    final primary = overlayFs ?? rootFs;
    final primaryUsed = primary?.usedBytes ?? 0;
    int extraUsed = 0;
    for (final m in mountPoints) {
      if (!m.isTmp &&
          m != primary &&
          m.mountPath != '/' &&
          m.mountPath != '/rom' &&
          m.mountPath != '/overlay') {
        extraUsed += m.usedBytes;
      }
    }
    return primaryUsed + extraUsed;
  }

  double get overallUsedPercent {
    final total = totalSizeBytes;
    if (total <= 0) return 0.0;
    return ((totalUsedBytes / total) * 100).clamp(0.0, 100.0);
  }
}
