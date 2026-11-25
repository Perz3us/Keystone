// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/modules/bandwidth_monitor/models/bandwidth_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RealtimeTrafficPoint Model', () {
    test('Parses luci-bwc raw array', () {
      final raw = [1711800000, 1048576, 100, 524288, 50];
      final pt = RealtimeTrafficPoint.fromList(raw);

      expect(pt.timestamp, equals(1711800000));
      expect(pt.rxBytes, equals(1048576));
      expect(pt.rxPackets, equals(100));
      expect(pt.txBytes, equals(524288));
      expect(pt.txPackets, equals(50));
      expect(pt.rxRate, equals(0.0));
      expect(pt.txRate, equals(0.0));
    });

    test('Handles short or empty list without throwing', () {
      final pt1 = RealtimeTrafficPoint.fromList([]);
      expect(pt1.timestamp, equals(0));
      expect(pt1.rxBytes, equals(0));

      final pt2 = RealtimeTrafficPoint.fromList([1711800000, 500]);
      expect(pt2.timestamp, equals(1711800000));
      expect(pt2.rxBytes, equals(500));
      expect(pt2.txBytes, equals(0));
    });

    test('Calculates rates between two consecutive points', () {
      const prev = RealtimeTrafficPoint(
        timestamp: 1711800000,
        rxBytes: 1000000,
        txBytes: 500000,
        rxPackets: 100,
        txPackets: 50,
      );

      final next = RealtimeTrafficPoint.fromList([
        1711800002,
        3000000,
        200,
        1500000,
        100,
      ], previousPoint: prev);

      expect(next.rxRate, equals(1000000.0));
      expect(next.txRate, equals(500000.0));
    });

    test('Handles counter reset/rollover', () {
      const prev = RealtimeTrafficPoint(
        timestamp: 1711800000,
        rxBytes: 5000000,
        txBytes: 5000000,
        rxPackets: 500,
        txPackets: 500,
      );

      final next = RealtimeTrafficPoint.fromList([
        1711800001,
        1000,
        1,
        2000,
        2,
      ], previousPoint: prev);

      expect(next.rxRate, equals(0.0));
      expect(next.txRate, equals(0.0));
    });
  });

  group('NlbwmonHostRecord & Report Model', () {
    test('Parses nlbwmon host record via fromColumns', () {
      final columns = [
        'mac',
        'ip',
        'layer7',
        'conns',
        'rx_bytes',
        'rx_pkts',
        'tx_bytes',
        'tx_pkts',
      ];
      final row = [
        'AA:BB:CC:DD:EE:FF',
        '192.168.1.105',
        'https',
        42,
        10485760,
        8000,
        5242880,
        4000,
      ];

      final record = NlbwmonHostRecord.fromColumns(columns, row);

      expect(record.ip, equals('192.168.1.105'));
      expect(record.mac, equals('AA:BB:CC:DD:EE:FF'));
      expect(record.layer7, equals('https'));
      expect(record.conns, equals(42));
      expect(record.rxBytes, equals(10485760));
      expect(record.txBytes, equals(5242880));
      expect(record.totalBytes, equals(15728640));
    });

    test('Parses nlbwmon report with period and host list', () {
      final json = {
        'period': '2026-03',
        'columns': [
          'mac',
          'ip',
          'layer7',
          'conns',
          'rx_bytes',
          'rx_pkts',
          'tx_bytes',
          'tx_pkts',
        ],
        'data': [
          [
            '11:22:33:44:55:66',
            '192.168.1.100',
            'http',
            10,
            1000,
            10,
            2000,
            20,
          ],
          ['AA:BB:CC:DD:EE:FF', '192.168.1.101', 'ssh', 20, 3000, 30, 4000, 40],
        ],
      };

      final report = NlbwmonReport.fromJson(json, '2026-03');

      expect(report.period, equals('2026-03'));
      expect(report.records.length, equals(2));
      expect(report.records[0].ip, equals('192.168.1.100'));
      expect(report.records[1].ip, equals('192.168.1.101'));
      expect(report.records[0].rxBytes, equals(1000));
      expect(report.records[1].txBytes, equals(4000));
    });
  });

  group('DeviceBandwidthItem Model', () {
    test('Calculates live and session formatted strings', () {
      final client = Client(
        ipAddress: '192.168.1.50',
        macAddress: 'AA:BB:CC:DD:EE:01',
        hostname: 'Work-Laptop',
        connectionType: ConnectionType.wireless,
        signalDbm: -55,
        rxRate: 866000,
      );

      final item = DeviceBandwidthItem(
        client: client,
        downloadSpeed: 2097152,
        uploadSpeed: 524288,
        peakDownloadSpeed: 4194304,
        peakUploadSpeed: 1048576,
        totalDownloaded: 1073741824,
        totalUploaded: 268435456,
      );

      expect(item.hasActiveSpeed, isTrue);
      expect(item.formattedDownloadSpeed('MB/s'), contains('MB/s'));
      expect(item.formattedUploadSpeed('KB/s'), contains('KB/s'));
      expect(item.formattedTotalDownloaded, contains('GB'));
      expect(item.formattedTotalUploaded, contains('MB'));
      expect(item.displayName, equals('Work-Laptop'));
      expect(item.ipAddress, equals('192.168.1.50'));
      expect(item.macAddress, equals('AA:BB:CC:DD:EE:01'));
    });

    test('Correctly identifies inactive devices below active threshold', () {
      final client = Client(
        ipAddress: '192.168.1.51',
        macAddress: 'AA:BB:CC:DD:EE:02',
        hostname: 'Idle-Phone',
      );

      final item = DeviceBandwidthItem(
        client: client,
        downloadSpeed: 50,
        uploadSpeed: 40,
      );

      expect(item.hasActiveSpeed, isFalse);
    });
  });

  group('BandwidthSummary Model', () {
    test('Computes aggregate speeds and session totals', () {
      const summary = BandwidthSummary(
        totalDownloadSpeed: 5242880,
        totalUploadSpeed: 1048576,
        peakDownloadSpeed: 10485760,
        peakUploadSpeed: 2097152,
        totalSessionDownload: 5000000000,
        totalSessionUpload: 1000000000,
        connectedDevicesCount: 5,
        activeTrafficDevicesCount: 3,
      );

      expect(summary.formattedDownloadSpeed('MB/s'), contains('MB/s'));
      expect(summary.formattedUploadSpeed('MB/s'), contains('MB/s'));
      expect(summary.formattedPeakDownload('MB/s'), contains('MB/s'));
      expect(summary.formattedPeakUpload('MB/s'), contains('MB/s'));
      expect(summary.formattedTotalDownloaded, isNotEmpty);
      expect(summary.formattedTotalUploaded, isNotEmpty);
    });
  });
}
