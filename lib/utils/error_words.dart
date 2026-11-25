// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

String errorWords(Object? e) {
  final t = '$e'.toLowerCase();
  bool has(List<String> words) => words.any(t.contains);
  if (has(['unauthorized', 'http 401', 'status 401', 'statuscode: 401'])) {
    return 'You were signed out. Sign in again.';
  }
  if (has([
    'access denied',
    'permission denied',
    'ubus code 6',
    'http 403',
    'status 403',
    'statuscode: 403',
    'forbidden',
  ])) {
    return 'The router didn\'t allow that for this account.';
  }
  if (has([
    'socketexception',
    'clientexception',
    'failed to reach',
    'connection refused',
    'network is unreachable',
    'no route to host',
    'host lookup failed',
    'os error:',
  ])) {
    return 'Couldn\'t reach the router. Check you\'re on its Wi-Fi.';
  }
  if (has(['http 404', 'status 404', 'statuscode: 404'])) {
    return 'The router is missing a part this needs.';
  }
  if (has([
    'http 500',
    'http 502',
    'http 503',
    'status 500',
    'status 502',
    'status 503',
  ])) {
    return 'The router had a problem. Try again.';
  }
  if (has(['timed out', 'timeout', 'ubus error 7', 'code 7'])) {
    return 'The router took too long. It may be busy.';
  }
  if (has(['command not found', 'exit code 127', 'code: 127'])) {
    return 'The router is missing a program this needs.';
  }
  if (has(['no space left', 'disk full', 'insufficient space'])) {
    return 'The router\'s storage is full.';
  }
  if (has(['out of memory', 'cannot allocate memory']) ||
      t.trim() == 'killed') {
    return 'The router ran out of memory.';
  }
  return 'Something went wrong. Try again.';
}

class ActionRateLimiter {
  static final Map<String, DateTime> _last = {};
  static final Map<String, int> _suppressed = {};

  static bool isRateLimited(
    String actionKey, {
    Duration cooldown = const Duration(milliseconds: 1500),
  }) {
    final now = DateTime.now();
    final last = _last[actionKey];
    if (last != null && now.difference(last) < cooldown) {
      _suppressed[actionKey] = (_suppressed[actionKey] ?? 0) + 1;
      return true;
    }
    _last[actionKey] = now;
    _suppressed[actionKey] = 0;
    return false;
  }

  static Duration getRemainingCooldown(
    String actionKey, {
    Duration cooldown = const Duration(milliseconds: 1500),
  }) {
    final last = _last[actionKey];
    if (last == null) return Duration.zero;
    final left = cooldown - DateTime.now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  static int getSuppressionCount(String actionKey) =>
      _suppressed[actionKey] ?? 0;

  static void reset([String? actionKey]) {
    if (actionKey == null) {
      _last.clear();
      _suppressed.clear();
    } else {
      _last.remove(actionKey);
      _suppressed.remove(actionKey);
    }
  }
}
