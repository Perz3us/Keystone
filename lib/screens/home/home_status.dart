enum LinkState { ok, weak, down, unknown }

enum HomeAction { findSpot, openModem }

class HomeStatus {
  const HomeStatus({
    required this.headline,
    required this.detail,
    required this.internet,
    required this.internetLine,
    required this.devices,
    this.tip,
    this.action,
    this.unreachable = false,
  });

  final String headline;
  final String detail;
  final LinkState internet;
  final String internetLine;
  final int devices;
  final String? tip;
  final HomeAction? action;

  final bool unreachable;

  factory HomeStatus.from({
    required List<dynamic>? interfaces,
    int? signalPercent,
    String? operatorName,
    String? mode,
    bool? modemConnected,
    required int devices,
    bool loading = false,
    String? address,
  }) {
    if (interfaces == null && loading) {
      return HomeStatus(
        headline: 'Checking your network…',
        detail: address == null
            ? 'Talking to your router.'
            : 'Talking to the router at $address.',
        internet: LinkState.unknown,
        internetLine: 'Checking',
        devices: devices,
      );
    }
    if (interfaces == null) {
      return HomeStatus(
        headline: "Can't reach your router.",
        detail: "This phone isn't talking to your router right now.",
        internet: LinkState.unknown,
        internetLine: 'Unknown',
        devices: devices,
        unreachable: true,
      );
    }

    final wan = interfaces.whereType<Map>().where(_isDefaultRoute).firstOrNull;
    final online = wan != null || modemConnected == true;
    final signal = signalPercent == null ? null : 'Signal $signalPercent%';

    if (!online) {
      return HomeStatus(
        headline: 'The internet is down.',
        detail: 'Your Wi-Fi and devices still work.',
        internet: LinkState.down,
        internetLine: 'Not connected',
        devices: devices,
        action: signalPercent != null ? HomeAction.openModem : null,
      );
    }
    if (signalPercent != null && signalPercent < 25) {
      return HomeStatus(
        headline: 'The mobile signal is weak.',
        detail: 'Things may feel slow. Your Wi-Fi and devices are fine.',
        internet: LinkState.weak,
        internetLine: signal!,
        devices: devices,
        tip: 'Moving the router near a window often helps.',
        action: HomeAction.findSpot,
      );
    }

    final uptime = (wan?['uptime'] as num?)?.toInt() ?? 0;
    final network = [
      operatorName,
      mode,
    ].whereType<String>().where((w) => w.isNotEmpty).join(' ');
    final since = uptime > 0 ? 'Online for ${onlineFor(uptime)}' : 'Online';
    return HomeStatus(
      headline: "Everything's working.",
      detail: network.isEmpty ? '$since.' : '$since on $network.',
      internet: LinkState.ok,
      internetLine: signal ?? 'Connected',
      devices: devices,
    );
  }

  static bool _isDefaultRoute(Map i) {
    if (i['up'] != true) return false;
    final routes = i['route'];
    return routes is List &&
        routes.whereType<Map>().any(
          (r) =>
              (r['target'] == '0.0.0.0' || r['target'] == '::') &&
              '${r['mask']}' == '0',
        );
  }
}

String onlineFor(int seconds) {
  String n(int v, String unit) => '$v $unit${v == 1 ? '' : 's'}';
  final d = Duration(seconds: seconds);
  if (d.inDays > 0) return n(d.inDays, 'day');
  if (d.inHours > 0) return n(d.inHours, 'hour');
  if (d.inMinutes > 0) return n(d.inMinutes, 'minute');
  return 'less than a minute';
}

bool homeStillLoading({
  required bool fetching,
  required bool hasDump,
  required bool failed,
}) => fetching || (!hasDump && !failed);

bool homeShouldPoll({
  required bool tabActive,
  required bool onTop,
  required bool foreground,
  required bool rebooting,
}) => tabActive && onTop && foreground && !rebooting;
