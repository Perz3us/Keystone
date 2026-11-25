// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

enum ScheduleDay {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension ScheduleDayExtension on ScheduleDay {
  String get shortLabel {
    switch (this) {
      case ScheduleDay.monday:
        return 'Mon';
      case ScheduleDay.tuesday:
        return 'Tue';
      case ScheduleDay.wednesday:
        return 'Wed';
      case ScheduleDay.thursday:
        return 'Thu';
      case ScheduleDay.friday:
        return 'Fri';
      case ScheduleDay.saturday:
        return 'Sat';
      case ScheduleDay.sunday:
        return 'Sun';
    }
  }

  String get longLabel {
    switch (this) {
      case ScheduleDay.monday:
        return 'Monday';
      case ScheduleDay.tuesday:
        return 'Tuesday';
      case ScheduleDay.wednesday:
        return 'Wednesday';
      case ScheduleDay.thursday:
        return 'Thursday';
      case ScheduleDay.friday:
        return 'Friday';
      case ScheduleDay.saturday:
        return 'Saturday';
      case ScheduleDay.sunday:
        return 'Sunday';
    }
  }

  int get cronIndex {
    switch (this) {
      case ScheduleDay.sunday:
        return 0;
      case ScheduleDay.monday:
        return 1;
      case ScheduleDay.tuesday:
        return 2;
      case ScheduleDay.wednesday:
        return 3;
      case ScheduleDay.thursday:
        return 4;
      case ScheduleDay.friday:
        return 5;
      case ScheduleDay.saturday:
        return 6;
    }
  }

  String get uciWeekday {
    switch (this) {
      case ScheduleDay.monday:
        return 'Mon';
      case ScheduleDay.tuesday:
        return 'Tue';
      case ScheduleDay.wednesday:
        return 'Wed';
      case ScheduleDay.thursday:
        return 'Thu';
      case ScheduleDay.friday:
        return 'Fri';
      case ScheduleDay.saturday:
        return 'Sat';
      case ScheduleDay.sunday:
        return 'Sun';
    }
  }

  ScheduleDay get nextDay => ScheduleDay.values[(index + 1) % 7];

  static ScheduleDay fromIndex(int index) => ScheduleDay.values[index];

  static ScheduleDay? parse(dynamic value) {
    if (value == null) return null;
    if (value is ScheduleDay) return value;
    if (value is int && value >= 0 && value < ScheduleDay.values.length) {
      return ScheduleDay.values[value];
    }
    final s = value.toString().trim().toLowerCase();
    final asInt = int.tryParse(s);
    if (asInt != null && asInt >= 0 && asInt < ScheduleDay.values.length) {
      return ScheduleDay.values[asInt];
    }
    switch (s) {
      case 'mon':
      case 'monday':
        return ScheduleDay.monday;
      case 'tue':
      case 'tuesday':
        return ScheduleDay.tuesday;
      case 'wed':
      case 'wednesday':
        return ScheduleDay.wednesday;
      case 'thu':
      case 'thursday':
        return ScheduleDay.thursday;
      case 'fri':
      case 'friday':
        return ScheduleDay.friday;
      case 'sat':
      case 'saturday':
        return ScheduleDay.saturday;
      case 'sun':
      case 'sunday':
        return ScheduleDay.sunday;
      default:
        return null;
    }
  }
}

enum ContentFilterDns {
  none,
  cloudflareFamilySafe,
  openDnsFamilyShield,
  custom,
}

extension ContentFilterDnsExtension on ContentFilterDns {
  String get label {
    switch (this) {
      case ContentFilterDns.none:
        return 'None (Router Default)';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'Cloudflare Family (1.1.1.3)';
      case ContentFilterDns.openDnsFamilyShield:
        return 'OpenDNS Family Shield';
      case ContentFilterDns.custom:
        return 'Custom DNS';
    }
  }

  List<String> get primaryServers {
    switch (this) {
      case ContentFilterDns.none:
        return [];
      case ContentFilterDns.cloudflareFamilySafe:
        return ['1.1.1.3', '1.0.0.3'];
      case ContentFilterDns.openDnsFamilyShield:
        return ['208.67.222.123', '208.67.220.123'];
      case ContentFilterDns.custom:
        return [];
    }
  }

