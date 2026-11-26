// SPDX-License-Identifier: GPL-3.0-or-later

enum RestartTarget { router, modem }

const restartGuard = '/usr/share/keystone-history/common.sh';
const _tag = '# keystone-restart';

String restartCronLine({
  required RestartTarget target,
  required int hour,
  required int minute,
  required bool guarded,
}) {
  if (hour < 0 || hour > 23) throw ArgumentError.value(hour, 'hour');
  if (minute < 0 || minute > 59) throw ArgumentError.value(minute, 'minute');
  final when = '$minute $hour * * *';
  if (guarded) {
    return '$when . $restartGuard && ks_restart_guarded ${target.name} $_tag';
  }
  if (target == RestartTarget.modem) {
    throw ArgumentError('A modem restart needs keystone-history on the router');
  }
  return '$when sleep 70 && touch /etc/banner && reboot $_tag';
}

bool isRestartPreset(String cronLine) => cronLine.trimRight().endsWith(_tag);

({RestartTarget target, int hour, int minute})? readRestartPreset(String line) {
  if (!isRestartPreset(line)) return null;
  final m = RegExp(r'^#?\s*(\d+) (\d+) \* \* \* ').firstMatch(line.trim());
  if (m == null) return null;
  return (
    target: line.contains('guarded modem')
        ? RestartTarget.modem
        : RestartTarget.router,
    hour: int.parse(m[2]!),
    minute: int.parse(m[1]!),
  );
}
