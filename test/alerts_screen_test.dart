import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/background/alerts_store.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_models.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_settings_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';

Map<String, dynamic> row(
  int id, {
  String type = 'device',
  int start = 1800000000,
  int? end,
  bool approx = false,
  Map<String, dynamic> detail = const {'name': 'Pixel'},
}) => {
  'id': id,
  'type': type,
  'start': start,
  'end': end,
  'approx': approx,
  'detail': detail,
};

class Router {
  Router(this.events, {this.installed = true});
  List<Map<String, dynamic>> events;
  bool installed;
  bool down = false;
  bool trimmed = false;
  String key = 'a' * 32;
  Map<String, dynamic>? saved;
  final calls = <String>[];

  Future<Map<String, dynamic>> call(String m, Map<String, dynamic> p) async {
    calls.add(m);
    if (down) throw const NoobRpcError('Timed out');
    if (!installed) throw const NoobRpcError('Method not found');
    switch (m) {
      case 'info':
        return {
          'version': '0.1.0',
          'newest': events.isEmpty ? 0 : events.last['id'],
          'oldest': 1,
          'key_id': keyId(key),
          'settings': saved ?? const {},
        };
      case 'events':
        final since = p['since'] as int;
        return {
          'events': events.where((e) => e['id'] > since).toList(),
          'trimmed': trimmed,
          'newest': events.isEmpty ? 0 : events.last['id'],
        };
      case 'pair':
        return {'key': key};
      case 'reset_key':
        key = 'b' * 32;
        return {};
      case 'set':
        saved = p;
        return {};
    }
    return {};
  }
}