  String get description {
    switch (this) {
      case ContentFilterDns.none:
        return 'Devices use the router\'s DNS, with no filter.';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'Blocks malware, adult content. Uses Cloudflare 1.1.1.3 / 1.0.0.3.';
      case ContentFilterDns.openDnsFamilyShield:
        return 'Blocks adult content via OpenDNS 208.67.222.123 / 208.67.220.123.';
      case ContentFilterDns.custom:
        return 'Use custom upstream DNS addresses for this profile.';
    }
  }

  String toStorageString() {
    switch (this) {
      case ContentFilterDns.none:
        return 'none';
      case ContentFilterDns.cloudflareFamilySafe:
        return 'cloudflare_family';
      case ContentFilterDns.openDnsFamilyShield:
        return 'opendns_family';
      case ContentFilterDns.custom:
        return 'custom';
    }
  }
}

ContentFilterDns contentFilterDnsFromString(String? value) {
  switch (value) {
    case 'cloudflare_family':
      return ContentFilterDns.cloudflareFamilySafe;
    case 'opendns_family':
      return ContentFilterDns.openDnsFamilyShield;
    case 'custom':
      return ContentFilterDns.custom;
    default:
      return ContentFilterDns.none;
  }
}

class TimeSchedule {
  final Set<ScheduleDay> activeDays;

  final int blockHour;
  final int blockMinute;

  final int resumeHour;
  final int resumeMinute;

  final bool enabled;

  const TimeSchedule({
    required this.activeDays,
    required this.blockHour,
    required this.blockMinute,
    required this.resumeHour,
    required this.resumeMinute,
    this.enabled = true,
  });

  String get blockTimeFormatted =>
      '${blockHour.toString().padLeft(2, '0')}:${blockMinute.toString().padLeft(2, '0')}';

  String get resumeTimeFormatted =>
      '${resumeHour.toString().padLeft(2, '0')}:${resumeMinute.toString().padLeft(2, '0')}';

  String get activeDaysLabel {
    if (activeDays.length == 7) {
      return 'Every day';
    }
    if (activeDays.containsAll([ScheduleDay.saturday, ScheduleDay.sunday]) &&
        activeDays.length == 2) {
      return 'Weekends';
    }
    if (activeDays
                .where(
                  (d) => d != ScheduleDay.saturday && d != ScheduleDay.sunday,
                )
                .length ==
            5 &&
        !activeDays.contains(ScheduleDay.saturday) &&
        !activeDays.contains(ScheduleDay.sunday)) {
      return 'Weekdays';
    }
    final sorted = activeDays.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return sorted.map((d) => d.shortLabel).join(', ');
  }

  bool isTimeInBlockWindow([DateTime? now]) {
    if (!enabled || activeDays.isEmpty) return false;
    final dt = (now ?? DateTime.now()).toLocal();
    final dayOfWeek = dt.weekday;
    final today = ScheduleDay.values[(dayOfWeek - 1) % 7];
    final yesterday = ScheduleDay.values[(dayOfWeek - 2 + 7) % 7];

    final currentMin = dt.hour * 60 + dt.minute;
    final blockMin = blockHour * 60 + blockMinute;
    final resumeMin = resumeHour * 60 + resumeMinute;

    if (blockMin < resumeMin) {
      if (!activeDays.contains(today)) return false;
      return currentMin >= blockMin && currentMin < resumeMin;
    } else if (blockMin > resumeMin) {
      if (currentMin >= blockMin) {
        return activeDays.contains(today);
      } else if (currentMin < resumeMin) {
        return activeDays.contains(yesterday);
      } else {
        return false;
      }
    } else {
      return activeDays.contains(today);
    }
  }

