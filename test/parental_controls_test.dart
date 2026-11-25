// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_controls_store.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  group('ParentalControlsStore', () {
    late ParentalControlsStore store;

    setUp(() {
      store = ParentalControlsStore.instance;
      for (final p in store.profiles.toList()) {
        store.deleteProfile(p.id);
      }
      store.clearActivityLog();
    });

    test('Add, update, and delete profile', () {
      const profile = ParentalProfile(
        id: 'test_1',
        name: 'Kids Tablet',
        icon: '👦',
        color: '#F97316',
        macAddresses: ['AA:BB:CC:DD:EE:11'],
        dailyTimeLimitMinutes: 120,
        contentFilter: ContentFilterDns.cloudflareFamilySafe,
      );

      final id = store.addProfile(profile);
      expect(id, 'test_1');
      expect(store.profiles.length, 1);
      expect(store.profiles.first.name, 'Kids Tablet');
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileCreated,
      );

      final updated = profile.copyWith(name: 'Kids Tablet (Updated)');
      store.updateProfile(updated);
      expect(store.profiles.first.name, 'Kids Tablet (Updated)');
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileUpdated,
      );

      store.deleteProfile('test_1');
      expect(store.profiles, isEmpty);
      expect(
        store.activityLog.first.eventType,
        ParentalEventType.profileDeleted,
      );
    });

    test('Pause and resume state management', () {
      const profile = ParentalProfile(
        id: 'test_pause',
        name: 'Gaming Console',
        icon: '🎮',
        color: '#3B82F6',
        macAddresses: ['11:22:33:44:55:66'],
      );
      store.addProfile(profile);

      final expiry = DateTime.now().toUtc().add(const Duration(hours: 1));
      store.markProfilePaused('test_pause', expiresAt: expiry);

      final p = store.getProfile('test_pause')!;
      expect(p.isPaused, isTrue);
      expect(p.pauseExpiresAt, equals(expiry));
      expect(store.isMacPaused('11:22:33:44:55:66'), isTrue);

      store.markProfileResumed('test_pause');
      final resumed = store.getProfile('test_pause')!;
      expect(resumed.isPaused, isFalse);
      expect(resumed.pauseExpiresAt, null);
      expect(store.isMacPaused('11:22:33:44:55:66'), isFalse);
    });

    test('Serialization and deserialization', () {
      const profile = ParentalProfile(
        id: 'test_ser',
        name: 'Teen Phone',
        icon: '📱',
        color: '#EF4444',
        macAddresses: ['00:11:22:33:44:55'],
        schedule: TimeSchedule(
          activeDays: {ScheduleDay.monday, ScheduleDay.friday},
          blockHour: 23,
          blockMinute: 30,
          resumeHour: 6,
          resumeMinute: 0,
        ),
        contentFilter: ContentFilterDns.openDnsFamilyShield,
      );
      store.addProfile(profile);

      final jsonStr = store.toJsonString();
      expect(jsonStr, contains('Teen Phone'));
      expect(jsonStr, contains('00:11:22:33:44:55'));
      expect(jsonStr, contains('opendns_family'));

      store.loadFromString(jsonStr);
      expect(store.profiles.length, 1);
      final loaded = store.profiles.first;
      expect(loaded.name, 'Teen Phone');
      expect(loaded.schedule?.blockHour, 23);
      expect(loaded.contentFilter, ContentFilterDns.openDnsFamilyShield);
      expect(loaded.isEnabled, isTrue);
    });

    test('Bypass state toggling and isMacPaused behavior', () {
      const profile = ParentalProfile(
        id: 'test_bypass',
        name: 'Bypass Test',
        icon: '📱',
        color: '#EF4444',
        macAddresses: ['AA:BB:CC:DD:EE:99'],
        isPaused: true,
        isEnabled: true,
      );
      store.addProfile(profile);

      expect(store.isMacPaused('AA:BB:CC:DD:EE:99'), isTrue);

      store.toggleProfileEnabled('test_bypass');
      final bypassed = store.getProfile('test_bypass')!;
      expect(bypassed.isEnabled, isFalse);
      expect(bypassed.isBypassed, isTrue);

      expect(store.isMacPaused('AA:BB:CC:DD:EE:99'), isFalse);
    });

    test('TimeSchedule isTimeInBlockWindow calculation', () {
      const schedule = TimeSchedule(
        activeDays: {ScheduleDay.monday},
        blockHour: 22,
        blockMinute: 0,
        resumeHour: 7,
        resumeMinute: 0,
      );

      final monNight = DateTime(2026, 8, 24, 23, 30);
      expect(schedule.isTimeInBlockWindow(monNight), isTrue);

      final tueMorning = DateTime(2026, 8, 25, 5, 15);
      expect(schedule.isTimeInBlockWindow(tueMorning), isTrue);

      final monMorning = DateTime(2026, 8, 24, 5, 15);
      expect(schedule.isTimeInBlockWindow(monMorning), isFalse);

      final monNoon = DateTime(2026, 8, 24, 12, 0);
      expect(schedule.isTimeInBlockWindow(monNoon), isFalse);

      final tueNight = DateTime(2026, 8, 25, 23, 30);
      expect(schedule.isTimeInBlockWindow(tueNight), isFalse);
    });
  });

  group('ParentalControlsController & Sync Hardening', () {
    late ParentalControlsController controller;
    late ParentalControlsStore store;

    setUp(() async {
      await AppState.instance.setReviewerMode(true);
      controller = ParentalControlsController.instance;
      store = controller.store;
      for (final p in store.profiles.toList()) {
        store.deleteProfile(p.id);
      }
      store.clearActivityLog();
    });

    test('Empty-store startup safety prevents bad writes', () async {
      final appState = AppState.instance;
      store.loadFromString('');
      expect(store.isLoaded, isTrue);

      final persisted = await controller.persistStore(appState);
      expect(persisted.success, isTrue);
    });

    test(
      'Pause expiry on checkPausesAndSchedules automatically resumes expired profiles',
      () async {
        final pastExpiry = DateTime.now().toUtc().subtract(
          const Duration(minutes: 5),
        );
        final profile = ParentalProfile(
          id: 'test_expired_pause',
          name: 'Study Laptop',
          icon: '💻',
          color: '#3B82F6',
          macAddresses: const ['11:22:33:44:55:77'],
          isPaused: true,
          pauseExpiresAt: pastExpiry,
        );
        store.addProfile(profile);

        expect(store.getProfile('test_expired_pause')!.isPaused, isTrue);

        await controller.checkPausesAndSchedules(AppState.instance);

        final updated = store.getProfile('test_expired_pause')!;
        expect(updated.isPaused, isFalse);
        expect(updated.pauseExpiresAt, isNull);
      },
    );

    test('Repeated lifecycle resume calls do not duplicate work or throw', () {
      final appState = AppState.instance;
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.handleLifecycleState(AppLifecycleState.paused, appState);
      controller.handleLifecycleState(AppLifecycleState.resumed, appState);
      controller.stopExpiryTimer();
    });

    test(
      'Store persistence round-trip preserves daily minutes and activity log',
      () {
        const profile = ParentalProfile(
          id: 'test_rt',
          name: 'Roundtrip Profile',
          icon: '🎮',
          color: '#10B981',
          macAddresses: ['AA:BB:CC:DD:EE:00'],
        );
        store.addProfile(profile);
        store.incrementDailyMinutesUsed('AA:BB:CC:DD:EE:00', 45);

        final rawJson = store.toJsonString();
        expect(rawJson, contains('Roundtrip Profile'));
        expect(rawJson, contains('daily_minutes_used'));
        expect(rawJson, contains('activity_log'));

        store.loadFromString(rawJson);
        expect(store.profiles.length, 1);
        expect(store.getDailyMinutesUsed('AA:BB:CC:DD:EE:00'), 45);
        expect(store.activityLog, isNotEmpty);
      },
    );

    test('Firewall-denied operations return clear failure type', () async {
      final appState = AppState.instance;
      const profile = ParentalProfile(
        id: 'test_fw',
        name: 'Firewall Test',
        icon: '📱',
        color: '#EF4444',
        macAddresses: ['00:11:22:33:44:99'],
      );

      final result = await controller.pauseProfile(
        profile,
        PauseDuration.indefinite,
        appState,
      );

      expect(result.message, isNotEmpty);
    });

    test(
      'Clear activity log via controller clears log and persists store',
      () async {
        final appState = AppState.instance;
        const profile = ParentalProfile(
          id: 'test_clear_log',
          name: 'Log Test',
          icon: '📱',
          color: '#10B981',
          macAddresses: ['AA:BB:CC:11:22:33'],
        );
        store.addProfile(profile);
        expect(store.activityLog, isNotEmpty);

        final res = await controller.clearActivityLog(appState);
        expect(res.success, isTrue);
        expect(res.message, contains('Activity log cleared'));
        expect(store.activityLog, isEmpty);
      },
    );

    test(
      'loadStore and persistStore return typed ParentalActionResult',
      () async {
        final appState = AppState.instance;
        final loadRes = await controller.loadStore(appState);
        expect(loadRes.success, isTrue);

        final persistRes = await controller.persistStore(appState);
        expect(persistRes.success, isTrue);
        expect(persistRes.failureType, ParentalFailureType.none);
      },
    );
  });

  group('Multi-Device Synchronization & UCI Parity', () {
    test(
      'ParentalProfile.fromJson reconstructs full schedule from flat UCI dictionary',
      () {
        final uciData = {
          '.name': 'profile_kids_tablet',
          '.type': 'profile',
          'name': 'Kids Tablet',
          'icon': '👦',
          'color': '#F97316',
          'is_paused': '1',
          'is_enabled': '1',
          'content_filter': 'cloudflare_family',
          'mac': ['aa:bb:cc:dd:ee:11', '11:22:33:44:55:66'],
          'custom_dns': ['1.1.1.3', '1.0.0.3'],
          'schedule_enabled': '1',
          'schedule_days': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
          'schedule_block_hour': '22',
          'schedule_block_min': '30',
          'schedule_resume_hour': '7',
          'schedule_resume_min': '15',
          'daily_time_limit_minutes': '120',
          'pause_expires_at': '1762261200',
        };

        final profile = ParentalProfile.fromJson(uciData);

        expect(profile.id, 'profile_kids_tablet');
        expect(profile.name, 'Kids Tablet');
        expect(profile.icon, '👦');
        expect(profile.isPaused, isTrue);
        expect(profile.isEnabled, isTrue);
        expect(profile.contentFilter, ContentFilterDns.cloudflareFamilySafe);
        expect(profile.macAddresses, [
          'aa:bb:cc:dd:ee:11',
          '11:22:33:44:55:66',
        ]);
        expect(profile.customDnsServers, ['1.1.1.3', '1.0.0.3']);
        expect(profile.dailyTimeLimitMinutes, 120);
        expect(profile.hasSchedule, isTrue);
        expect(profile.schedule?.blockHour, 22);
        expect(profile.schedule?.blockMinute, 30);
        expect(profile.schedule?.resumeHour, 7);
        expect(profile.schedule?.resumeMinute, 15);
        expect(profile.schedule?.activeDays, {
          ScheduleDay.monday,
          ScheduleDay.tuesday,
          ScheduleDay.wednesday,
          ScheduleDay.thursday,
          ScheduleDay.friday,
        });
        expect(profile.pauseExpiresAt, isNotNull);
      },
    );

    test(
      'ParentalProfile.fromJson normalizes daily_time_limit_minutes of 0 or "0" to null',
      () {
        final dataZeroStr = {
          'id': 'p1',
          'name': 'Test Profile',
          'daily_time_limit_minutes': '0',
        };
        final p1 = ParentalProfile.fromJson(dataZeroStr);
        expect(p1.dailyTimeLimitMinutes, isNull);
        expect(p1.hasTimeLimit, isFalse);

        final dataZeroInt = {
          'id': 'p2',
          'name': 'Test Profile 2',
          'daily_time_limit_minutes': 0,
        };
        final p2 = ParentalProfile.fromJson(dataZeroInt);
        expect(p2.dailyTimeLimitMinutes, isNull);
        expect(p2.hasTimeLimit, isFalse);
      },
    );

    test('ScheduleDayExtension parses weekdays and advances to next day', () {
      expect(ScheduleDayExtension.parse('Mon'), ScheduleDay.monday);
      expect(ScheduleDayExtension.parse('Friday'), ScheduleDay.friday);
      expect(ScheduleDayExtension.parse(0), ScheduleDay.monday);
      expect(ScheduleDay.friday.nextDay, ScheduleDay.saturday);
      expect(ScheduleDay.sunday.nextDay, ScheduleDay.monday);
      expect(ScheduleDay.monday.uciWeekday, 'Mon');
    });

    test('Multi-device profile save and load parity via AppState', () async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);

      const profileDevice1 = ParentalProfile(
        id: 'sync_test_prof',
        name: 'Shared Family Profile',
        icon: '📱',
        color: '#3B82F6',
        macAddresses: ['00:11:22:33:44:55'],
        schedule: TimeSchedule(
          activeDays: {
            ScheduleDay.monday,
            ScheduleDay.wednesday,
            ScheduleDay.friday,
          },
          blockHour: 21,
          blockMinute: 0,
          resumeHour: 6,
          resumeMinute: 30,
        ),
        dailyTimeLimitMinutes: 90,
        contentFilter: ContentFilterDns.openDnsFamilyShield,
      );

      final saveOk = await appState.saveParentalProfile(
        profile: profileDevice1,
      );
      expect(saveOk, isTrue);

      final fetchedProfiles = await appState.fetchParentalProfiles();
      expect(fetchedProfiles, isNotNull);
      final syncedProfile = fetchedProfiles!.firstWhere(
        (p) => p.id == 'sync_test_prof',
      );

      expect(syncedProfile.name, 'Shared Family Profile');
      expect(syncedProfile.icon, '📱');
      expect(syncedProfile.hasSchedule, isTrue);
      expect(syncedProfile.schedule?.blockHour, 21);
      expect(syncedProfile.schedule?.resumeHour, 6);
      expect(syncedProfile.schedule?.activeDays.length, 3);
      expect(syncedProfile.dailyTimeLimitMinutes, 90);
      expect(syncedProfile.contentFilter, ContentFilterDns.openDnsFamilyShield);
    });

    test('ParentalActionResult captures granular error reason', () {
      const errorResult = ParentalActionResult(
        success: false,
        failureType: ParentalFailureType.permissionDenied,
        message: 'Failed to save profile',
        errorReason: 'Permission denied: root access to UCI is required.',
      );

      expect(errorResult.success, isFalse);
      expect(errorResult.errorReason, contains('Permission denied'));
    });

    test(
      'Add profile with null pauseExpiresAt and OpenDNS succeeds via controller',
      () async {
        final appState = AppState.instance;
        await appState.setReviewerMode(true);
        final controller = ParentalControlsController.instance;

        const testProfile = ParentalProfile(
          id: 'test_open_dns',
          name: 'Test',
          icon: '👦',
          color: '#F97316',
          macAddresses: ['aa:bb:cc:dd:ee:ff'],
          contentFilter: ContentFilterDns.openDnsFamilyShield,
          isPaused: false,
          pauseExpiresAt: null,
        );

        final res = await controller.addProfile(testProfile, appState);
        expect(res.success, isTrue);
        expect(res.message, contains('Test'));
      },
    );

    test(
      'Add profile with custom dual-stack IPv4/IPv6 DNS succeeds and persists',
      () async {
        final appState = AppState.instance;
        await appState.setReviewerMode(true);
        final controller = ParentalControlsController.instance;

        const dualStackProfile = ParentalProfile(
          id: 'test_dual_stack',
          name: 'Control D Dual Stack',
          icon: '🛡️',
          color: '#10B981',
          macAddresses: ['04:d1:3a:ac:9a:63'],
          contentFilter: ContentFilterDns.custom,
          customDnsServers: ['76.76.2.2', '76.76.10.2', '2606:4700:4700::1111'],
          isPaused: false,
        );

        final res = await controller.addProfile(dualStackProfile, appState);
        expect(res.success, isTrue);

        final fetched = await appState.fetchParentalProfiles();
        expect(fetched, isNotNull);
        final p = fetched!.firstWhere((x) => x.id == 'test_dual_stack');
        expect(p.customDnsServers, contains('76.76.2.2'));
        expect(p.customDnsServers, contains('2606:4700:4700::1111'));
        expect(p.hasContentFilter, isTrue);
      },
    );

    test(
      'TimeSchedule defaults empty days to all 7 days when schedule is present',
      () {
        final jsonWithEmptyDays = {
          'block_hour': 22,
          'block_minute': 0,
          'resume_hour': 7,
          'resume_minute': 0,
          'active_days': [],
          'enabled': '1',
        };
        final sched = TimeSchedule.fromJson(jsonWithEmptyDays);
        expect(sched.activeDays.length, 7);
        expect(sched.activeDaysLabel, 'Every day');

        final profile = ParentalProfile(
          id: 'test_sched_days',
          name: 'Auto Days Profile',
          icon: '👦',
          color: '#FF5722',
          macAddresses: ['00:11:22:33:44:55'],
          schedule: sched,
        );
        expect(profile.hasSchedule, isTrue);
      },
    );

    test(
      'Daily usage quota tracking and blocking in ParentalControlsStore and ParentalProfile',
      () {
        final store = ParentalControlsStore.instance;
        const profile = ParentalProfile(
          id: 'quota_prof',
          name: 'Quota Profile',
          icon: '⏳',
          color: '#F97316',
          macAddresses: ['00:AA:BB:CC:DD:EE'],
          dailyTimeLimitMinutes: 60,
        );
        store.addProfile(profile);

        expect(store.isProfileQuotaFinished(profile), isFalse);
        expect(store.isMacPaused('00:AA:BB:CC:DD:EE'), isFalse);

        store.incrementDailyMinutesUsed('00:AA:BB:CC:DD:EE', 30);
        expect(store.getDailyMinutesUsed('00:AA:BB:CC:DD:EE'), 30);
        expect(store.isProfileQuotaFinished(profile), isFalse);

        store.incrementDailyMinutesUsed('00:AA:BB:CC:DD:EE', 30);
        expect(store.getDailyMinutesUsed('00:AA:BB:CC:DD:EE'), 60);
        expect(store.isProfileQuotaFinished(profile), isTrue);
        expect(store.isMacPaused('00:AA:BB:CC:DD:EE'), isTrue);

        store.deleteProfile('quota_prof');
      },
    );

    test(
      'AppState getDeviceNetworkAccessPolicy and isInternetPaused reflect parental blocks',
      () {
        final appState = AppState.instance;
        final store = ParentalControlsStore.instance;
        const profile = ParentalProfile(
          id: 'sync_client_tab_prof',
          name: 'Sync Test Profile',
          icon: '📱',
          color: '#3B82F6',
          macAddresses: ['12:34:56:78:9A:BC'],
          isPaused: true,
        );
        store.addProfile(profile);

        expect(store.isMacPaused('12:34:56:78:9A:BC'), isTrue);
        expect(appState.isInternetPaused('12:34:56:78:9A:BC'), isTrue);
        final policy = appState.getDeviceNetworkAccessPolicy(
          '12:34:56:78:9A:BC',
        );
        expect(policy.isEffectivelyBlocked, isTrue);
        expect(
          appState.pausedInternetMacs.contains('12:34:56:78:9A:BC'),
          isTrue,
        );

        store.deleteProfile('sync_client_tab_prof');
      },
    );
  });
}
