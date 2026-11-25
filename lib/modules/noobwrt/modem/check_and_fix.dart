// SPDX-License-Identifier: GPL-3.0-or-later

import 'modem_controls.dart';

class FixStep {
  const FixStep(this.text, [this.ok]);
  final String text;
  final bool? ok;
}

Future<bool> _safe(Future<bool> Function() f) async {
  try {
    return await f();
  } catch (_) {
    return false;
  }
}

Stream<FixStep> checkAndFix(
  ModemControls c,
  Future<bool> Function() online, {
  Future<bool> Function(Duration)? waitOnline,
  DateTime Function() now = DateTime.now,
  Future<void> Function(Duration) sleep = Future<void>.delayed,
}) async* {
  final wait =
      waitOnline ??
      (Duration d) async {
        final start = now();
        var dropped = false;
        while (now().difference(start) < d) {
          await sleep(const Duration(seconds: 5));
          if (!await _safe(online)) {
            dropped = true;
          } else if (dropped ||
              now().difference(start) >= const Duration(seconds: 20)) {
            return true;
          }
        }
        return false;
      };

  yield const FixStep('Checking the connection');
  if (await _safe(online)) {
    yield const FixStep('Checking the connection', true);
    yield const FixStep('The connection is fine', true);
    return;
  }
  yield const FixStep('Checking the connection', false);

  final steps =
      <(String, Future<bool> Function(), Future<void> Function(), int)>[
        ('Reconnecting', c.canReconnect, c.reconnect, 35),
        ('Restarting the modem', c.canRestart, c.restart, 80),
        (
          'Power-cycling the modem over USB',
          c.canPowerCycle,
          c.powerCycle,
          120,
        ),
      ];
  for (final (text, can, run, secs) in steps) {
    if (!await _safe(can)) continue;
    yield FixStep(text);
    try {
      await run();
    } catch (_) {
      yield FixStep(text, false);
      continue;
    }
    if (await _safe(() => wait(Duration(seconds: secs)))) {
      yield FixStep(text, true);
      yield const FixStep('The internet is back', true);
      return;
    }
    yield FixStep(text, false);
  }
  yield const FixStep(
    'Automatic fixes did not help. Check the SIM, the antennas and your balance.',
    false,
  );
}