void main() {
  late AlertsStore store;
  late Map<String, String> keys;
  late List<Duration?> intervals;
  late bool allowed;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AlertsStore(await SharedPreferences.getInstance());
    keys = {};
    intervals = [];
    allowed = true;
  });

  AlertsPhone phone() => AlertsPhone(
    store: store,
    routerId: 'r1',
    readKey: () async => keys['r1'],
    writeKey: (k) async => keys['r1'] = k,
    interval: () async => intervals.isEmpty ? null : intervals.last,
    setInterval: (d) async => intervals.add(d),
    notificationsAllowed: () async => allowed,
    askForNotifications: () async => allowed,
    openNotificationSettings: () async {},
  );

  Future<void> open(WidgetTester t, Router r, {bool dark = false}) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [dark ? KeystoneColors.dark : KeystoneColors.light],
        ),
        home: AlertsScreen(
          client: AlertsClient(r.call),
          phone: phone(),
          install: () async => r.installed = true,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('offers to install when missing', (t) async {
    final r = Router([], installed: false);
    await open(t, r);
    expect(find.text('Get alerts from your router'), findsOneWidget);
    await t.tap(find.text('Install'));
    await t.pumpAndSettle();
    expect(find.text('Get alerts from your router'), findsNothing);
  });

  testWidgets('newest first, with outage words', (t) async {
    await open(
      t,
      Router([
        row(1),
        row(2, type: 'internet', end: 1800000720, detail: {'drops': 6}),
        row(3, type: 'internet', detail: {'drops': 1}),
      ]),
    );
    final texts = t
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .toList();
    final now = texts.indexWhere((s) => s.startsWith('Internet is down'));
    final was = texts.indexWhere((s) => s.startsWith('Internet was down'));
    final dev = texts.indexWhere((s) => s.startsWith('New device'));
    expect([now, was, dev].every((i) => i >= 0), isTrue);
    expect(now < was && was < dev, isTrue);
    expect(find.textContaining('dropped 6 times'), findsOneWidget);
  });

  testWidgets('approximate times say so', (t) async {
    await open(t, Router([row(1, approx: true)]));
    expect(find.textContaining('about '), findsOneWidget);
  });

  testWidgets('outages filter', (t) async {
    await open(t, Router([row(1), row(2, type: 'internet', end: 1800000100)]));
    await t.tap(find.text('Outages'));
    await t.pumpAndSettle();
    expect(find.textContaining('New device'), findsNothing);
    expect(find.textContaining('Internet was down'), findsOneWidget);
  });

  testWidgets('removed events are mentioned', (t) async {
    await open(t, Router([row(9)])..trimmed = true);
    expect(
      find.text(
        'Older events were removed before this phone could collect them',
      ),
      findsOneWidget,
    );
  });

  testWidgets('seeing the list counts as seen', (t) async {
    await open(t, Router([row(1), row(2)]));
    expect(store.lastId('r1'), 2);
    expect(store.events('r1'), hasLength(2));
  });

  testWidgets('the router is the record: gone events leave the list', (
    t,
  ) async {
    await store.saveEvents('r1', [AlertEvent.from(row(1, type: 'internet'))!]);
    await open(t, Router([row(1006)]));
    expect(find.textContaining('Internet is down'), findsNothing);
    expect(store.events('r1').map((e) => e.id), [1006]);
  });

  testWidgets('router out of reach shows what this phone has', (t) async {
    await store.saveEvents('r1', [AlertEvent.from(row(4))!]);
    await open(t, Router([])..down = true);
    expect(find.textContaining('New device'), findsOneWidget);
    expect(find.textContaining("Can't reach the router"), findsOneWidget);
  });

  testWidgets('empty', (t) async {
    await open(t, Router([]));
    expect(find.text('Nothing has happened yet'), findsOneWidget);
  });

  testWidgets('dark mode renders', (t) async {
    await open(t, Router([row(1)]), dark: true);
    expect(t.takeException(), isNull);
  });

  group('settings', () {
    Future<void> settings(WidgetTester t, Router r) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [KeystoneColors.light]),
          home: AlertSettingsScreen(
            client: AlertsClient(r.call),
            phone: phone(),
            settings: const AlertSettings(),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> reveal(WidgetTester t, Finder f) =>
        t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

    Future<void> save(WidgetTester t) async {
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
    }

    testWidgets('turning a kind off', (t) async {
      final r = Router([]);
      await settings(t, r);
      await t.tap(
        find.descendant(
          of: find.byKey(const ValueKey('mode-internet')),
          matching: find.text('Off'),
        ),
      );
      await t.pumpAndSettle();
      await save(t);
      expect(r.saved!['internet'], {'mode': 'off'});
    });

    testWidgets('signal level must be sensible', (t) async {
      final r = Router([]);
      await settings(t, r);
      await reveal(t, find.byKey(const ValueKey('rsrp')));
      await t.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('rsrp')),
          matching: find.byType(TextFormField),
        ),
        '-200',
      );
      await save(t);
      expect(find.text('-140 to -60'), findsOneWidget);
      expect(r.saved, isNull);
    });

    testWidgets('notifications on this phone pair and schedule', (t) async {
      final r = Router([]);
      await settings(t, r);
      await t.tap(find.text('Notify this phone'));
      await t.pumpAndSettle();
      expect(keys['r1'], r.key);
      expect(intervals.last, const Duration(minutes: 15));
      expect(store.muted, isFalse);
    });

    testWidgets('notifications refused', (t) async {
      allowed = false;
      await settings(t, Router([]));
      await t.tap(find.text('Notify this phone'));
      await t.pumpAndSettle();
      expect(find.text('Notifications are off for Keystone'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });

    testWidgets('checking interval', (t) async {
      await settings(t, Router([]));
      expect(find.text('Off'), findsWidgets);
      for (final s in ['15 min', '30 min', '1 hour']) {
        expect(find.text(s), findsOneWidget);
      }
      await t.tap(find.text('30 min'));
      await t.pumpAndSettle();
      expect(intervals.last, const Duration(minutes: 30));
    });

    testWidgets('resetting the key keeps this phone working', (t) async {
      final r = Router([]);
      keys['r1'] = r.key;
      await settings(t, r);
      await reveal(t, find.text('Reset alerts key'));
      await t.ensureVisible(find.text('Reset alerts key'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reset alerts key'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reset'));
      await t.pumpAndSettle();
      expect(keys['r1'], 'b' * 32);
    });
  });
}
