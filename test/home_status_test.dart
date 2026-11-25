import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';

Map<String, dynamic> _wan({bool up = true, int uptime = 3 * 86400}) => {
  'interface': 'wan',
  'up': up,
  'uptime': uptime,
  'route': [
    {'target': '0.0.0.0', 'mask': 0, 'nexthop': '10.0.0.1'},
  ],
};

const _lan = {
  'interface': 'lan',
  'up': true,
  'uptime': 999,
  'route': <dynamic>[],
};

void main() {
  test('still loading says so, never "working"', () {
    final s = HomeStatus.from(
      interfaces: null,
      devices: 0,
      loading: true,
      address: '192.168.1.1',
    );
    expect(s.headline, 'Checking your network…');
    expect(s.detail, 'Talking to the router at 192.168.1.1.');
    expect(s.unreachable, isFalse);
    expect(s.internet, LinkState.unknown);
    expect(s.internetLine, 'Checking');
  });

  test('all good names the time online and the network', () {
    final s = HomeStatus.from(
      interfaces: [_wan(), _lan],
      signalPercent: 73,
      operatorName: 'airtel',
      mode: 'LTE',
      modemConnected: true,
      devices: 7,
    );
    expect(s.headline, "Everything's working.");
    expect(s.detail, 'Online for 3 days on airtel LTE.');
    expect(s.internet, LinkState.ok);
    expect(s.internetLine, 'Signal 73%');
    expect(s.tip, isNull);
    expect(s.devices, 7);
  });

  test('a router without a modem uses the cable link alone', () {
    final s = HomeStatus.from(
      interfaces: [
        _wan(uptime: 5 * 3600),
        _lan,
      ],
      devices: 2,
    );
    expect(s.headline, "Everything's working.");
    expect(s.detail, 'Online for 5 hours.');
    expect(s.internetLine, 'Connected');
  });

  test('weak signal points at one thing to do', () {
    final s = HomeStatus.from(
      interfaces: [_wan()],
      signalPercent: 18,
      modemConnected: true,
      devices: 7,
    );
    expect(s.headline, 'The mobile signal is weak.');
    expect(s.detail, 'Things may feel slow. Your Wi-Fi and devices are fine.');
    expect(s.internet, LinkState.weak);
    expect(s.tip, 'Moving the router near a window often helps.');
    expect(s.action, HomeAction.findSpot);
  });

  test('no default route and no modem link means the internet is down', () {
    final s = HomeStatus.from(
      interfaces: [_wan(up: false), _lan],
      signalPercent: 60,
      modemConnected: false,
      devices: 3,
    );
    expect(s.headline, 'The internet is down.');
    expect(s.detail, 'Your Wi-Fi and devices still work.');
    expect(s.internet, LinkState.down);
    expect(s.internetLine, 'Not connected');
    expect(s.action, HomeAction.openModem);
  });

  test('time online in plain words', () {
    expect(onlineFor(86400), '1 day');
    expect(onlineFor(2 * 86400 + 5), '2 days');
    expect(onlineFor(3600), '1 hour');
    expect(onlineFor(12 * 60), '12 minutes');
    expect(onlineFor(30), 'less than a minute');
  });

  test('a failed first load stops saying "checking"', () {
    expect(
      homeStillLoading(fetching: false, hasDump: false, failed: true),
      isFalse,
    );
    expect(
      homeStillLoading(fetching: false, hasDump: false, failed: false),
      isTrue,
    );
    expect(
      homeStillLoading(fetching: true, hasDump: false, failed: true),
      isTrue,
    );
    final s = HomeStatus.from(interfaces: null, devices: 0, loading: false);
    expect(s.headline, "Can't reach your router.");
    expect(s.detail, "This phone isn't talking to your router right now.");
    expect(s.unreachable, isTrue);
    expect(s.internetLine, 'Unknown');
  });

  test('Home polls only when it is what the user sees', () {
    expect(
      homeShouldPoll(
        tabActive: true,
        onTop: true,
        foreground: true,
        rebooting: false,
      ),
      isTrue,
    );
    expect(
      homeShouldPoll(
        tabActive: false,
        onTop: true,
        foreground: true,
        rebooting: false,
      ),
      isFalse,
    );
    expect(
      homeShouldPoll(
        tabActive: true,
        onTop: false,
        foreground: true,
        rebooting: false,
      ),
      isFalse,
    );
    expect(
      homeShouldPoll(
        tabActive: true,
        onTop: true,
        foreground: false,
        rebooting: false,
      ),
      isFalse,
    );
    expect(
      homeShouldPoll(
        tabActive: true,
        onTop: true,
        foreground: true,
        rebooting: true,
      ),
      isFalse,
    );
  });

  test('an IPv6-only uplink counts as online', () {
    final s = HomeStatus.from(
      interfaces: [
        {
          'interface': 'wan6',
          'up': true,
          'uptime': 60,
          'route': [
            {'target': '::', 'mask': 0},
          ],
        },
      ],
      devices: 1,
    );
    expect(s.internet, LinkState.ok);
  });
}
