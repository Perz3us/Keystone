// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/phone/call_log.dart';

void main() {
  test('parses answered, missed, blocked and outgoing calls', () {
    const log = '''
100 incoming 0771234567
105 answered 0771234567
165 hangup 0771234567
200 incoming 0779999999
220 missed 0779999999
300 blocked 0110000000
400 dial 0112223344
410 connected 0112223344
470 ended
''';
    final calls = parseCallLog(log);
    expect(calls.length, 4);

    final out = calls[0];
    expect(out.dir, CallDir.outgoing);
    expect(out.status, 'answered');
    expect(out.talked, const Duration(seconds: 60));

    expect(calls[1].status, 'blocked');
    expect(calls[2].status, 'missed');
    expect(calls[3].status, 'answered');
    expect(calls[3].talked, const Duration(seconds: 60));
  });

  test('an unfinished call is active when live', () {
    final calls = parseCallLog('10 incoming 077\n12 answered 077', live: true);
    expect(calls.single.status, 'active');
    expect(parseCallLog('10 dial 077').single.status, 'cancelled');
  });
}
