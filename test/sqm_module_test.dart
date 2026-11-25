// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/storage_monitoring/models/storage_info.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';

void main() {
  group('SqmQueue Model', () {
    test('Parses from standard UCI JSON', () {
      final uciJson = {
        '.type': 'queue',
        '.name': 'eth1',
        'enabled': '1',
        'interface': 'pppoe-wan',
        'download': '100000',
        'upload': '20000',
        'qdisc': 'cake',
        'script': 'piece_of_cake.qos',
        'linklayer': 'ethernet',
        'overhead': '44',
        'qdisc_advanced': '1',
        'squash_dscp': '1',
        'squash_ingress': '1',
        'ingress_ecn': 'ECN',
        'egress_ecn': 'NOECN',
        'debug_logging': '0',
        'verbosity': '5',
      };

      final queue = SqmQueue.fromUci('eth1', uciJson);

      expect(queue.name, equals('eth1'));
      expect(queue.enabled, isTrue);
      expect(queue.interface, equals('pppoe-wan'));
      expect(queue.download, equals(100000));
      expect(queue.downloadMbps, equals(100.0));
      expect(queue.upload, equals(20000));
      expect(queue.uploadMbps, equals(20.0));
      expect(queue.hasIngressShaping, isTrue);
      expect(queue.hasEgressShaping, isTrue);
      expect(queue.qdisc, equals('cake'));
      expect(queue.script, equals('piece_of_cake.qos'));
      expect(queue.linklayer, equals('ethernet'));
      expect(queue.overhead, equals(44));
      expect(queue.qdiscAdvanced, isTrue);
      expect(queue.squashDscp, isTrue);
      expect(queue.squashIngress, isTrue);
      expect(queue.ingressEcn, equals('ECN'));
      expect(queue.egressEcn, equals('NOECN'));
      expect(queue.debugLogging, isFalse);
    });

    test('toUciParams serializes with advanced flags', () {
      const queue = SqmQueue(
        name: 'eth1',
        enabled: true,
        interface: 'eth1',
        download: 50000,
        upload: 10000,
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'ethernet',
        overhead: 34,
        qdiscAdvanced: true,
        squashDscp: true,
        squashIngress: false,
        ingressEcn: 'ECN',
        egressEcn: 'ECN',
        debugLogging: false,
      );

      final params = queue.toUciParams();

      expect(params['enabled'], equals('1'));
      expect(params['interface'], equals('eth1'));
      expect(params['download'], equals('50000'));
      expect(params['upload'], equals('10000'));
      expect(params['qdisc'], equals('cake'));
      expect(params['script'], equals('piece_of_cake.qos'));
      expect(params['linklayer'], equals('ethernet'));
      expect(params['overhead'], equals('34'));
      expect(params['qdisc_advanced'], equals('1'));
      expect(params['squash_dscp'], equals('1'));
      expect(params['squash_ingress'], equals('0'));
      expect(params['ingress_ecn'], equals('ECN'));
      expect(params['egress_ecn'], equals('ECN'));
    });

    test('toUciParams sets qdisc_advanced to 0 when disabled', () {
      const queue = SqmQueue(
        name: 'eth1',
        enabled: false,
        interface: 'wan',
        download: 0,
        upload: 0,
        qdiscAdvanced: false,
      );

      final params = queue.toUciParams();

      expect(params['enabled'], equals('0'));
      expect(params['qdisc_advanced'], equals('0'));
      expect(params.containsKey('squash_dscp'), isFalse);
      expect(params.containsKey('ingress_ecn'), isFalse);
    });

    test('copyWith overrides specified attributes', () {
      const original = SqmQueue(
        name: 'eth1',
        interface: 'wan',
        download: 10000,
        upload: 5000,
      );

      final modified = original.copyWith(
        download: 20000,
        enabled: false,
        qdisc: 'fq_codel',
      );

      expect(modified.name, equals('eth1'));
      expect(modified.interface, equals('wan'));
      expect(modified.download, equals(20000));
      expect(modified.downloadMbps, equals(20.0));
      expect(modified.upload, equals(5000));
      expect(modified.enabled, isFalse);
      expect(modified.qdisc, equals('fq_codel'));
    });
  });

  group('SqmOverview Model', () {});

  group('Storage Assessment & Edge Case Logic', () {
    const int luciMinBytes = 500 * 1024;
    const int scriptsMinBytes = 100 * 1024;

    test('Identifies exhausted storage condition (< 100 KB) in overlay', () {
      final mockMountData = [
        {
          'mount': '/',
          'device': '/dev/root',
          'type': 'squashfs',
          'size': 16777216,
          'avail': 0,
        },
        {
          'mount': '/overlay',
          'device': '/dev/mtdblock6',
          'type': 'jffs2',
          'sizeBytes': 524288,
          'availableBytes': 57344,
        },
      ];

      final storage = StorageOverview.fromRpcData(mockMountData);
      final overlay = storage.overlayFs;

      expect(overlay, isNotNull);
      expect(overlay!.availableBytes, equals(57344));

      final bool isStorageExhausted = overlay.availableBytes < scriptsMinBytes;
      final bool isLuciStorageInsufficient =
          overlay.availableBytes < luciMinBytes;

      expect(isStorageExhausted, isTrue);
      expect(isLuciStorageInsufficient, isTrue);
    });

    test(
      'Allows sqm-scripts but restricts luci-app-sqm when storage is between 100 KB and 500 KB',
      () {
        final mockMountData = [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'type': 'jffs2',
            'sizeBytes': 1048576,
            'availableBytes': 256 * 1024,
          },
        ];

        final storage = StorageOverview.fromRpcData(mockMountData);
        final overlay = storage.overlayFs;

        expect(overlay, isNotNull);
        final bool isStorageExhausted =
            overlay!.availableBytes < scriptsMinBytes;
        final bool isLuciStorageInsufficient =
            overlay.availableBytes < luciMinBytes;

        expect(isStorageExhausted, isFalse);
        expect(isLuciStorageInsufficient, isTrue);
      },
    );

    test(
      'Allows both packages when overlay has sufficient free space (>= 500 KB)',
      () {
        final mockMountData = [
          {
            'mount': '/overlay',
            'device': '/dev/mtdblock6',
            'type': 'ext4',
            'size': 33554432,
            'avail': 16777216,
          },
        ];

        final storage = StorageOverview.fromRpcData(mockMountData);
        final overlay = storage.overlayFs;

        expect(overlay, isNotNull);
        expect(overlay!.availableBytes, greaterThan(500 * 1024));

        final bool isStorageExhausted =
            overlay.availableBytes < scriptsMinBytes;
        final bool isLuciStorageInsufficient =
            overlay.availableBytes < luciMinBytes;
        expect(isStorageExhausted, isFalse);
        expect(isLuciStorageInsufficient, isFalse);
      },
    );

    test('Detects read-only or exhausted storage partition', () {
      final mockMountData = [
        {
          'mount': '/overlay',
          'device': '/dev/mtdblock6',
          'type': 'jffs2',
          'size': 524288,
          'avail': 0,
        },
      ];

      final storage = StorageOverview.fromRpcData(mockMountData);
      final overlay = storage.overlayFs;

      expect(overlay, isNotNull);
      expect(overlay!.availableBytes, equals(0));
      expect(overlay.availableBytes < scriptsMinBytes, isTrue);
    });
  });

  group('Queue Naming & Verbosity', () {
    test('SqmQueue serializes and parses verbosity field', () {
      const queue = SqmQueue(
        name: 'sqm1',
        interface: 'wan',
        debugLogging: true,
        verbosity: 8,
      );

      final params = queue.toUciParams();
      expect(params['verbosity'], equals('8'));
      expect(params['debug_logging'], equals('1'));

      final parsed = SqmQueue.fromUci('sqm1', {
        'interface': 'wan',
        'debug_logging': '1',
        'verbosity': '8',
      });
      expect(parsed.verbosity, equals(8));
      expect(parsed.debugLogging, isTrue);

      final modified = queue.copyWith(verbosity: 2);
      expect(modified.verbosity, equals(2));
    });

    test(
      'Queue naming algorithm avoids collisions with existing queues and interfaces',
      () {
        final existingQueues = {'sqm1', 'sqm2'};
        final networkInterfaces = {'sqm3', 'eth0', 'eth1', 'br-lan', 'wan'};

        int counter = 1;
        String newName = 'sqm$counter';
        final existingLower = existingQueues
            .map((q) => q.toLowerCase())
            .toSet();
        final ifaceLower = networkInterfaces
            .map((i) => i.toLowerCase())
            .toSet();

        while (existingLower.contains(newName.toLowerCase()) ||
            ifaceLower.contains(newName.toLowerCase())) {
          counter++;
          newName = 'sqm$counter';
        }

        expect(newName, equals('sqm4'));
      },
    );
  });

  group('MockApiService SQM Method', () {
    test('saveSqmQueue, deleteSqmQueue, toggleSqmService execute', () async {
      final api = MockApiService();

      const testQueue = SqmQueue(
        name: 'eth1',
        enabled: true,
        interface: 'wan',
        download: 100000,
        upload: 20000,
      );

      final saveResult = await api.saveSqmQueue(
        '192.168.1.1',
        'auth_token',
        false,
        queue: testQueue,
      );
      expect(saveResult, isTrue);

      final toggleResult = await api.toggleSqmService(
        '192.168.1.1',
        'auth_token',
        false,
        enable: true,
      );
      expect(toggleResult, isTrue);

      final deleteResult = await api.deleteSqmQueue(
        '192.168.1.1',
        'auth_token',
        false,
        sectionName: 'eth1',
      );
      expect(deleteResult, isTrue);
    });
  });

  group('Flow Offloading Detection', () {});
}
