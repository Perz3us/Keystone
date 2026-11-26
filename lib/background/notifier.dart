// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../modules/noobwrt/alerts/alert_models.dart';
import '../modules/noobwrt/alerts/alert_notify_plan.dart';

const alertsPayload = 'alerts';

final _plugin = FlutterLocalNotificationsPlugin();

AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
    .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin
    >();

const _channel = NotificationDetails(
  android: AndroidNotificationDetails(
    'keystone_alerts',
    'Router alerts',
    channelDescription: 'Outages, new devices, data and signal',
  ),
);

final alertTaps = ValueNotifier<int>(0);

Future<void> initNotifications() async {
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_keystone'),
    ),
    onDidReceiveNotificationResponse: (r) {
      if (r.payload == alertsPayload) alertTaps.value++;
    },
  );
}

Future<void> listenForAlertTaps() async {
  await initNotifications();
  final launch = await _plugin.getNotificationAppLaunchDetails();
  if (launch?.didNotificationLaunchApp == true &&
      launch?.notificationResponse?.payload == alertsPayload) {
    alertTaps.value++;
  }
}

Future<bool> notificationsAllowed() async =>
    await _android?.areNotificationsEnabled() ?? false;

Future<bool> askForNotifications() async =>
    await _android?.requestNotificationsPermission() ?? false;

Future<void> showAlerts(NotifyPlan plan, String routerName) async {
  await initNotifications();
  switch (plan) {
    case NotifyNone():
      return;
    case NotifyOne(:final event):
      await _plugin.show(
        id: Object.hash(routerName, event.id) & 0x7fffffff,
        title: alertTitle(event),
        body: routerName,
        notificationDetails: _channel,
        payload: alertsPayload,
      );
    case NotifySummary(:final events):
      await _plugin.show(
        id: routerName.hashCode & 0x7fffffff,
        title: '${events.length} events while you were away',
        body: '$routerName · Latest: ${alertTitle(events.last)}',
        notificationDetails: _channel,
        payload: alertsPayload,
      );
  }
}
