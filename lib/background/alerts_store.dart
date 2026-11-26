// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../modules/noobwrt/alerts/alert_models.dart';

const _keep = 500;

String alertsKeyName(String routerId) => 'alerts.key.$routerId';

class AlertsStore {
  AlertsStore(this._p);
  final SharedPreferences _p;

  int? lastId(String router) => _p.getInt('alerts.lastId.$router');
  Future<void> setLastId(String router, int id) =>
      _p.setInt('alerts.lastId.$router', id);

  bool trimmed(String router) => _p.getBool('alerts.trimmed.$router') ?? false;
  Future<void> setTrimmed(String router, bool v) =>
      _p.setBool('alerts.trimmed.$router', v);

  bool get muted => _p.getBool('alerts.muted') ?? false;
  Future<void> setMuted(bool v) => _p.setBool('alerts.muted', v);

  List<AlertEvent> events(String router) {
    try {
      final j = jsonDecode(_p.getString('alerts.cache.$router') ?? '[]');
      return j is List ? j.map(AlertEvent.from).nonNulls.toList() : const [];
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveEvents(String router, List<AlertEvent> fresh) async {
    if (fresh.isEmpty) return;
    final all = {
      for (final e in events(router)) e.id: e,
      for (final e in fresh) e.id: e,
    }.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    await _p.setString(
      'alerts.cache.$router',
      jsonEncode([for (final e in all.take(_keep)) e.toCache()]),
    );
  }

  Future<void> clearEvents(String router) => _p.remove('alerts.cache.$router');

  Future<void> removeEvents(String router, Set<int> ids) async {
    if (ids.isEmpty) return;
    final keep = [
      for (final e in events(router))
        if (!ids.contains(e.id)) e,
    ];
    await _p.setString(
      'alerts.cache.$router',
      jsonEncode([for (final e in keep) e.toCache()]),
    );
  }

  Future<void> forget(String router) async {
    for (final k in const ['lastId', 'trimmed', 'cache']) {
      await _p.remove('alerts.$k.$router');
    }
  }
}
