// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../models/router.dart';
import '../modules/noobwrt/alerts/alert_notify_plan.dart';
import '../modules/noobwrt/alerts/alerts_client.dart';
import '../modules/noobwrt/modem/signal_overview.dart';
import '../screens/home/home_data.dart';
import '../services/secure_storage_service.dart';
import '../utils/logger.dart';
import 'alerts_feed.dart';
import 'alerts_store.dart';
import 'notifier.dart';
import 'widget_data.dart';
import 'widget_lines.dart';

const _task = 'keystone.check';

enum CheckResult { notWifi, nothingReachable, done }

class CheckDeps {
  const CheckDeps({
    required this.onWifi,
    required this.routers,
    required this.readKey,
    required this.post,
    required this.store,
    required this.phoneMuted,
    required this.notify,
    required this.saveWidget,
    required this.now,
  });

  final Future<bool> Function() onWifi;
  final Future<List<Router>> Function() routers;

  final Future<String?> Function(String routerId) readKey;
  final Future<FeedPost> Function(Router r) post;
  final AlertsStore store;
  final Future<bool> Function() phoneMuted;
  final Future<void> Function(NotifyPlan plan, String routerName) notify;
  final Future<void> Function(WidgetSnapshot s) saveWidget;
  final DateTime Function() now;
}

Future<CheckResult> runBackgroundCheck(CheckDeps d) async {
  var result = CheckResult.nothingReachable;
  try {
    if (!await d.onWifi()) return CheckResult.notWifi;
    for (final r in await d.routers()) {
      try {
        final key = await d.readKey(r.id);
        if (key == null) continue;
        final reply = await _collect(d, r, key, await d.post(r));
        if (result != CheckResult.done) {
          result = CheckResult.done;
          await d.saveWidget(_snapshot(r, reply, d.now()));
        }
      } catch (e) {
        Logger.info('Background check: ${r.id} skipped: $e');
      }
    }
  } catch (e, stack) {
    Logger.exception('Background check failed', e, stack);
  }
  return result;
}

String routerLabel(Router r) =>
    [
      r.name,
      r.lastKnownHostname,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).firstOrNull ??
    'Router';

Future<FeedReply> _collect(
  CheckDeps d,
  Router r,
  String key,
  FeedPost post,
) async {
  final last = d.store.lastId(r.id);
  final open = [
    for (final e in d.store.events(r.id))
      if (e.lasts && e.end == null) e.id,
  ];
  final since = last == null ? 0 : open.map((id) => id - 1).fold(last, min);

  FeedReply? reply;
  final got = await collectPages((since) async {
    final f = await readFeed(post, key, since);
    if (f == null) throw const FormatException('not our router');
    return reply = f;
  }, since);

  final restarted = last != null && got.newest < last;
  if (restarted) await d.store.clearEvents(r.id);
  await d.store.saveEvents(r.id, got.events);
  final back = {for (final e in got.events) e.id};
  await d.store.removeEvents(r.id, {
    for (final id in open)
      if (!back.contains(id)) id,
  });
  if (got.trimmed) await d.store.setTrimmed(r.id, true);
  if (last != null && !restarted) {
    final plan = planNotifications(
      [
        for (final e in got.events)
          if (e.id > last) e,
      ],
      reply!.settings,
      phoneMuted: await d.phoneMuted(),
    );
    if (plan is! NotifyNone) await d.notify(plan, routerLabel(r));
  }
  await d.store.setLastId(r.id, got.newest);
  return reply!;
}

WidgetSnapshot _snapshot(Router r, FeedReply f, DateTime now) => WidgetSnapshot(
  routerName: routerLabel(r),
  online: f.online,
  bars: f.rsrp == null ? null : signalBars(f.rsrp!),
  dataLine: f.plan == null ? null : dataLines(f.plan!, now).first,
  data: dataWidgetLines(f.plan, now),
  signal: signalLine(bands: f.bands, rsrp: f.rsrp, sinr: f.sinr),
  at: now,
);

bool hasWifi(Iterable<String> interfaces) =>
    interfaces.any((n) => n.startsWith('wlan') || n.startsWith('eth'));

Future<bool> _onWifi() async =>
    hasWifi((await NetworkInterface.list()).map((i) => i.name));

@pragma('vm:entry-point')
void backgroundMain() {
  Workmanager().executeTask((_, _) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final secure = SecureStorageService();
      final store = AlertsStore(prefs);
      await runBackgroundCheck(
        CheckDeps(
          onWifi: _onWifi,
          routers: secure.getRouters,
          readKey: (id) => secure.readValue(alertsKeyName(id)),
          post: (r) async => httpFeed(r),
          store: store,
          phoneMuted: () async => store.muted,
          notify: showAlerts,
          saveWidget: (s) => saveWidgetSnapshot(prefs, s),
          now: DateTime.now,
        ),
      );
    } catch (_) {}
    return true;
  });
}

class BackgroundPrefs {
  BackgroundPrefs(this._p);
  final SharedPreferences _p;

  static const _name = 'alerts.interval';

  Duration? get interval {
    final m = _p.getInt(_name) ?? 0;
    return m <= 0 ? null : Duration(minutes: max(15, m));
  }

  Future<void> setInterval(Duration? d) => _p.setInt(_name, d?.inMinutes ?? 0);
}

Future<void> startBackground({bool changed = false}) async {
  if (!Platform.isAndroid) return;
  try {
    final every = BackgroundPrefs(
      await SharedPreferences.getInstance(),
    ).interval;
    final w = Workmanager();
    await w.initialize(backgroundMain);
    if (every == null) {
      if (changed) await w.cancelByUniqueName(_task);
      return;
    }
    await w.registerPeriodicTask(
      _task,
      _task,
      frequency: every,
      existingWorkPolicy: changed
          ? ExistingPeriodicWorkPolicy.replace
          : ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e, stack) {
    Logger.exception('Could not schedule background checks', e, stack);
  }
}
