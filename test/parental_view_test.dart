// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/parental_controls/screens/parental_controls_screen.dart';
import 'package:yet_another_luci_app/modules/parental_controls/screens/parental_words.dart';

ParentalProfile person({
  bool paused = false,
  bool enabled = true,
  DateTime? until,
  TimeSchedule? schedule,
  int? limit,
  List<String> macs = const ['AA:AA:AA:AA:AA:AA'],
}) => ParentalProfile(
  id: 'p1',
  name: 'Sam',
  icon: '',
  color: '#000000',
  macAddresses: macs,
  isPaused: paused,
  isEnabled: enabled,
  pauseExpiresAt: until,
  schedule: schedule,
  dailyTimeLimitMinutes: limit,
);

void main() {
  group('words', () {
    test('limits and times', () {
      expect(limitWords(45), '45 min');
      expect(limitWords(60), '1 h');
      expect(limitWords(90), '1 h 30 min');
      expect(hhmm(7, 5), '07:05');
    });

    test('bedtime days read naturally', () {
      TimeSchedule s(Set<ScheduleDay> d) => TimeSchedule(
        activeDays: d,
        blockHour: 21,
        blockMinute: 0,
        resumeHour: 7,
        resumeMinute: 0,
      );
      expect(
        bedtimeWords(s(ScheduleDay.values.toSet())),
        '21:00 to 07:00, every day',
      );
      expect(
        bedtimeWords(s({ScheduleDay.saturday, ScheduleDay.sunday})),
        '21:00 to 07:00, weekends',
      );
      expect(
        bedtimeWords(
          s({
            ScheduleDay.sunday,
            ScheduleDay.monday,
            ScheduleDay.tuesday,
            ScheduleDay.wednesday,
            ScheduleDay.thursday,
          }),
        ),
        '21:00 to 07:00, school nights',
      );
    });

    test('status says what is happening first', () {
      expect(personStatus(person(enabled: false)), 'Rules off, free access');
      expect(personStatus(person(paused: true)), 'Paused');
      final until = DateTime.now().add(const Duration(hours: 1));
      expect(
        personStatus(person(paused: true, until: until.toUtc())),
        'Paused until ${hhmm(until.hour, until.minute)}',
      );
      expect(
        personStatus(person(limit: 60), used: 60),
        'Out of time for today',
      );
      expect(
        personStatus(person(limit: 90), used: 30),
        '1 device · 1 h left today',
      );
      expect(personStatus(person(macs: const [])), 'No devices yet');
    });

    test('only a pause counts as paused now', () {
      expect(isPausedNow(person(paused: true)), isTrue);
      expect(isPausedNow(person(paused: true, enabled: false)), isFalse);
      expect(isPausedNow(person()), isFalse);
    });
  });

  testWidgets('nobody yet offers to add a person', (tester) async {
    var added = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParentalListView(
            people: const [],
            statusOf: (_) => '',
            onOpen: (_) {},
            onPause: (_) {},
            onResume: (_) {},
            onAdd: () => added++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Add a person'));
    expect(added, 1);
  });

  testWidgets('each person has one tap to pause or resume', (tester) async {
    final paused = <String>[];
    final resumed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ParentalListView(
              people: [person(), person(paused: true)],
              statusOf: (p) => personStatus(p),
              onOpen: (_) {},
              onPause: (p) => paused.add(p.name),
              onResume: (p) => resumed.add(p.name),
              onAdd: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pause'));
    await tester.tap(find.text('Resume'));
    expect(paused, ['Sam']);
    expect(resumed, ['Sam']);
  });
}
