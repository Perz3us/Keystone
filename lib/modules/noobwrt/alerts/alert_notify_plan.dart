// SPDX-License-Identifier: GPL-3.0-or-later

import 'alert_models.dart';

sealed class NotifyPlan {
  const NotifyPlan();
}

class NotifyNone extends NotifyPlan {
  const NotifyNone();
}

class NotifyOne extends NotifyPlan {
  const NotifyOne(this.event);
  final AlertEvent event;
}

class NotifySummary extends NotifyPlan {
  const NotifySummary(this.events);
  final List<AlertEvent> events;
  int get count => events.length;
}

NotifyPlan planNotifications(
  List<AlertEvent> fresh,
  AlertSettings s, {
  required bool phoneMuted,
}) {
  final loud = [
    for (final e in fresh)
      if (s.modes[e.type] == AlertMode.buzz) e,
  ];
  if (phoneMuted || loud.isEmpty) return const NotifyNone();
  return loud.length == 1 ? NotifyOne(loud.single) : NotifySummary(loud);
}