  TimeSchedule copyWith({
    Set<ScheduleDay>? activeDays,
    int? blockHour,
    int? blockMinute,
    int? resumeHour,
    int? resumeMinute,
    bool? enabled,
  }) {
    return TimeSchedule(
      activeDays: activeDays ?? this.activeDays,
      blockHour: blockHour ?? this.blockHour,
      blockMinute: blockMinute ?? this.blockMinute,
      resumeHour: resumeHour ?? this.resumeHour,
      resumeMinute: resumeMinute ?? this.resumeMinute,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'active_days': activeDays.map((d) => d.index).toList(),
    'block_hour': blockHour,
    'block_minute': blockMinute,
    'resume_hour': resumeHour,
    'resume_minute': resumeMinute,
    'enabled': enabled,
  };

  factory TimeSchedule.fromJson(Map<String, dynamic> json) {
    Set<ScheduleDay> days = {};
    final rawDays = json['active_days'] ?? json['schedule_days'];
    if (rawDays is List) {
      days = rawDays
          .map((e) => ScheduleDayExtension.parse(e))
          .whereType<ScheduleDay>()
          .toSet();
    } else if (rawDays is String && rawDays.isNotEmpty) {
      days = rawDays
          .split(RegExp(r'\s+'))
          .map((e) => ScheduleDayExtension.parse(e))
          .whereType<ScheduleDay>()
          .toSet();
    }

    final rawBlockH = json['block_hour'] ?? json['schedule_block_hour'];
    final blockH = rawBlockH is num
        ? rawBlockH.toInt()
        : (int.tryParse(rawBlockH?.toString() ?? '') ?? 22);

    final rawBlockM =
        json['block_minute'] ??
        json['schedule_block_min'] ??
        json['schedule_block_minute'];
    final blockM = rawBlockM is num
        ? rawBlockM.toInt()
        : (int.tryParse(rawBlockM?.toString() ?? '') ?? 0);

    final rawResumeH = json['resume_hour'] ?? json['schedule_resume_hour'];
    final resumeH = rawResumeH is num
        ? rawResumeH.toInt()
        : (int.tryParse(rawResumeH?.toString() ?? '') ?? 7);

    final rawResumeM =
        json['resume_minute'] ??
        json['schedule_resume_min'] ??
        json['schedule_resume_minute'];
    final resumeM = rawResumeM is num
        ? rawResumeM.toInt()
        : (int.tryParse(rawResumeM?.toString() ?? '') ?? 0);

    final rawEnabled = json['enabled'] ?? json['schedule_enabled'];
    final bool isEnabled =
        rawEnabled == null ||
        rawEnabled == true ||
        rawEnabled == '1' ||
        rawEnabled == 'true';

    if (days.isEmpty &&
        (isEnabled ||
            rawBlockH != null ||
            json['schedule_block_hour'] != null)) {
      days = ScheduleDay.values.toSet();
    }

    return TimeSchedule(
      activeDays: days,
      blockHour: blockH,
      blockMinute: blockM,
      resumeHour: resumeH,
      resumeMinute: resumeM,
      enabled: isEnabled,
    );
  }
}

enum PauseDuration {
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  untilTomorrow,
  indefinite,
}

extension PauseDurationExtension on PauseDuration {
  String get label {
    switch (this) {
      case PauseDuration.fifteenMinutes:
        return '15 Minutes';
      case PauseDuration.thirtyMinutes:
        return '30 Minutes';
      case PauseDuration.oneHour:
        return '1 Hour';
      case PauseDuration.untilTomorrow:
        return 'Until Tomorrow';
      case PauseDuration.indefinite:
        return 'Until I Resume';
    }
  }

  Duration? get duration {
    switch (this) {
      case PauseDuration.fifteenMinutes:
        return const Duration(minutes: 15);
      case PauseDuration.thirtyMinutes:
        return const Duration(minutes: 30);
      case PauseDuration.oneHour:
        return const Duration(hours: 1);
      case PauseDuration.untilTomorrow:
        return null;
      case PauseDuration.indefinite:
        return null;
    }
  }
}

const List<String> kProfileIcons = [
  '👦',
  '👧',
  '👶',
  '🧒',
  '👩',
  '👨',
  '🎮',
  '📱',
  '💻',
  '🖥',
  '📺',
  '🎵',
  '⭐',
  '🌟',
  '🏠',
  '🐱',
  '🐶',
  '🐰',
  '🦁',
  '🐼',
];

class ParentalProfile {
  final String id;
  final String name;
  final String icon;
  final String color;

  final List<String> macAddresses;

  final bool isPaused;

  final bool isEnabled;

  final DateTime? pauseExpiresAt;

  final TimeSchedule? schedule;

  final int? dailyTimeLimitMinutes;

  final ContentFilterDns contentFilter;

  final List<String> customDnsServers;

