// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';

class ThroughputController {
  ThroughputController({required ThroughputService throughputService})
    : _throughputService = throughputService;

  final ThroughputService _throughputService;

  Timer? _throughputTimer;
  int _throughputIntervalSeconds = 2;

  int get throughputIntervalSeconds => _throughputIntervalSeconds;

  List<double> get rxHistory => _throughputService.rxHistory;
  List<double> get txHistory => _throughputService.txHistory;
  double get currentRxRate => _throughputService.currentRxRate;
  double get currentTxRate => _throughputService.currentTxRate;

  List<double> getRxHistoryForInterface(String interface) =>
      _throughputService.getRxHistoryForInterface(interface);

  List<double> getTxHistoryForInterface(String interface) =>
      _throughputService.getTxHistoryForInterface(interface);

  double getCurrentRxRateForInterface(String interface) =>
      _throughputService.getCurrentRxRateForInterface(interface);

  double getCurrentTxRateForInterface(String interface) =>
      _throughputService.getCurrentTxRateForInterface(interface);

  bool setInterval(
    int seconds, {
    required bool isRebooting,
    required VoidCallback onTick,
    bool immediateTick = true,
  }) {
    final clamped = seconds.clamp(1, 10);
    final changed = _throughputIntervalSeconds != clamped;
    final wasRunning = isTimerRunning;
    _throughputIntervalSeconds = clamped;
    startTimer(isRebooting: isRebooting, onTick: onTick);
    if (immediateTick && !isRebooting) {
      Future.microtask(onTick);
    }
    return changed || !wasRunning;
  }

  bool _isPaused = false;

  bool get isTimerRunning =>
      _throughputTimer != null && _throughputTimer!.isActive;

  bool get isPaused => _isPaused;

  void startTimer({required bool isRebooting, required VoidCallback onTick}) {
    _isPaused = false;
    _throughputTimer?.cancel();
    if (isRebooting) return;
    _throughputTimer = Timer.periodic(
      Duration(seconds: _throughputIntervalSeconds),
      (_) => onTick(),
    );
  }

  void cancelAndClear() {
    _isPaused = false;
    _throughputTimer?.cancel();
    _throughputTimer = null;
    _throughputService.clear();
  }

  void pauseTimer() {
    if (isTimerRunning) {
      _isPaused = true;
      _throughputTimer?.cancel();
      _throughputTimer = null;
    }
  }

  void resumeTimer({
    required bool isRebooting,
    required VoidCallback onTick,
    bool immediateTick = false,
  }) {
    if (_isPaused) {
      _isPaused = false;
      _throughputService.resetBaseline();
      startTimer(isRebooting: isRebooting, onTick: onTick);
      if (immediateTick && !isRebooting) {
        Future.microtask(onTick);
      }
    }
  }

  void resetBaseline() {
    _throughputService.resetBaseline();
  }

  void updateThroughput(
    Map<String, dynamic>? networkData,
    Set<String> wanDeviceNames, {
    String? specificInterface,
  }) {
    _throughputService.updateThroughput(
      networkData,
      wanDeviceNames,
      specificInterface: specificInterface,
    );
  }

  static String? resolveSpecificInterface(
    DashboardPreferences prefs, {
    String? Function(String)? deviceNameResolver,
  }) {
    if (prefs.showAllThroughput || prefs.primaryThroughputInterface == null) {
      return null;
    }
    final interfaceId = prefs.primaryThroughputInterface!;
    if (interfaceId.contains('(')) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
      return match?.group(1);
    }
    if (deviceNameResolver != null) {
      final resolved = deviceNameResolver(interfaceId);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return interfaceId;
  }

  static Set<String> resolveThroughputDeviceNames(
    Map<String, dynamic>? interfaceDump,
  ) {
    if (interfaceDump == null || interfaceDump['interface'] is! List) {
      return const <String>{};
    }

    final wanDevices = <String>{};
    final lanDevices = <String>{};

    for (final interface in interfaceDump['interface']) {
      if (interface is! Map<String, dynamic>) continue;
      final ifname = (interface['interface'] as String?)?.toLowerCase();
      if (ifname == null || ifname == 'loopback' || ifname == 'lo') continue;

      final proto = (interface['proto'] as String?)?.toLowerCase();
      final device = interface['device'] as String?;
      final l3Device = interface['l3_device'] as String?;
      final targetDev = (l3Device != null && l3Device.isNotEmpty)
          ? l3Device
          : device;

      if (targetDev == null || targetDev == 'lo' || targetDev.isEmpty) continue;

      final routes = interface['route'];
      final hasDefaultRoute =
          interface['up'] == true &&
          routes is List &&
          routes.any(
            (r) => r is Map && r['target'] == '0.0.0.0' && r['mask'] == 0,
          );

      final isWan =
          ifname.startsWith('wan') ||
          proto == 'pppoe' ||
          interface['is_wan'] == true ||
          hasDefaultRoute;

      if (isWan) {
        wanDevices.add(targetDev);
      } else if (ifname == 'lan') {
        lanDevices.add(targetDev);
      } else if (ifname.startsWith('lan') && lanDevices.isEmpty) {
        lanDevices.add(targetDev);
      }
    }

    if (wanDevices.isNotEmpty) {
      return wanDevices;
    }

    if (lanDevices.isNotEmpty) {
      return lanDevices;
    }

    return const <String>{};
  }

  void dispose() {
    _throughputTimer?.cancel();
  }
}
