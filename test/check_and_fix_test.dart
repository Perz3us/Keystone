// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/check_and_fix.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_controls.dart';

class _Fake implements ModemControls {
  _Fake({this.power = true, this.throwReconnect = false});
  final bool power;
  final bool throwReconnect;
  final calls = <String>[];

  @override
  Future<bool> canReconnect() async => true;
  @override
  Future<void> reconnect() async {
    calls.add('reconnect');
    if (throwReconnect) throw Exception('x');
  }

  @override
  Future<bool> canRestart() async => true;
  @override
  Future<void> restart() async => calls.add('restart');
  @override
  Future<bool> canPowerCycle() async => power;
  @override
  Future<void> powerCycle() async => calls.add('powerCycle');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

List<(String, bool?)> _seq(List<FixStep> s) => [
  for (final e in s) (e.text, e.ok),
];

void main() {
  test('already online does nothing', () async {
    final c = _Fake();
    final s = await checkAndFix(c, () async => true).toList();
    expect(s.first.text, 'Checking the connection');
    expect(_seq(s), [
      ('Checking the connection', null),
      ('Checking the connection', true),
      ('The connection is fine', true),
    ]);
    expect(s.last.text, 'The connection is fine');
    expect(s.last.ok, true);
    expect(c.calls, isEmpty);
  });

  test('reconnect brings it back', () async {
    final c = _Fake();
    var on = false;
    final s = await checkAndFix(
      c,
      () async => on,
      waitOnline: (_) async => on = true,
    ).toList();
    expect(c.calls, ['reconnect']);
    expect(_seq(s), contains(('Reconnecting', true)));
    expect(s.where((e) => e.text == 'Restarting the modem'), isEmpty);
    expect(s.last.text, 'The internet is back');
    expect(s.last.ok, true);
  });

  test('nothing helps', () async {
    final c = _Fake();
    final s = await checkAndFix(
      c,
      () async => false,
      waitOnline: (_) async => false,
    ).toList();
    expect(c.calls, ['reconnect', 'restart', 'powerCycle']);
    expect(_seq(s).where((e) => e.$2 == false).toList(), [
      ('Checking the connection', false),
      ('Reconnecting', false),
      ('Restarting the modem', false),
      ('Power-cycling the modem over USB', false),
      (s.last.text, false),
    ]);
    expect(
      s.last.text,
      'Automatic fixes did not help. Check the SIM, the antennas and your balance.',
    );
    expect(s.last.ok, false);
  });

  test('throwing action marks step failed and moves on', () async {
    final c = _Fake(power: false, throwReconnect: true);
    final s = await checkAndFix(
      c,
      () async => false,
      waitOnline: (_) async => throw Exception('unreachable'),
    ).toList();
    expect(c.calls, ['reconnect', 'restart']);
    expect(_seq(s), [
      ('Checking the connection', null),
      ('Checking the connection', false),
      ('Reconnecting', null),
      ('Reconnecting', false),
      ('Restarting the modem', null),
      ('Restarting the modem', false),
      (s.last.text, false),
    ]);
  });

  test('stale online right after the action waits 20 s', () async {
    final c = _Fake();
    var t = DateTime(2026);
    final polls = <int>[];
    var first = true;
    final start = t;
    final s = await checkAndFix(
      c,
      () async {
        if (first) return first = false;
        polls.add(t.difference(start).inSeconds);
        return true;
      },
      now: () => t,
      sleep: (d) async => t = t.add(d),
    ).toList();
    expect(c.calls, ['reconnect']);
    expect(polls, [5, 10, 15, 20]);
    expect(s.last.text, 'The internet is back');
  });

  test('online after a drop counts at once', () async {
    final c = _Fake();
    var t = DateTime(2026);
    final start = t;
    final answers = [false, false, true];
    final polls = <int>[];
    final s = await checkAndFix(
      c,
      () async {
        polls.add(t.difference(start).inSeconds);
        return answers.removeAt(0);
      },
      now: () => t,
      sleep: (d) async => t = t.add(d),
    ).toList();
    expect(c.calls, ['reconnect']);
    expect(polls, [0, 5, 10]);
    expect(s.last.text, 'The internet is back');
  });
}