  const ParentalProfile({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.macAddresses,
    this.isPaused = false,
    this.isEnabled = true,
    this.pauseExpiresAt,
    this.schedule,
    this.dailyTimeLimitMinutes,
    this.contentFilter = ContentFilterDns.none,
    this.customDnsServers = const [],
  });

  bool get hasMacs => macAddresses.isNotEmpty;
  bool get isBypassed => !isEnabled;
  bool get hasSchedule =>
      schedule != null && schedule!.enabled && schedule!.activeDays.isNotEmpty;
  bool get isScheduleBlocked => hasSchedule && schedule!.isTimeInBlockWindow();
  bool isDailyLimitReached([int? minutesUsed]) =>
      hasTimeLimit && (minutesUsed ?? 0) >= dailyTimeLimitMinutes!;
  bool isCurrentlyBlocked([int? minutesUsed]) =>
      isEnabled &&
      (isPaused || isScheduleBlocked || isDailyLimitReached(minutesUsed));
  bool get hasTimeLimit =>
      dailyTimeLimitMinutes != null && dailyTimeLimitMinutes! > 0;
  bool get hasContentFilter => contentFilter != ContentFilterDns.none;

  bool get isTimedPause =>
      isPaused &&
      pauseExpiresAt != null &&
      pauseExpiresAt!.isAfter(DateTime.now().toUtc());

  Duration? get timeRemainingInPause {
    if (!isTimedPause || pauseExpiresAt == null) return null;
    final remaining = pauseExpiresAt!.difference(DateTime.now().toUtc());
    return remaining.isNegative ? null : remaining;
  }

