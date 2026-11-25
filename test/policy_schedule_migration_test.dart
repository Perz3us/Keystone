// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/services/client_policy_schedule_service.dart';

void main() {
  test('schedules saved by older builds are moved to the new key', () async {
    const mac = 'AA:BB:CC:DD:EE:FF';
    final expiry = DateTime.now().add(const Duration(hours: 2));
    final record = StoredPolicySchedule(
      targetMac: mac,
      scheduleExpiry: expiry,
      createdAt: DateTime.now(),
      policy: NetworkAccessPolicy.blocked(mac),
    );
    SharedPreferences.setMockInitialValues({
      'yala_policy_schedule_$mac': jsonEncode(record.toJson()),
    });
    final prefs = await SharedPreferences.getInstance();

    await ClientPolicyScheduleService.instance.init(prefs);

    expect(ClientPolicyScheduleService.instance.getExpiry(mac), isNotNull);
    expect(prefs.containsKey('yala_policy_schedule_$mac'), isFalse);
    expect(
      prefs.containsKey('${ClientPolicyScheduleService.keyPrefix}$mac'),
      isTrue,
    );
  });
}
