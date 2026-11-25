// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final operationQueueProvider = Provider<RouterScopedOperationQueue>(
  (ref) => RouterScopedOperationQueue.instance,
);

class _PendingOperation {
  final String domain;
  final Completer<void> completer = Completer<void>();
  bool isDisposed = false;

  _PendingOperation(this.domain);
}

class _RouterLockState {
  int activeExclusive = 0;

  int waitingExclusiveCount = 0;

  final List<_PendingOperation> exclusiveQueue = [];

  final Map<String, int> activeDomains = {};

  final Map<String, List<_PendingOperation>> domainQueues = {};

  bool get isIdle =>
      activeExclusive == 0 &&
      waitingExclusiveCount == 0 &&
      exclusiveQueue.isEmpty &&
      activeDomains.isEmpty &&
      domainQueues.values.every((q) => q.isEmpty);

  bool isBusy(String domain) {
    if (activeExclusive > 0 || waitingExclusiveCount > 0) return true;
    if (domain == '*') {
      return activeDomains.isNotEmpty;
    }
    return (activeDomains[domain] ?? 0) > 0;
  }
}

class RouterScopedOperationQueue {
  RouterScopedOperationQueue._();

  static final RouterScopedOperationQueue instance =
      RouterScopedOperationQueue._();

  final Map<String, _RouterLockState> _routerStates = {};

  _RouterLockState _getState(String routerId) {
    return _routerStates.putIfAbsent(routerId, () => _RouterLockState());
  }

  void _cleanupIfIdle(String routerId) {
    final state = _routerStates[routerId];
    if (state != null && state.isIdle) {
      _routerStates.remove(routerId);
    }
  }

  bool isBusy(String routerId, String domain) {
    final state = _routerStates[routerId];
    if (state == null) return false;
    return state.isBusy(domain);
  }

  Future<T> runLocked<T>({
    required String routerId,
    required String domain,
    required Future<T> Function() action,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final activeLockKey = 'operation_queue_lock_$routerId';
    final heldDomain = Zone.current[Symbol(activeLockKey)] as String?;
    if (heldDomain != null && (heldDomain == domain || heldDomain == '*')) {
      return await action();
    }

    await _acquire(routerId, domain, timeout);
    try {
      return await runZoned(
        action,
        zoneValues: {Symbol(activeLockKey): domain},
      );
    } finally {
      _release(routerId, domain);
    }
  }

  Future<void> _acquire(
    String routerId,
    String domain,
    Duration timeout,
  ) async {
    final state = _getState(routerId);

    if (domain == '*') {
      if (state.activeExclusive == 0 &&
          state.activeDomains.isEmpty &&
          state.waitingExclusiveCount == 0) {
        state.activeExclusive = 1;
        return;
      }

      state.waitingExclusiveCount++;
      final op = _PendingOperation('*');
      state.exclusiveQueue.add(op);

      try {
        await op.completer.future.timeout(timeout);
      } on TimeoutException {
        op.isDisposed = true;
        state.exclusiveQueue.remove(op);
        state.waitingExclusiveCount--;
        if (op.completer.isCompleted) {
          _release(routerId, '*');
        } else {
          _pumpQueues(state);
          _cleanupIfIdle(routerId);
        }
        rethrow;
      }
    } else {
      if (state.activeExclusive == 0 &&
          state.waitingExclusiveCount == 0 &&
          (state.activeDomains[domain] ?? 0) == 0) {
        state.activeDomains[domain] = 1;
        return;
      }

      final op = _PendingOperation(domain);
      state.domainQueues.putIfAbsent(domain, () => []).add(op);

      try {
        await op.completer.future.timeout(timeout);
      } on TimeoutException {
        op.isDisposed = true;
        state.domainQueues[domain]?.remove(op);
        if (op.completer.isCompleted) {
          _release(routerId, domain);
        } else {
          _pumpQueues(state);
          _cleanupIfIdle(routerId);
        }
        rethrow;
      }
    }
  }

  void _release(String routerId, String domain) {
    final state = _routerStates[routerId];
    if (state == null) return;

    if (domain == '*') {
      state.activeExclusive = 0;
    } else {
      state.activeDomains.remove(domain);
    }

    _pumpQueues(state);
    _cleanupIfIdle(routerId);
  }

  void _pumpQueues(_RouterLockState state) {
    if (state.activeExclusive > 0) {
      return;
    }

    if (state.waitingExclusiveCount > 0) {
      if (state.activeDomains.isEmpty) {
        while (state.exclusiveQueue.isNotEmpty) {
          final op = state.exclusiveQueue.removeAt(0);
          state.waitingExclusiveCount--;
          if (!op.isDisposed && !op.completer.isCompleted) {
            state.activeExclusive = 1;
            op.completer.complete();
            return;
          }
        }
      }
      return;
    }

    for (final domain in state.domainQueues.keys.toList()) {
      if ((state.activeDomains[domain] ?? 0) == 0) {
        final queue = state.domainQueues[domain];
        if (queue != null) {
          while (queue.isNotEmpty) {
            final op = queue.removeAt(0);
            if (!op.isDisposed && !op.completer.isCompleted) {
              state.activeDomains[domain] = 1;
              op.completer.complete();
              break;
            }
          }
        }
      }
    }
  }
}
