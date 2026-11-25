// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Robust External Storage Detection - Live Router Payload', () {
    test(
      '10.0.0.1 Payload: Detects external SSD on /dev/sda2 without confusing internal flash',
      () {
        final payload = [
          {
            "device": "/dev/root",
            "mount": "/rom",
            "size": 16515072,
            "avail": 0,
            "free": 0,
          },
          {
            "device": "tmpfs",
            "mount": "/tmp",
            "size": 126009344,
            "avail": 123916288,
            "free": 123916288,
          },
          {
            "device": "/dev/ubi0_1",
            "mount": "/overlay",
            "size": 55664640,
            "avail": 18579456,
            "free": 21463040,
          },
          {
            "device": "overlayfs:/overlay",
            "mount": "/",
            "size": 55664640,
            "avail": 18579456,
            "free": 21463040,
          },
          {
            "device": "tmpfs",
            "mount": "/dev",
            "size": 524288,
            "avail": 524288,
            "free": 524288,
          },
          {
            "device": "/dev/sda2",
            "mount": "/mnt/ssd",
            "size": 488992784384,
            "avail": 483994144768,
            "free": 488990511104,
          },
        ];

        final overview = StorageOverview.fromRpcData(payload);

        expect(overview.hasExternalStorage, isTrue);
        expect(overview.externalMounts.length, equals(1));

        final externalItem = overview.externalMounts.first;
        expect(externalItem.mountPath, equals('/mnt/ssd'));
        expect(externalItem.device, equals('/dev/sda2'));
        expect(externalItem.isExternal, isTrue);
        expect(externalItem.isInbuilt, isFalse);

        expect(overview.rootFs, isNotNull);
        expect(overview.rootFs!.isExternal, isFalse);
        expect(overview.rootFs!.isInbuilt, isTrue);

        expect(overview.overlayFs, isNotNull);
        expect(overview.overlayFs!.isExternal, isFalse);
        expect(overview.overlayFs!.isInbuilt, isTrue);
        expect(overview.overlayFs!.mountPath, equals('/overlay'));
        expect(overview.overlayFs!.device, equals('/dev/ubi0_1'));

        expect(overview.externalStorageTotalBytes, equals(488992784384));
        expect(overview.inbuiltStorageTotalBytes, equals(55664640));
        expect(overview.totalSizeBytes, equals(55664640 + 488992784384));
      },
    );

    test(
      '192.168.1.1 Payload: Archer C60 on-board flash reports 0 external storage',
      () {
        final payload = [
          {
            "device": "/dev/root",
            "mount": "/rom",
            "size": 4980736,
            "avail": 0,
            "free": 0,
          },
          {
            "device": "tmpfs",
            "mount": "/tmp",
            "size": 28594176,
            "avail": 28291072,
            "free": 28291072,
          },
          {
            "device": "/dev/mtdblock6",
            "mount": "/overlay",
            "size": 393216,
            "avail": 110592,
            "free": 110592,
          },
          {
            "device": "overlayfs:/overlay",
            "mount": "/",
            "size": 393216,
            "avail": 110592,
            "free": 110592,
          },
          {
            "device": "tmpfs",
            "mount": "/dev",
            "size": 524288,
            "avail": 524288,
            "free": 524288,
          },
        ];

        final overview = StorageOverview.fromRpcData(payload);

        expect(overview.hasExternalStorage, isFalse);
        expect(overview.externalMounts, isEmpty);
        expect(overview.externalStorageTotalBytes, equals(0));
        expect(overview.inbuiltStorageTotalBytes, equals(393216));
        expect(overview.totalSizeBytes, equals(393216));

        for (final m in overview.mountPoints) {
          expect(m.isExternal, isFalse);
        }
      },
    );

    test(
      'Detects USB drives, NVMe SSDs, network CIFS/NFS shares, and external SD cards',
      () {
        final testCases = [
          {
            'device': '/dev/sdb1',
            'mount': '/mnt/usb',
            'fs': 'vfat',
            'sizeBytes': 32000000000,
          },
          {
            'device': '/dev/nvme0n1p1',
            'mount': '/mnt/fast_nvme',
            'fs': 'ext4',
            'sizeBytes': 1000000000000,
          },
          {
            'device': '//192.168.1.100/Media',
            'mount': '/mnt/media',
            'fs': 'cifs',
            'sizeBytes': 4000000000000,
          },
          {
            'device': '192.168.1.100:/export/data',
            'mount': '/mnt/nfs_data',
            'fs': 'nfs',
            'sizeBytes': 2000000000000,
          },
          {
            'device': '/dev/mmcblk1p1',
            'mount': '/mnt/sdcard',
            'fs': 'exfat',
            'sizeBytes': 64000000000,
          },
        ];

        for (final tc in testCases) {
          final item = MountPointItem.fromJson(tc);
          expect(
            item.isExternal,
            isTrue,
            reason: 'Failed for ${tc["device"]} at ${tc["mount"]}',
          );
          expect(item.isInbuilt, isFalse);
        }
      },
    );

    test(
      'Extroot: Detects external USB drive backing /overlay as external',
      () {
        final extrootPayload = [
          {'device': '/dev/root', 'mount': '/rom', 'size': 16000000},
          {
            'device': '/dev/sda1',
            'mount': '/overlay',
            'size': 64000000000,
            'used': 2000000000,
            'avail': 62000000000,
          },
          {
            'device': 'overlayfs:/overlay',
            'mount': '/',
            'size': 64000000000,
            'used': 2000000000,
            'avail': 62000000000,
          },
        ];

        final overview = StorageOverview.fromRpcData(extrootPayload);
        expect(overview.hasExternalStorage, isTrue);
        expect(
          overview.externalMounts.any((m) => m.mountPath == '/overlay'),
          isTrue,
        );
      },
    );

    test(
      'Internal eMMC: Correctly identifies on-board eMMC rootfs as inbuilt, not external',
      () {
        final emmcPayload = [
          {'device': '/dev/mmcblk0p1', 'mount': '/boot', 'size': 67108864},
          {
            'device': '/dev/mmcblk0p2',
            'mount': '/',
            'size': 8589934592,
            'used': 1073741824,
            'avail': 7516192768,
          },
        ];

        final overview = StorageOverview.fromRpcData(emmcPayload);
        expect(overview.hasExternalStorage, isFalse);
        expect(overview.rootFs!.isInbuilt, isTrue);
        expect(overview.rootFs!.isExternal, isFalse);
      },
    );
  });

  group('Storage Monitoring UI & Badge Rendering', () {});
}
