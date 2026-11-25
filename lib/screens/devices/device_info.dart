import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

String? signalWord(int? dbm) {
  if (dbm == null) return null;
  if (dbm >= -60) return 'strong';
  if (dbm >= -70) return 'good';
  return 'weak signal';
}

bool isWeak(Client c) =>
    c.connectionType == ConnectionType.wireless &&
    signalWord(c.signalDbm) == 'weak signal';

double deviceMbps(Client c) => ((c.rxSpeed ?? 0) + (c.txSpeed ?? 0)) * 8 / 1e6;

String deviceLine(Client c) {
  if (c.connectionType == ConnectionType.wired) return 'Wired';
  final s = signalWord(c.signalDbm);
  return s == null ? 'Wi-Fi' : 'Wi-Fi · $s';
}

class DeviceGroups {
  const DeviceGroups(this.using, this.quiet, this.paused);

  final List<Client> using;

  final List<Client> quiet;
  final List<Client> paused;

  factory DeviceGroups.from(List<Client> online, Set<String> pausedMacs) {
    final paused = {
      for (final m in pausedMacs) ClientNamingHelper.normalizeMac(m),
    };
    bool isPaused(Client c) =>
        paused.contains(ClientNamingHelper.normalizeMac(c.macAddress));
    final active = online.where((c) => !isPaused(c));
    final using = active.where((c) => deviceMbps(c) >= 0.1).toList()
      ..sort((a, b) => deviceMbps(b).compareTo(deviceMbps(a)));
    final quiet = active.where((c) => deviceMbps(c) < 0.1).toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    return DeviceGroups(using, quiet, online.where(isPaused).toList());
  }
}
