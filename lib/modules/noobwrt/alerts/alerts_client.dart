// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

import '../datacap/data_plan_client.dart';
import '../history/helper_history.dart';
import '../noob_rpc.dart';
import 'alert_models.dart';

String keyId(String key) =>
    sha256.convert(utf8.encode(key)).toString().substring(0, 8);

class AlertsInfo {
  const AlertsInfo({
    required this.version,
    required this.newest,
    required this.settings,
    this.keyId = '',
  });
  final String version;
  final int newest;
  final AlertSettings settings;

  final String keyId;
}

class AlertsPage {
  const AlertsPage({
    required this.events,
    required this.trimmed,
    required this.newest,
  });
  factory AlertsPage.from(Map<String, dynamic> r, int since) {
    final rows = r['events'], newest = r['newest'];
    return AlertsPage(
      events: rows is List
          ? rows.map(AlertEvent.from).nonNulls.toList()
          : const [],
      trimmed: r['trimmed'] == true,
      newest: newest is int ? newest : since,
    );
  }

  final List<AlertEvent> events;
  final bool trimmed;
  final int newest;
}

class AlertsClient {
  AlertsClient(this._call);
  AlertsClient.of(AppState app)
    : this((m, p) => noobCall(app, 'keystone.alerts', m, p));

  final HelperCall _call;

  Future<AlertsInfo?> info() async {
    final Map<String, dynamic> r;
    try {
      r = await _call('info', {});
    } catch (e) {
      if (keystoneMissing(e)) return null;
      rethrow;
    }
    final newest = r['newest'];
    if (newest is! int) return null;
    return AlertsInfo(
      version: '${r['version'] ?? ''}',
      newest: newest,
      settings: AlertSettings.from(r['settings']),
      keyId: '${r['key_id'] ?? ''}',
    );
  }

  Future<AlertsPage> events(int since) async =>
      AlertsPage.from(await _call('events', {'since': since}), since);

  Future<void> save(AlertSettings s) async {
    final r = await _call('set', s.toRouter());
    if (r['error'] != null) throw NoobRpcError('${r['error']}');
  }

  Future<void> clear() => _call('clear', {});

  Future<String> pair() async {
    final k = (await _call('pair', {}))['key'];
    if (k is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(k)) {
      throw const NoobRpcError("The router didn't give a key");
    }
    return k;
  }

  Future<void> resetKey() => _call('reset_key', {});
}

const _keep = 1000;

Future<({List<AlertEvent> events, bool trimmed, int newest})> collectSince(
  AlertsClient c,
  int lastId,
) => collectPages(c.events, lastId);

Future<({List<AlertEvent> events, bool trimmed, int newest})> collectPages(
  Future<AlertsPage> Function(int since) ask,
  int lastId,
) async {
  var events = <AlertEvent>[];
  var trimmed = false, since = lastId, newest = lastId;
  while (true) {
    final page = await ask(since);
    newest = page.newest;
    trimmed |= page.trimmed;
    final fresh = page.events.where((e) => e.id > since).toList();
    if (fresh.isEmpty) break;
    events.addAll(fresh);
    if (events.length > _keep) events = events.sublist(events.length - _keep);
    since = fresh.last.id;
    if (since >= newest) break;
  }
  return (events: events, trimmed: trimmed, newest: newest);
}

Future<List<(DateTime, DateTime)>> alertOutages(
  AlertsClient c,
  DateTime from,
  DateTime to,
) async {
  if (await c.info() == null) return const [];
  final got = await collectSince(c, 0);
  return [
    for (final e in got.events)
      if (e.type == AlertType.internet && e.start != null)
        if ((e.end ?? to).isAfter(from) && e.start!.isBefore(to))
          (e.start!, e.end ?? to),
  ];
}
