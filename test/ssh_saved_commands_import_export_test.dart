// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/ssh_console/services/saved_commands_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    final appState = AppState.instance;
    appState.setApiServiceForTesting(MockApiService());
    appState.setDashboardTabActive(false);
    appState.cancelThroughputTimer();
  });

  tearDown(() {
    AppState.instance.cancelThroughputTimer();
  });

  group('SavedCommandsService Import', () {
    const testRouterId = 'test-router-1';
    late SavedCommandsService service;

    setUp(() {
      service = SavedCommandsService();
    });

    test('imports commands from raw JSON array', () async {
      final jsonArray = jsonEncode([
        {'name': 'Check IP', 'command': 'ip addr show'},
        {'name': 'Show Disk', 'command': 'df -h'},
      ]);

      final count = await service.importFromJson(testRouterId, jsonArray);
      expect(count, equals(2));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
      expect(saved[0].name, equals('Check IP'));
      expect(saved[0].command, equals('ip addr show'));
      expect(saved[1].name, equals('Show Disk'));
      expect(saved[1].command, equals('df -h'));
    });

    test('imports commands from single category export JSON', () async {
      final categoryJson = jsonEncode({
        'category': 'sshSavedCommands',
        'exportedAt': DateTime.now().toIso8601String(),
        'data': [
          {'name': 'Uptime', 'command': 'uptime'},
          {'name': 'Free RAM', 'command': 'free -m'},
        ],
      });

      final count = await service.importFromJson(testRouterId, categoryJson);
      expect(count, equals(2));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
      expect(saved.any((c) => c.name == 'Uptime'), isTrue);
    });

    test('imports commands from full config export JSON manifest', () async {
      final fullConfigJson = jsonEncode({
        'manifestVersion': 1,
        'categories': {
          'sshSavedCommands': {
            'data': [
              {'name': 'Logread', 'command': 'logread -f'},
            ],
          },
          'firewall': {'data': []},
        },
      });

      final count = await service.importFromJson(testRouterId, fullConfigJson);
      expect(count, equals(1));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(1));
      expect(saved.first.name, equals('Logread'));
      expect(saved.first.command, equals('logread -f'));
    });

    test('handles invalid JSON and empty strings', () async {
      expect(await service.importFromJson(testRouterId, ''), equals(0));
      expect(
        await service.importFromJson(testRouterId, 'not a json'),
        equals(0),
      );
      expect(await service.importFromJson(testRouterId, '{}'), equals(0));
      expect(
        await service.importFromJson(testRouterId, '{"data": []}'),
        equals(0),
      );
    });

    test('deduplicates existing commands by name and command text', () async {
      final firstBatch = jsonEncode([
        {'name': 'Reboot', 'command': 'reboot'},
      ]);
      await service.importFromJson(testRouterId, firstBatch);

      final secondBatch = jsonEncode([
        {'name': 'Reboot', 'command': 'reboot'},
        {'name': 'New Cmd', 'command': 'ls -l'},
      ]);
      final count = await service.importFromJson(testRouterId, secondBatch);
      expect(count, equals(1));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(2));
    });

    test('caps total commands at 50', () async {
      final fiftyCommands = List.generate(
        55,
        (i) => {'name': 'Cmd $i', 'command': 'echo $i'},
      );
      final count = await service.importFromJson(
        testRouterId,
        jsonEncode(fiftyCommands),
      );
      expect(count, equals(50));

      final saved = await service.getAll(testRouterId);
      expect(saved.length, equals(50));
    });
  });

  group('ConfigExportService SSH Commands Export', () {});

  group('JsonExportScreen Category UI', () {});
}