  ParentalProfile copyWith({
    String? name,
    String? icon,
    String? color,
    List<String>? macAddresses,
    bool? isPaused,
    bool? isEnabled,
    Object? pauseExpiresAt = _sentinel,
    Object? schedule = _sentinel,
    int? dailyTimeLimitMinutes,
    Object? clearDailyLimit = _sentinel,
    ContentFilterDns? contentFilter,
    List<String>? customDnsServers,
  }) {
    return ParentalProfile(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      macAddresses: macAddresses ?? this.macAddresses,
      isPaused: isPaused ?? this.isPaused,
      isEnabled: isEnabled ?? this.isEnabled,
      pauseExpiresAt: pauseExpiresAt == _sentinel
          ? this.pauseExpiresAt
          : pauseExpiresAt as DateTime?,
      schedule: schedule == _sentinel
          ? this.schedule
          : schedule as TimeSchedule?,
      dailyTimeLimitMinutes: clearDailyLimit != _sentinel
          ? null
          : (dailyTimeLimitMinutes ?? this.dailyTimeLimitMinutes),
      contentFilter: contentFilter ?? this.contentFilter,
      customDnsServers: customDnsServers ?? this.customDnsServers,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color,
    'mac_addresses': macAddresses,
    'is_paused': isPaused,
    'is_enabled': isEnabled,
    'pause_expires_at': pauseExpiresAt?.toUtc().toIso8601String(),
    'schedule': schedule?.toJson(),
    'daily_time_limit_minutes':
        (dailyTimeLimitMinutes != null && dailyTimeLimitMinutes! > 0)
        ? dailyTimeLimitMinutes
        : null,
    'content_filter': contentFilter.toStorageString(),
    'custom_dns_servers': customDnsServers,
  };

  factory ParentalProfile.fromJson(
    Map<String, dynamic> json, [
    String? fallbackId,
  ]) {
    DateTime? expiresAt;
    final rawExpiry = (json['pause_expires_at'] ?? json['pauseExpiresAt'])
        ?.toString();
    if (rawExpiry != null && rawExpiry.isNotEmpty) {
      final asInt = int.tryParse(rawExpiry);
      if (asInt != null && asInt > 1000000000) {
        final ms = asInt > 100000000000 ? asInt : asInt * 1000;
        expiresAt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
      } else {
        expiresAt = DateTime.tryParse(rawExpiry)?.toUtc();
      }
    }

    final List<String> macs = [];
    final rawMacs = json['mac_addresses'] ?? json['mac'];
    if (rawMacs is List) {
      macs.addAll(rawMacs.map((e) => e.toString()));
    } else if (rawMacs is String && rawMacs.isNotEmpty) {
      macs.addAll(rawMacs.split(RegExp(r'\s+')));
    }

    final List<String> customDns = [];
    final rawDns = json['custom_dns_servers'] ?? json['custom_dns'];
    if (rawDns is List) {
      customDns.addAll(rawDns.map((e) => e.toString()));
    } else if (rawDns is String && rawDns.isNotEmpty) {
      customDns.addAll(rawDns.split(RegExp(r'\s+')));
    }

    final rawPaused = json['is_paused'];
    final bool isPaused =
        rawPaused == true || rawPaused == '1' || rawPaused == 'true';

    final rawEnabled = json['is_enabled'];
    final bool isEnabled =
        rawEnabled != false && rawEnabled != '0' && rawEnabled != 'false';

    TimeSchedule? schedule;
    if (json['schedule'] is Map) {
      schedule = TimeSchedule.fromJson(
        Map<String, dynamic>.from(json['schedule'] as Map),
      );
    } else if (json['schedule_enabled'] != null ||
        json['schedule_days'] != null ||
        json['schedule_block_hour'] != null) {
      schedule = TimeSchedule.fromJson(json);
    }

    final rawDaily = json['daily_time_limit_minutes'] ?? json['daily_limit'];
    final int? parsedDaily = rawDaily is num
        ? rawDaily.toInt()
        : (int.tryParse(rawDaily?.toString() ?? ''));
    final int? dailyLimit = (parsedDaily != null && parsedDaily > 0)
        ? parsedDaily
        : null;

    return ParentalProfile(
      id:
          json['id']?.toString() ??
          json['.name']?.toString() ??
          fallbackId ??
          '',
      name: json['name']?.toString() ?? 'Profile',
      icon: json['icon']?.toString() ?? '👦',
      color: json['color']?.toString() ?? '#F97316',
      macAddresses: macs,
      isPaused: isPaused,
      isEnabled: isEnabled,
      pauseExpiresAt: expiresAt,
      schedule: schedule,
      dailyTimeLimitMinutes: dailyLimit,
      contentFilter: contentFilterDnsFromString(
        json['content_filter']?.toString(),
      ),
      customDnsServers: customDns,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ParentalProfile.fromJsonString(String s) =>
      ParentalProfile.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
}

const Object _sentinel = Object();

enum ParentalEventType {
  paused,
  resumed,
  schedulePaused,
  scheduleResumed,
  limitReached,
  limitOverridden,
  profileCreated,
  profileDeleted,
  profileUpdated,
  contentFilterApplied,
}

extension ParentalEventTypeExtension on ParentalEventType {
  String get label {
    switch (this) {
      case ParentalEventType.paused:
        return 'Paused';
      case ParentalEventType.resumed:
        return 'Resumed';
      case ParentalEventType.schedulePaused:
        return 'Schedule: Blocked';
      case ParentalEventType.scheduleResumed:
        return 'Schedule: Unblocked';
      case ParentalEventType.limitReached:
        return 'Daily Limit Reached';
      case ParentalEventType.limitOverridden:
        return 'Limit Overridden (+30 min)';
      case ParentalEventType.profileCreated:
        return 'Profile Created';
      case ParentalEventType.profileDeleted:
        return 'Profile Deleted';
      case ParentalEventType.profileUpdated:
        return 'Profile Updated';
      case ParentalEventType.contentFilterApplied:
        return 'Content Filter Applied';
    }
  }
}

class ParentalActivityLog {
  final String profileId;
  final String profileName;
  final ParentalEventType eventType;
  final DateTime timestamp;
  final String? detail;

  const ParentalActivityLog({
    required this.profileId,
    required this.profileName,
    required this.eventType,
    required this.timestamp,
    this.detail,
  });

  Map<String, dynamic> toJson() => {
    'profile_id': profileId,
    'profile_name': profileName,
    'event_type': eventType.name,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'detail': detail,
  };

  factory ParentalActivityLog.fromJson(Map<String, dynamic> json) {
    final typeStr = json['event_type']?.toString() ?? '';
    final eventType = ParentalEventType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => ParentalEventType.paused,
    );
    return ParentalActivityLog(
      profileId: json['profile_id']?.toString() ?? '',
      profileName: json['profile_name']?.toString() ?? '',
      eventType: eventType,
      timestamp:
          DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      detail: json['detail']?.toString(),
    );
  }
}
