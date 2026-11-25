// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import '../../../services/service_factory.dart';
import '../models/reboot_capability.dart';
import '../models/reboot_state.dart';
import '../services/advanced_reboot_coordinator.dart';
import '../services/advanced_reboot_detector.dart';

class AdvancedRebootState {
  final AdvancedRebootCapabilities? capabilities;
  final RebootExecutionProgress progress;
  final bool isDetecting;
  final String? detectionError;

  const AdvancedRebootState({
    this.capabilities,
    this.progress = const RebootExecutionProgress(),
    this.isDetecting = false,
    this.detectionError,
  });

  bool get hasCapabilities => capabilities != null;

  AdvancedRebootState copyWith({
    AdvancedRebootCapabilities? capabilities,
    RebootExecutionProgress? progress,
    bool? isDetecting,
    String? detectionError,
  }) {
    return AdvancedRebootState(
      capabilities: capabilities ?? this.capabilities,
      progress: progress ?? this.progress,
      isDetecting: isDetecting ?? this.isDetecting,
      detectionError: detectionError,
    );
  }
}

class AdvancedRebootController extends StateNotifier<AdvancedRebootState> {
  final Ref ref;
  final AdvancedRebootDetector detector;
  final AdvancedRebootCoordinator coordinator;

  AdvancedRebootController({
    required this.ref,
    required this.detector,
    required this.coordinator,
  }) : super(const AdvancedRebootState()) {
    detectCapabilities();
  }

  Future<void> detectCapabilities() async {
    state = state.copyWith(isDetecting: true, detectionError: null);

    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;

    if (router == null || sysauth == null) {
      state = state.copyWith(
        isDetecting: false,
        detectionError: 'No router session active or router not selected.',
      );
      return;
    }

    try {
      final caps = await detector.detect(
        routerId: router.id,
        ipAddress: router.ipAddress,
        sysauth: sysauth,
        useHttps: router.useHttps,
        sshUsername: router.username,
        sshPassword: router.password,
        sshPort: 22,
        routerCapabilities: appState.capabilities,
      );

      state = state.copyWith(
        capabilities: caps,
        isDetecting: false,
        detectionError: caps.detectionError,
      );
    } catch (e) {
      state = state.copyWith(isDetecting: false, detectionError: e.toString());
    }
  }

  Future<void> executeOperation(
    RebootOperationType operation, {
    String? targetSlot,
  }) async {
    final appState = ref.read(appStateProvider);
    final router = appState.selectedRouter;
    final sysauth = appState.sysauth;
    final caps = state.capabilities;

    if (router == null || sysauth == null || caps == null) {
      state = state.copyWith(
        progress: state.progress.copyWith(
          state: RebootExecutionState.failed,
          message: 'Cannot execute: active session or capabilities missing.',
          failureReason: 'Missing router session or capabilities',
        ),
      );
      return;
    }

    await coordinator.execute(
      router: router,
      sysauth: sysauth,
      operation: operation,
      capabilities: caps,
      targetSlot: targetSlot,
      sshUsername: router.username,
      sshPassword: router.password,
      sshPort: 22,
      onProgress: (p) {
        state = state.copyWith(progress: p);
      },
    );
  }

  void cancel() {
    coordinator.cancel();
  }

  void resetProgress() {
    state = state.copyWith(progress: const RebootExecutionProgress());
  }
}

final advancedRebootControllerProvider =
    StateNotifierProvider.autoDispose<
      AdvancedRebootController,
      AdvancedRebootState
    >((ref) {
      final apiService = ServiceContainer.instance.factory.createApiService();
      final sshService = ServiceContainer.instance.factory.createSshService();
      final detector = AdvancedRebootDetector(
        apiService: apiService,
        sshService: sshService,
      );
      final coordinator = AdvancedRebootCoordinator(
        apiService: apiService,
        sshService: sshService,
        detector: detector,
      );

      return AdvancedRebootController(
        ref: ref,
        detector: detector,
        coordinator: coordinator,
      );
    });
