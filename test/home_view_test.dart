import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/home/home_flow.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/screens/home/home_status.dart';
import 'package:yet_another_luci_app/screens/home/home_view.dart';
import 'package:yet_another_luci_app/screens/stats/wan_usage.dart';

const _ok = HomeStatus(
  headline: "Everything's working.",
  detail: 'Online for 3 days on airtel LTE.',
  internet: LinkState.ok,
  internetLine: 'Signal 73%',
  devices: 7,
);

const _weak = HomeStatus(
  headline: 'The mobile signal is weak.',
  detail: 'Things may feel slow. Your Wi-Fi and devices are fine.',
  internet: LinkState.weak,
  internetLine: 'Signal 18%',
  devices: 7,
  tip: 'Moving the router near a window often helps.',
  action: HomeAction.findSpot,
);

Future<List<String>> _pump(
  WidgetTester t, {
  HomeStatus status = _ok,
  double textScale = 1,
  bool dark = false,
  HomePrefs prefs = const HomePrefs(flow: false),
  List<FlowDevice> devices = const [],
  bool settle = true,
  double down = 42.83,
  double up = 9.1,
}) async {
  final taps = <String>[];
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: dark
          ? KeystoneTheme.buildDarkTheme()
          : KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: HomeView(
          prefs: prefs,
          devices: devices,
          routerName: 'AW1000',
          model: 'Arcadyan AW1000',
          status: status,
          lights: RouterLights.unlit,
          shortcuts: [
            HomeShortcut(Icons.cell_tower, 'Modem', () => taps.add('modem')),
            HomeShortcut(Icons.phone, 'Phone', () => taps.add('phone')),
            HomeShortcut(Icons.vpn_lock, 'Passwall2', () {}),
          ],
          downMbps: down,
          upMbps: up,
          downHistory: const [10, 20, 30, 42],
          upHistory: const [2, 4, 6, 9],
          onRouterMenu: () => taps.add('menu'),
          onSettings: () => taps.add('settings'),
          onInternet: () => taps.add('internet'),
          onDevices: () => taps.add('devices'),
          onRouter: () => taps.add('router'),
          onAction: () => taps.add('action'),
          usage: const WanUsage(down: 156000000, up: 136000000, seconds: 900),
        ),
      ),
    ),
  );
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
  return taps;
}

