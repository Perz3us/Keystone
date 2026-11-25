// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/parental_controls_store.dart';
import '../models/parental_profile.dart';

String hhmm(int h, int m) =>
    '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

String limitWords(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

int minutesUsed(ParentalProfile p, ParentalControlsStore store) =>
    p.macAddresses.fold(0, (a, m) {
      final u = store.getDailyMinutesUsed(m);
      return u > a ? u : a;
    });

String bedtimeWords(TimeSchedule s) {
  final days = s.activeDays;
  const week = {
    ScheduleDay.monday,
    ScheduleDay.tuesday,
    ScheduleDay.wednesday,
    ScheduleDay.thursday,
    ScheduleDay.friday,
  };
  const nights = {
    ScheduleDay.sunday,
    ScheduleDay.monday,
    ScheduleDay.tuesday,
    ScheduleDay.wednesday,
    ScheduleDay.thursday,
  };
  final when = days.length == 7
      ? 'every day'
      : days.length == 5 && days.containsAll(week)
      ? 'weekdays'
      : days.length == 5 && days.containsAll(nights)
      ? 'school nights'
      : days.length == 2 &&
            days.containsAll({ScheduleDay.saturday, ScheduleDay.sunday})
      ? 'weekends'
      : [
          for (final d in ScheduleDay.values)
            if (days.contains(d)) d.shortLabel,
        ].join(', ');
  return '${hhmm(s.blockHour, s.blockMinute)} to '
      '${hhmm(s.resumeHour, s.resumeMinute)}, $when';
}

String filterWords(ContentFilterDns f) => switch (f) {
  ContentFilterDns.none => 'No site filter',
  ContentFilterDns.cloudflareFamilySafe => 'Blocks adult sites and malware',
  ContentFilterDns.openDnsFamilyShield => 'Blocks adult sites',
  ContentFilterDns.custom => 'Your own filter service',
};

String pauseWords(PauseDuration d) => switch (d) {
  PauseDuration.fifteenMinutes => '15 minutes',
  PauseDuration.thirtyMinutes => '30 minutes',
  PauseDuration.oneHour => '1 hour',
  PauseDuration.untilTomorrow => 'Until tomorrow morning',
  PauseDuration.indefinite => 'Until I turn it back on',
};

bool isPausedNow(ParentalProfile p) =>
    p.isEnabled && p.isPaused && (p.pauseExpiresAt == null || p.isTimedPause);

String personStatus(ParentalProfile p, {int used = 0}) {
  if (!p.isEnabled) return 'Rules off, free access';
  if (p.isTimedPause) {
    final t = p.pauseExpiresAt!.toLocal();
    return 'Paused until ${hhmm(t.hour, t.minute)}';
  }
  if (p.isPaused) return 'Paused';
  if (p.isScheduleBlocked) {
    final s = p.schedule!;
    return 'Bedtime until ${hhmm(s.resumeHour, s.resumeMinute)}';
  }
  if (p.isDailyLimitReached(used)) return 'Out of time for today';
  final n = p.macAddresses.length;
  return [
    n == 0 ? 'No devices yet' : '$n device${n == 1 ? '' : 's'}',
    if (p.hasSchedule)
      'bedtime ${hhmm(p.schedule!.blockHour, p.schedule!.blockMinute)}',
    if (p.hasTimeLimit)
      '${limitWords((p.dailyTimeLimitMinutes! - used).clamp(0, 1 << 30))} left today',
  ].join(' · ');
}

String eventWords(ParentalEventType t) => switch (t) {
  ParentalEventType.paused => 'Paused',
  ParentalEventType.resumed => 'Back on',
  ParentalEventType.schedulePaused => 'Bedtime started',
  ParentalEventType.scheduleResumed => 'Bedtime ended',
  ParentalEventType.limitReached => 'Ran out of time',
  ParentalEventType.limitOverridden => 'Got 30 more minutes',
  ParentalEventType.profileCreated => 'Added',
  ParentalEventType.profileDeleted => 'Removed',
  ParentalEventType.profileUpdated => 'Rules changed',
  ParentalEventType.contentFilterApplied => 'Site filter changed',
};
