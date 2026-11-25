// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'sqm_queue.dart';

@immutable
class CakeTinStats {
  final String name;
  final int? thresholdBps;
  final double? targetMs;
  final double? intervalMs;
  final double? pkDelayMs;
  final double? avDelayMs;
  final double? spDelayMs;
  final int backlogBytes;
  final int backlogPackets;
  final int droppedPackets;
  final int? sentPackets;
  final int? sentBytes;
  final int? ecnMarked;

  const CakeTinStats({
    required this.name,
    this.thresholdBps,
    this.targetMs,
    this.intervalMs,
    this.pkDelayMs,
    this.avDelayMs,
    this.spDelayMs,
    this.backlogBytes = 0,
    this.backlogPackets = 0,
    this.droppedPackets = 0,
    this.sentPackets,
    this.sentBytes,
    this.ecnMarked,
  });

  CakeTinStats copyWith({
    String? name,
    int? thresholdBps,
    double? targetMs,
    double? intervalMs,
    double? pkDelayMs,
    double? avDelayMs,
    double? spDelayMs,
    int? backlogBytes,
    int? backlogPackets,
    int? droppedPackets,
    int? sentPackets,
    int? sentBytes,
    int? ecnMarked,
  }) {
    return CakeTinStats(
      name: name ?? this.name,
      thresholdBps: thresholdBps ?? this.thresholdBps,
      targetMs: targetMs ?? this.targetMs,
      intervalMs: intervalMs ?? this.intervalMs,
      pkDelayMs: pkDelayMs ?? this.pkDelayMs,
      avDelayMs: avDelayMs ?? this.avDelayMs,
      spDelayMs: spDelayMs ?? this.spDelayMs,
      backlogBytes: backlogBytes ?? this.backlogBytes,
      backlogPackets: backlogPackets ?? this.backlogPackets,
      droppedPackets: droppedPackets ?? this.droppedPackets,
      sentPackets: sentPackets ?? this.sentPackets,
      sentBytes: sentBytes ?? this.sentBytes,
      ecnMarked: ecnMarked ?? this.ecnMarked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CakeTinStats &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          thresholdBps == other.thresholdBps &&
          targetMs == other.targetMs &&
          intervalMs == other.intervalMs &&
          pkDelayMs == other.pkDelayMs &&
          avDelayMs == other.avDelayMs &&
          spDelayMs == other.spDelayMs &&
          backlogBytes == other.backlogBytes &&
          backlogPackets == other.backlogPackets &&
          droppedPackets == other.droppedPackets &&
          sentPackets == other.sentPackets &&
          sentBytes == other.sentBytes &&
          ecnMarked == other.ecnMarked;

  @override
  int get hashCode => Object.hash(
    name,
    thresholdBps,
    targetMs,
    intervalMs,
    pkDelayMs,
    avDelayMs,
    spDelayMs,
    backlogBytes,
    backlogPackets,
    droppedPackets,
    sentPackets,
    sentBytes,
    ecnMarked,
  );
}

@immutable
class SqmQueueTelemetry {
  final String interfaceName;
  final String qdisc;
  final String? handle;
  final bool root;
  final int sentBytes;
  final int sentPackets;
  final int droppedPackets;
  final int overlimits;
  final int requeues;
  final int backlogBytes;
  final int backlogPackets;
  final int? memoryUsedBytes;
  final int? memoryLimitBytes;
  final int? capacityEstimateBps;
  final int? ecnMarked;
  final int? dropOverlimit;
  final int? maxPacket;
  final int? newFlowCount;
  final List<CakeTinStats> tinStats;
  final String rawOutput;
  final DateTime timestamp;

  const SqmQueueTelemetry({
    required this.interfaceName,
    required this.qdisc,
    this.handle,
    this.root = true,
    this.sentBytes = 0,
    this.sentPackets = 0,
    this.droppedPackets = 0,
    this.overlimits = 0,
    this.requeues = 0,
    this.backlogBytes = 0,
    this.backlogPackets = 0,
    this.memoryUsedBytes,
    this.memoryLimitBytes,
    this.capacityEstimateBps,
    this.ecnMarked,
    this.dropOverlimit,
    this.maxPacket,
    this.newFlowCount,
    this.tinStats = const [],
    this.rawOutput = '',
    required this.timestamp,
  });

  double get dropRatePercent {
    final total = sentPackets + droppedPackets;
    if (total <= 0) return 0.0;
    return (droppedPackets / total) * 100.0;
  }

  bool get hasBacklog => backlogPackets > 0 || backlogBytes > 0;

  bool get hasCumulativeDrops => droppedPackets > 0;

  bool get hasCumulativeOverlimits => overlimits > 0;

  bool hasRecentDropActivity(SqmQueueTelemetry? previous) {
    if (previous == null) return false;
    return droppedPackets > previous.droppedPackets ||
        overlimits > previous.overlimits;
  }

  bool get isCake => qdisc.toLowerCase() == 'cake';

  bool get isFqCodel => qdisc.toLowerCase() == 'fq_codel';

  factory SqmQueueTelemetry.empty(String interfaceName) {
    return SqmQueueTelemetry(
      interfaceName: interfaceName,
      qdisc: 'none',
      timestamp: DateTime.now(),
    );
  }

  SqmQueueTelemetry copyWith({
    String? interfaceName,
    String? qdisc,
    String? handle,
    bool? root,
    int? sentBytes,
    int? sentPackets,
    int? droppedPackets,
    int? overlimits,
    int? requeues,
    int? backlogBytes,
    int? backlogPackets,
    int? memoryUsedBytes,
    int? memoryLimitBytes,
    int? capacityEstimateBps,
    int? ecnMarked,
    int? dropOverlimit,
    int? maxPacket,
    int? newFlowCount,
    List<CakeTinStats>? tinStats,
    String? rawOutput,
    DateTime? timestamp,
  }) {
    return SqmQueueTelemetry(
      interfaceName: interfaceName ?? this.interfaceName,
      qdisc: qdisc ?? this.qdisc,
      handle: handle ?? this.handle,
      root: root ?? this.root,
      sentBytes: sentBytes ?? this.sentBytes,
      sentPackets: sentPackets ?? this.sentPackets,
      droppedPackets: droppedPackets ?? this.droppedPackets,
      overlimits: overlimits ?? this.overlimits,
      requeues: requeues ?? this.requeues,
      backlogBytes: backlogBytes ?? this.backlogBytes,
      backlogPackets: backlogPackets ?? this.backlogPackets,
      memoryUsedBytes: memoryUsedBytes ?? this.memoryUsedBytes,
      memoryLimitBytes: memoryLimitBytes ?? this.memoryLimitBytes,
      capacityEstimateBps: capacityEstimateBps ?? this.capacityEstimateBps,
      ecnMarked: ecnMarked ?? this.ecnMarked,
      dropOverlimit: dropOverlimit ?? this.dropOverlimit,
      maxPacket: maxPacket ?? this.maxPacket,
      newFlowCount: newFlowCount ?? this.newFlowCount,
      tinStats: tinStats ?? this.tinStats,
      rawOutput: rawOutput ?? this.rawOutput,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqmQueueTelemetry &&
          runtimeType == other.runtimeType &&
          interfaceName == other.interfaceName &&
          qdisc == other.qdisc &&
          handle == other.handle &&
          root == other.root &&
          sentBytes == other.sentBytes &&
          sentPackets == other.sentPackets &&
          droppedPackets == other.droppedPackets &&
          overlimits == other.overlimits &&
          requeues == other.requeues &&
          backlogBytes == other.backlogBytes &&
          backlogPackets == other.backlogPackets &&
          memoryUsedBytes == other.memoryUsedBytes &&
          memoryLimitBytes == other.memoryLimitBytes &&
          capacityEstimateBps == other.capacityEstimateBps &&
          ecnMarked == other.ecnMarked &&
          dropOverlimit == other.dropOverlimit &&
          maxPacket == other.maxPacket &&
          newFlowCount == other.newFlowCount &&
          listEquals(tinStats, other.tinStats);

  @override
  int get hashCode => Object.hash(
    interfaceName,
    qdisc,
    handle,
    root,
    sentBytes,
    sentPackets,
    droppedPackets,
    overlimits,
    requeues,
    backlogBytes,
    backlogPackets,
    memoryUsedBytes,
    memoryLimitBytes,
    capacityEstimateBps,
    ecnMarked,
    dropOverlimit,
    maxPacket,
    newFlowCount,
    Object.hashAll(tinStats),
  );
}

enum SqmOperatingState {
  notInstalled,

  inactive,

  active,

  flowOffloadingConflict,

  telemetryUnavailable,

  tcCommandUnavailable,
}

@immutable
class SqmState {
  final SqmOperatingState operatingState;
  final bool isInstalled;
  final bool isServiceRunning;
  final bool isServiceEnabled;
  final List<SqmQueue> queues;
  final String? primaryWanInterface;
  final List<String> networkInterfaces;
  final bool hasSoftwareFlowOffload;
  final bool hasHardwareFlowOffload;
  final Map<String, SqmQueueTelemetry> telemetryByInterface;
  final Map<String, SqmQueueTelemetry> previousTelemetryByInterface;
  final bool isLoading;
  final bool isTelemetryPolling;
  final String? errorMessage;
  final DateTime? lastUpdated;

  const SqmState({
    this.operatingState = SqmOperatingState.inactive,
    this.isInstalled = false,
    this.isServiceRunning = false,
    this.isServiceEnabled = false,
    this.queues = const [],
    this.primaryWanInterface,
    this.networkInterfaces = const [],
    this.hasSoftwareFlowOffload = false,
    this.hasHardwareFlowOffload = false,
    this.telemetryByInterface = const {},
    this.previousTelemetryByInterface = const {},
    this.isLoading = false,
    this.isTelemetryPolling = false,
    this.errorMessage,
    this.lastUpdated,
  });

  bool get hasAnyFlowOffloading =>
      hasSoftwareFlowOffload || hasHardwareFlowOffload;

  SqmQueue? get primaryQueue {
    if (queues.isEmpty) return null;
    if (primaryWanInterface != null) {
      final wanMatch = queues.where((q) => q.interface == primaryWanInterface);
      if (wanMatch.isNotEmpty) return wanMatch.first;
    }
    final enabledMatch = queues.where((q) => q.enabled);
    if (enabledMatch.isNotEmpty) return enabledMatch.first;
    return queues.first;
  }

  SqmQueueTelemetry? get primaryTelemetry {
    final q = primaryQueue;
    if (q == null) return null;
    return telemetryByInterface[q.interface];
  }

  factory SqmState.initial() => const SqmState(isLoading: true);

  SqmState copyWith({
    SqmOperatingState? operatingState,
    bool? isInstalled,
    bool? isServiceRunning,
    bool? isServiceEnabled,
    List<SqmQueue>? queues,
    String? primaryWanInterface,
    List<String>? networkInterfaces,
    bool? hasSoftwareFlowOffload,
    bool? hasHardwareFlowOffload,
    Map<String, SqmQueueTelemetry>? telemetryByInterface,
    Map<String, SqmQueueTelemetry>? previousTelemetryByInterface,
    bool? isLoading,
    bool? isTelemetryPolling,
    String? errorMessage,
    DateTime? lastUpdated,
  }) {
    return SqmState(
      operatingState: operatingState ?? this.operatingState,
      isInstalled: isInstalled ?? this.isInstalled,
      isServiceRunning: isServiceRunning ?? this.isServiceRunning,
      isServiceEnabled: isServiceEnabled ?? this.isServiceEnabled,
      queues: queues ?? this.queues,
      primaryWanInterface: primaryWanInterface ?? this.primaryWanInterface,
      networkInterfaces: networkInterfaces ?? this.networkInterfaces,
      hasSoftwareFlowOffload:
          hasSoftwareFlowOffload ?? this.hasSoftwareFlowOffload,
      hasHardwareFlowOffload:
          hasHardwareFlowOffload ?? this.hasHardwareFlowOffload,
      telemetryByInterface: telemetryByInterface ?? this.telemetryByInterface,
      previousTelemetryByInterface:
          previousTelemetryByInterface ?? this.previousTelemetryByInterface,
      isLoading: isLoading ?? this.isLoading,
      isTelemetryPolling: isTelemetryPolling ?? this.isTelemetryPolling,
      errorMessage: errorMessage ?? this.errorMessage,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqmState &&
          runtimeType == other.runtimeType &&
          operatingState == other.operatingState &&
          isInstalled == other.isInstalled &&
          isServiceRunning == other.isServiceRunning &&
          isServiceEnabled == other.isServiceEnabled &&
          listEquals(queues, other.queues) &&
          primaryWanInterface == other.primaryWanInterface &&
          listEquals(networkInterfaces, other.networkInterfaces) &&
          hasSoftwareFlowOffload == other.hasSoftwareFlowOffload &&
          hasHardwareFlowOffload == other.hasHardwareFlowOffload &&
          mapEquals(telemetryByInterface, other.telemetryByInterface) &&
          mapEquals(
            previousTelemetryByInterface,
            other.previousTelemetryByInterface,
          ) &&
          isLoading == other.isLoading &&
          isTelemetryPolling == other.isTelemetryPolling &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    operatingState,
    isInstalled,
    isServiceRunning,
    isServiceEnabled,
    Object.hashAll(queues),
    primaryWanInterface,
    Object.hashAll(networkInterfaces),
    hasSoftwareFlowOffload,
    hasHardwareFlowOffload,
    Object.hashAll(telemetryByInterface.entries),
    Object.hashAll(previousTelemetryByInterface.entries),
    isLoading,
    isTelemetryPolling,
    errorMessage,
  );
}