void main() {
  testWidgets('says the state first, then the arch', (t) async {
    await _pump(t);
    expect(find.text("Everything's working."), findsOneWidget);
    expect(find.text('Online for 3 days on airtel LTE.'), findsOneWidget);
    expect(find.text('AW1000'), findsWidgets);
    expect(find.text('Internet'), findsOneWidget);
    expect(find.text('Signal 73%'), findsOneWidget);
    expect(find.text('7 devices connected ›'), findsOneWidget);
  });

  testWidgets('no problem card when all is well', (t) async {
    await _pump(t);
    expect(find.text('Find a spot'), findsNothing);
  });

  testWidgets('a problem gets one action', (t) async {
    final taps = await _pump(t, status: _weak);
    expect(
      find.text('Moving the router near a window often helps.'),
      findsOneWidget,
    );
    await t.tap(find.text('Find a spot'));
    expect(taps, ['action']);
  });

  testWidgets('shortcuts, nodes and links do their job', (t) async {
    final taps = await _pump(t);
    await t.tap(find.text('Modem'));
    await t.tap(find.text('7 devices connected ›'));
    await t.tap(find.text('Internet'));
    await t.tap(find.byTooltip('Settings'));
    expect(taps, ['modem', 'devices', 'internet', 'settings']);
    expect(find.text('Statistics'), findsNothing);
  });

  testWidgets('the internet line counts upload too, like device lines', (
    t,
  ) async {
    await _pump(t);
    final flow = t.widget<HomeFlow>(find.byType(HomeFlow));
    expect(flow.internetMbps, closeTo(42.83 + 9.1, 1e-9));
  });

  testWidgets(
    'the internet line carries device traffic before its own reading',
    (t) async {
      await _pump(
        t,
        settle: false,
        devices: const [
          FlowDevice(
            name: 'Phone',
            icon: Icons.phone_android,
            line: '',
            mbps: 2.5,
          ),
          FlowDevice(name: 'Laptop', icon: Icons.laptop, line: '', mbps: 0.1),
        ],
        down: 0,
        up: 0,
      );
      final flow = t.widget<HomeFlow>(find.byType(HomeFlow));
      expect(flow.internetMbps, closeTo(2.6, 1e-9));
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('live speed in plain numbers', (t) async {
    await _pump(t);
    expect(find.text('42.8'), findsOneWidget);
    expect(find.text('9.1'), findsOneWidget);
    expect(find.text('Mbps down'), findsOneWidget);
    expect(find.text('Mbps up'), findsOneWidget);
  });

  testWidgets('data used since the connection came up', (t) async {
    await _pump(t);
    await t.scrollUntilVisible(find.text('292 MB'), 200);
    expect(
      find.text('since the internet came up 15 minutes ago'),
      findsOneWidget,
    );
    expect(find.text('156 MB down'), findsOneWidget);
    expect(find.text('136 MB up'), findsOneWidget);
    expect(find.text('Averaged 2.6 Mbps'), findsOneWidget);
    final bar = t.getSize(find.byKey(const Key('usage-down')));
    expect(bar.height, 8);
    expect(bar.width, closeTo((350 - 32 - 2 - 2) * 156 / 292, 2));
  });

  testWidgets('shortcuts sit in even columns', (t) async {
    await _pump(t);
    final xs = [
      for (final w in ['Modem', 'Phone', 'Passwall2'])
        t.getCenter(find.text(w)).dx,
    ];
    expect(xs[1] - xs[0], closeTo(xs[2] - xs[1], 0.5));
    expect(xs[1] - xs[0], closeTo(350 / 4, 0.5));
  });

  testWidgets('settings sits at the right edge', (t) async {
    await _pump(t);
    final gear = t.getRect(find.byTooltip('Settings'));
    expect(gear.right, greaterThan(360));
  });

  testWidgets('no word breaks in half at 2x text', (t) async {
    await _pump(t, textScale: 2);
    for (final word in ['AW1000', 'Passwall2', 'Modem']) {
      final p = t.renderObject<RenderParagraph>(find.text(word).last);
      final oneLine = p.text.style!.fontSize! * 2 * 1.6;
      expect(p.size.height, lessThan(oneLine), reason: word);
    }
  });

  testWidgets('one device is not "1 devices"', (t) async {
    await _pump(
      t,
      status: const HomeStatus(
        headline: 'x',
        detail: 'y',
        internet: LinkState.ok,
        internetLine: 'Connected',
        devices: 1,
      ),
    );
    expect(find.text('1 device connected ›'), findsOneWidget);
  });

  testWidgets('shows the picked devices and how many more', (t) async {
    final taps = <String>[];
    await _pump(
      t,
      devices: [
        FlowDevice(
          name: 'Living room TV',
          icon: Icons.tv,
          line: '14.1 Mbps',
          mbps: 14.1,
          onTap: () => taps.add('tv'),
        ),
        const FlowDevice(
          name: 'Work laptop',
          icon: Icons.laptop,
          line: 'Wired',
          mbps: 0,
        ),
      ],
    );
    expect(find.text('14.1 Mbps'), findsOneWidget);
    expect(find.text('5 more devices ›'), findsOneWidget);
    await t.tap(find.text('Living room TV'));
    expect(taps, ['tv']);
  });

  testWidgets('five devices fit side by side', (t) async {
    await _pump(
      t,
      prefs: const HomePrefs(flow: false, deviceCount: 5),
      devices: [
        for (var i = 0; i < 5; i++)
          FlowDevice(
            name: 'Kitchen speaker $i',
            icon: Icons.speaker,
            line: 'Wi-Fi · good',
            mbps: 0,
          ),
      ],
    );
    expect(find.text('Kitchen speaker 4'), findsOneWidget);
    expect(find.text('2 more devices ›'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('sections the user turned off stay hidden', (t) async {
    await _pump(
      t,
      prefs: const HomePrefs(flow: false, shortcuts: false, chart: false),
    );
    expect(find.text('Modem'), findsNothing);
    expect(find.text('— Download'), findsNothing);
    expect(find.text('Right now'), findsOneWidget);
  });

  testWidgets('speeds in MB/s when chosen', (t) async {
    await _pump(t, prefs: const HomePrefs(flow: false, unit: SpeedUnit.mbs));
    expect(find.text('MB/s down'), findsOneWidget);
    expect(find.text('5.4'), findsOneWidget);
    await t.scrollUntilVisible(find.text('292 MB'), 200);
    expect(find.text('Averaged 0.32 MB/s'), findsOneWidget);
  });

  testWidgets('top-to-bottom layout puts the internet in a pill', (t) async {
    await _pump(
      t,
      prefs: const HomePrefs(flow: false, layout: HomeLayout.topDown),
    );
    expect(find.text('Internet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('moving dots keep running without errors', (t) async {
    await _pump(t, prefs: const HomePrefs(), settle: false);
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final dark in [false, true]) {
    testWidgets('fits at 2x text (dark: $dark)', (t) async {
      await _pump(t, status: _weak, textScale: 2, dark: dark);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets("can't reach: two checks, Try again, Wi-Fi settings", (t) async {
    final taps = <String>[];
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildDarkTheme(),
        home: Scaffold(
          body: HomeView(
            routerName: 'AW1000',
            address: '192.168.1.1',
            status: HomeStatus.from(interfaces: null, devices: 0),
            lights: RouterLights.unlit,
            shortcuts: [HomeShortcut(Icons.phone, 'Phone', () {})],
            downMbps: 0,
            upMbps: 0,
            downHistory: const [],
            upHistory: const [],
            onRefresh: () async => taps.add('again'),
            onOpenWifiSettings: () => taps.add('wifi'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text("Can't reach your router."), findsOneWidget);
    expect(find.text("Is this phone on the router's Wi-Fi?"), findsOneWidget);
    expect(find.text("Mobile data can't reach 192.168.1.1"), findsOneWidget);
    expect(find.text('Is the router on?'), findsOneWidget);
    expect(find.text('Phone'), findsNothing);
    expect(find.text('Right now'), findsNothing);
    await t.tap(find.text('Try again'));
    await t.tap(find.text('Open Wi-Fi settings'));
    expect(taps, ['again', 'wifi']);
  });
}
