// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThroughputController Lazy Loading & Lifecycle', () {
    late ThroughputService throughputService;
    late ThroughputController controller;

    setUp(() {
      throughputService = ThroughputService();
      controller = ThroughputController(throughputService: throughputService);
    });

    tearDown(() {
      controller.cancelAndClear();
    });

    test('startTimer starts active timer and resets isPaused', () {
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isFalse);

      int ticks = 0;
      controller.startTimer(isRebooting: false, onTick: () => ticks++);

      expect(controller.isTimerRunning, isTrue);
      expect(controller.isPaused, isFalse);
    });

    test('pauseTimer pauses running timer and records isPaused', () {
      controller.startTimer(isRebooting: false, onTick: () {});
      expect(controller.isTimerRunning, isTrue);

      controller.pauseTimer();
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isTrue);
    });

    test('pauseTimer does nothing if timer was never started', () {
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isFalse);

      controller.pauseTimer();
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isFalse);
    });

    test('resumeTimer restarts timer only if it was paused', () {
      controller.resumeTimer(isRebooting: false, onTick: () {});
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isFalse);

      controller.startTimer(isRebooting: false, onTick: () {});
      expect(controller.isTimerRunning, isTrue);
      controller.pauseTimer();
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isTrue);

      controller.resumeTimer(isRebooting: false, onTick: () {});
      expect(controller.isTimerRunning, isTrue);
      expect(controller.isPaused, isFalse);
    });

    test('cancelAndClear completely resets timer and isPaused state', () {
      controller.startTimer(isRebooting: false, onTick: () {});
      controller.pauseTimer();
      expect(controller.isPaused, isTrue);

      controller.cancelAndClear();
      expect(controller.isTimerRunning, isFalse);
      expect(controller.isPaused, isFalse);

      controller.resumeTimer(isRebooting: false, onTick: () {});
      expect(controller.isTimerRunning, isFalse);
    });
  });
}
