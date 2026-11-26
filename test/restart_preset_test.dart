import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/services_system/restart_preset.dart';

void main() {
  test('guarded router restart', () {
    expect(
      restartCronLine(
        target: RestartTarget.router,
        hour: 4,
        minute: 0,
        guarded: true,
      ),
      '0 4 * * * . /usr/share/keystone-history/common.sh && ks_restart_guarded router # keystone-restart',
    );
  });
  test('guarded modem restart', () {
    expect(
      restartCronLine(
        target: RestartTarget.modem,
        hour: 3,
        minute: 30,
        guarded: true,
      ),
      '30 3 * * * . /usr/share/keystone-history/common.sh && ks_restart_guarded modem # keystone-restart',
    );
  });
  test('plain router restart waits out a clock jump', () {
    expect(
      restartCronLine(
        target: RestartTarget.router,
        hour: 4,
        minute: 0,
        guarded: false,
      ),
      '0 4 * * * sleep 70 && touch /etc/banner && reboot # keystone-restart',
    );
  });
  test('a modem restart needs the guard script', () {
    expect(
      () => restartCronLine(
        target: RestartTarget.modem,
        hour: 4,
        minute: 0,
        guarded: false,
      ),
      throwsArgumentError,
    );
  });
  test('times out of range', () {
    for (final (h, m) in [(24, 0), (-1, 0), (4, 60), (4, -1)]) {
      expect(
        () => restartCronLine(
          target: RestartTarget.router,
          hour: h,
          minute: m,
          guarded: true,
        ),
        throwsArgumentError,
      );
    }
  });
  test('recognises its own lines and nothing else', () {
    for (final g in [true, false]) {
      final line = restartCronLine(
        target: RestartTarget.router,
        hour: 4,
        minute: 0,
        guarded: g,
      );
      expect(isRestartPreset(line), isTrue);
      expect(isRestartPreset('# $line'), isTrue);
    }
    expect(isRestartPreset('0 4 * * * reboot'), isFalse);
    expect(isRestartPreset('0 4 * * * echo keystone-restart'), isFalse);
  });
  test('reads back what was saved', () {
    final p = readRestartPreset(
      restartCronLine(
        target: RestartTarget.modem,
        hour: 2,
        minute: 15,
        guarded: true,
      ),
    )!;
    expect((p.target, p.hour, p.minute), (RestartTarget.modem, 2, 15));
    expect(readRestartPreset('0 4 * * * reboot'), isNull);
  });
}
