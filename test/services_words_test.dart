// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/services_system/models/services_system_info.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/services_system_screen.dart';

void main() {
  test('common schedules read as words', () {
    expect(cronWords('*/5 * * * *'), 'Every 5 minutes');
    expect(cronWords('0 * * * *'), 'Every hour');
    expect(cronWords('30 * * * *'), 'Every hour at :30');
    expect(cronWords('0 4 * * *'), 'Every day at 04:00');
    expect(cronWords('15 22 * * 1-5'), 'Weekdays at 22:15');
    expect(cronWords('0 0 * * 0'), 'Every Sunday at 00:00');
    expect(cronWords('0 3 1 * *'), 'First of the month at 03:00');
  });

  test('anything unusual stays as written', () {
    expect(cronWords('0 4 1 6 *'), '0 4 1 6 *');
    expect(cronWords('nonsense'), 'nonsense');
  });

  test('a service line says if it runs and starts by itself', () {
    expect(
      serviceLine(
        const InitScript(
          name: 'dnsmasq',
          isEnabled: true,
          isRunning: true,
          startPriority: 19,
        ),
      ),
      'Running · starts with the router',
    );
    expect(
      serviceLine(
        const InitScript(
          name: 'x',
          isEnabled: false,
          isRunning: false,
          startPriority: 99,
        ),
      ),
      "Stopped · doesn't start by itself",
    );
  });

  test('a cron line keeps its on/off mark', () {
    final j = CronJob.fromCronLine('# 0 4 * * * wifi reload');
    expect(j.isCommented, isTrue);
    expect(j.copyWith(isCommented: false).rawLine, '0 4 * * * wifi reload');
  });
}
