import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/background/alerts_feed.dart';
import 'package:yet_another_luci_app/background/alerts_store.dart';
import 'package:yet_another_luci_app/background/background_check.dart';
import 'package:yet_another_luci_app/background/widget_data.dart';
import 'package:yet_another_luci_app/background/widget_lines.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_models.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_notify_plan.dart';

const key = '00112233445566778899aabbccddeeff';

String sha(String s) => sha256.convert(utf8.encode(s)).toString();

Router router(String id) => Router(
  id: id,
  ipAddress: '192.168.1.1',
  username: 'root',
  password: 'secret',
  useHttps: false,
  name: id,
);

Map<String, dynamic> row(int id, {String type = 'device', int? end}) => {
  'id': id,
  'type': type,
  'start': 1800000000 + id,
  'end': end,
  'approx': false,
  'detail': {'mac': 'aa'},
};

class FakeRouter {
  FakeRouter(this.events, {this.newest, this.routerKey = key});
  List<Map<String, dynamic>> events;
  int? newest;
  String routerKey;
  bool online = true;
  bool tamper = false;
  Map<String, dynamic> extra = const {};
  final asked = <Map<String, dynamic>>[];

  Future<Map<String, dynamic>?> post(Map<String, dynamic> p) async {
    asked.add(p);
    final since = p['since'] as int, nonce = p['nonce'] as String;
    if (p['proof'] != sha('$routerKey:q:$nonce:$since:$routerKey')) return {};
    final body = jsonEncode({
      'events': events.where((e) => e['id'] > since).take(100).toList(),
      'trimmed': false,
      'newest': newest ?? (events.isEmpty ? 0 : events.last['id']),
      'settings': {
        'internet': {'mode': 'buzz'},
        'device': {'mode': 'buzz'},
        'signal': {'mode': 'log', 'rsrp_below': -110},
      },
      'online': online,
      'rsrp': -97,
      'plan': {
        'sim': 'main',
        'plan': 'unlimited',
        'allowance_gb': 0,
        'billing_day': 1,
        'period_start': '2026-11-01',
        'period_end': '2026-11-30',
        'down': 18000000000,
        'up': 0,
      },
      ...extra,
    });
    final sig = sha('$routerKey:a:$nonce:$body:$routerKey');
    return {
      'body': tamper ? body.replaceFirst('true', 'false') : body,
      'sig': sig,
    };
  }
}

void main() {
  late AlertsStore store;
  late List<(NotifyPlan, String)> notified;
  late List<WidgetSnapshot> widgets;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = AlertsStore(await SharedPreferences.getInstance());
    notified = [];
    widgets = [];
  });

  Future<CheckResult> check(
    Map<String, FakeRouter> routers, {
    bool wifi = true,
    bool muted = false,
    Map<String, String> keys = const {'a': key, 'b': key},
    Future<void> Function(NotifyPlan, String)? notify,
  }) => runBackgroundCheck(
    CheckDeps(
      onWifi: () async => wifi,
      routers: () async => [router('a'), router('b')],
      readKey: (id) async => keys[id],
      post: (r) async =>
          (p) async =>
              routers[r.id]?.post(p) ?? (throw Exception('unreachable')),
      store: store,
      phoneMuted: () async => muted,
      notify: notify ?? (p, name) async => notified.add((p, name)),
      saveWidget: (w) async => widgets.add(w),
      now: () => DateTime(2026, 11, 20, 14, 20),
    ),
  );

  group('the feed', () {
    Future<FeedReply?> read(FakeRouter r, {String k = key}) =>
        readFeed(r.post, k, 0);

    test('reads a signed answer', () async {
      final f = (await read(FakeRouter([row(1)])))!;
      expect(f.events, hasLength(1));
      expect(f.online, isTrue);
      expect(f.rsrp, -97);
      expect(f.plan!.used, 18000000000);
    });
    test('never sends the key or the password', () async {
      final r = FakeRouter([]);
      await read(r);
      final sent = jsonEncode(r.asked);
      expect(sent, isNot(contains(key)));
      expect(sent, isNot(contains('secret')));
    });
    test('asks differently each time', () async {
      final r = FakeRouter([]);
      await read(r);
      await read(r);
      expect(r.asked[0]['nonce'], isNot(r.asked[1]['nonce']));
      expect(r.asked[0]['nonce'], matches(RegExp(r'^[0-9a-f]{32}$')));
    });
    test('a changed answer is not believed', () async {
      expect(await read(FakeRouter([row(1)])..tamper = true), isNull);
    });
    test('another router with the same address is not believed', () async {
      final other = FakeRouter([row(1)], routerKey: 'f' * 32);
      expect(await read(other), isNull);
      expect(
        await readFeed(
          (_) async => {'body': '{"newest":9}', 'sig': 'x'},
          key,
          0,
        ),
        isNull,
      );
    });
    test('odd answers', () async {
      for (final a in [
        null,
        <String, dynamic>{},
        {'body': 1, 'sig': 2},
      ]) {
        expect(await readFeed((_) async => a, key, 0), isNull);
      }
      String? nonce;
      expect(
        await readFeed(
          (p) async {
            nonce = p['nonce'] as String;
            return {'body': 'nope', 'sig': sha('$key:a:$nonce:nope:$key')};
          },
          key,
          0,
        ),
        isNull,
      );
    });
  });

  group('the check', () {
    test('off Wi-Fi does nothing', () async {
      final r = FakeRouter([row(1)]);
      expect(await check({'a': r}, wifi: false), CheckResult.notWifi);
      expect(r.asked, isEmpty);
    });
    test('routers without a key are never contacted', () async {
      final r = FakeRouter([row(1)]);
      expect(await check({'a': r}, keys: {}), CheckResult.nothingReachable);
      expect(r.asked, isEmpty);
    });
    test('only the reachable router counts', () async {
      await store.setLastId('a', 5);
      await store.setLastId('b', 0);
      final b = FakeRouter([row(1)]);
      expect(await check({'b': b}), CheckResult.done);
      expect(store.lastId('a'), 5);
      expect(store.lastId('b'), 1);
      expect(notified.single.$2, 'b');
    });
    test('first check is the baseline', () async {
      await check({
        'a': FakeRouter([row(39), row(40)]),
      });
      expect(store.lastId('a'), 40);
      expect(notified, isEmpty);
      expect(store.events('a'), hasLength(2));
    });
    test('one new event', () async {
      await store.setLastId('a', 1);
      await check({
        'a': FakeRouter([row(1), row(2)]),
      });
      expect((notified.single.$1 as NotifyOne).event.id, 2);
      expect(store.lastId('a'), 2);
    });
    test('a second check stays quiet', () async {
      await store.setLastId('a', 0);
      final r = FakeRouter([row(1)]);
      await check({'a': r});
      await check({'a': r});
      expect(notified, hasLength(1));
    });
    test('many events become one notification', () async {
      await store.setLastId('a', 0);
      await check({
        'a': FakeRouter([for (var i = 1; i <= 2500; i++) row(i)]),
      });
      expect(notified, hasLength(1));
      expect((notified.single.$1 as NotifySummary).count, 1000);
      expect(store.lastId('a'), 2500);
      expect(store.events('a'), hasLength(500));
    });
    test('muted phone still collects', () async {
      await store.setLastId('a', 0);
      await check({
        'a': FakeRouter([row(1)]),
      }, muted: true);
      expect(notified, isEmpty);
      expect(store.lastId('a'), 1);
    });
    test('a failed notification is tried again', () async {
      await store.setLastId('a', 0);
      final r = FakeRouter([row(1)]);
      await check({'a': r}, notify: (_, _) async => throw Exception('x'));
      expect(store.lastId('a'), 0);
      await check({'a': r});
      expect(notified, hasLength(1));
    });
    test('an outage that ended is updated without a second buzz', () async {
      await store.setLastId('a', 0);
      final r = FakeRouter([row(1, type: 'internet')]);
      await check({'a': r});
      expect(store.events('a').single.end, isNull);
      r.events = [row(1, type: 'internet', end: 1800000600)];
      await check({'a': r});
      expect(store.events('a').single.end, isNotNull);
      expect(notified, hasLength(1));
    });
    test('an open outage the router lost is dropped', () async {
      await store.setLastId('a', 5);
      await store.saveEvents('a', [
        AlertEvent.from(row(4))!,
        AlertEvent.from(row(5, type: 'internet'))!,
      ]);
      await check({
        'a': FakeRouter([row(1006, type: 'restart')]),
      });
      expect(store.events('a').map((e) => e.id), [1006, 4]);
    });
    test('a reinstalled router starts over', () async {
      await store.setLastId('a', 900);
      await store.saveEvents('a', [AlertEvent.from(row(900))!]);
      await check({
        'a': FakeRouter([row(1), row(2)]),
      });
      expect(store.lastId('a'), 2);
      expect(notified, isEmpty);
    });
    test('wrong key leaves everything alone', () async {
      await store.setLastId('a', 1);
      final r = FakeRouter([row(5)], routerKey: 'e' * 32);
      expect(await check({'a': r}), CheckResult.nothingReachable);
      expect(store.lastId('a'), 1);
      expect(widgets, isEmpty);
    });
    test('fills the widget', () async {
      await check({'a': FakeRouter([])..online = false});
      final w = widgets.single;
      expect(w.online, isFalse);
      expect(w.bars, 2);
      expect(w.dataLine, '18.0 GB this month');
      expect(w.routerName, 'a');
      expect(w.at, DateTime(2026, 11, 20, 14, 20));
      expect(w.data!.of, 'Unlimited');
      expect(w.signal, '−97 dBm');
    });
    test('the widget gets the bands from a newer router', () async {
      await check({
        'a': FakeRouter([])
          ..extra = {
            'sinr': 14,
            'band': 'B3 (1800 MHz)',
            'bands': ['B3', 'B1', 7, 'B1'],
          },
      });
      expect(widgets.single.signal, 'B3 + B1 + B1 · −97 dBm · SINR 14');
    });
    test('an older router has no signal line past rsrp', () async {
      await check({
        'a': FakeRouter([])..extra = {'rsrp': null},
      });
      expect(widgets.single.signal, isNull);
    });
    test('nothing escapes', () async {
      Never boom() => throw StateError('boom');
      final r = FakeRouter([row(1)]);
      for (var i = 0; i < 7; i++) {
        await runBackgroundCheck(
          CheckDeps(
            onWifi: () async => i == 0 ? boom() : true,
            routers: () async => i == 1 ? boom() : [router('a')],
            readKey: (_) async => i == 2 ? boom() : key,
            post: (_) async => i == 3 ? boom() : r.post,
            store: store,
            phoneMuted: () async => i == 4 ? boom() : false,
            notify: (_, _) async => i == 5 ? boom() : null,
            saveWidget: (_) async => i == 6 ? boom() : null,
            now: DateTime.now,
          ),
        );
      }
    });
  });

  group('store', () {
    test('keeps the newest 500, newest first', () async {
      await store.saveEvents('a', [
        for (var i = 1; i <= 600; i++) AlertEvent.from(row(i))!,
      ]);
      final e = store.events('a');
      expect(e, hasLength(500));
      expect(e.first.id, 600);
    });
    test('damaged cache reads as empty', () async {
      SharedPreferences.setMockInitialValues({'alerts.cache.a': '{nope'});
      expect(
        AlertsStore(await SharedPreferences.getInstance()).events('a'),
        isEmpty,
      );
    });
    test('routers are kept apart', () async {
      await store.saveEvents('a', [AlertEvent.from(row(1))!]);
      expect(store.events('b'), isEmpty);
    });
    test('forgetting a router', () async {
      await store.setLastId('a', 3);
      await store.saveEvents('a', [AlertEvent.from(row(1))!]);
      await store.forget('a');
      expect(store.lastId('a'), isNull);
      expect(store.events('a'), isEmpty);
    });
  });

  test('Wi-Fi is told apart from mobile data and VPN', () {
    expect(hasWifi(['lo', 'wlan0']), isTrue);
    expect(hasWifi(['rmnet_data0', 'tun0']), isFalse);
    expect(hasWifi(['wlan0', 'tun0']), isTrue);
    expect(hasWifi(['eth0']), isTrue);
    expect(hasWifi([]), isFalse);
  });

  group('interval', () {
    test('off until chosen', () async {
      final p = await SharedPreferences.getInstance();
      expect(BackgroundPrefs(p).interval, isNull);
    });
    test('remembers, and off turns off', () async {
      final b = BackgroundPrefs(await SharedPreferences.getInstance());
      await b.setInterval(const Duration(minutes: 30));
      expect(b.interval, const Duration(minutes: 30));
      await b.setInterval(null);
      expect(b.interval, isNull);
    });
    test('never faster than Android allows', () async {
      SharedPreferences.setMockInitialValues({'alerts.interval': 2});
      expect(
        BackgroundPrefs(await SharedPreferences.getInstance()).interval,
        const Duration(minutes: 15),
      );
    });
  });

  test('widget keys', () {
    expect(
      snapshotKeys(
        WidgetSnapshot(
          routerName: 'r',
          at: DateTime.fromMillisecondsSinceEpoch(5),
        ),
      ),
      {
        'widget.router': 'r',
        'widget.online': '',
        'widget.bars': '',
        'widget.data': '',
        'widget.used': '',
        'widget.of': '',
        'widget.pct': '',
        'widget.split': '',
        'widget.reset': '',
        'widget.compact': '',
        'widget.signal': '',
        'widget.at': '5',
      },
    );
    expect(
      snapshotKeys(
        WidgetSnapshot(
          routerName: 'r',
          online: false,
          bars: 3,
          dataLine: 'x',
          at: DateTime.fromMillisecondsSinceEpoch(5),
        ),
      ),
      containsPair('widget.online', '0'),
    );
    final keys = snapshotKeys(
      WidgetSnapshot(
        routerName: 'r',
        data: const DataLines(
          used: '1.0 GB',
          of: 'of 5 GB',
          percent: 20,
          split: 's',
          reset: 'r',
          compact: 'c',
        ),
        signal: 'B3',
        at: DateTime.fromMillisecondsSinceEpoch(5),
      ),
    );
    expect(keys['widget.pct'], '20');
    final partial = snapshotKeys(
      WidgetSnapshot(
        routerName: 'r',
        at: DateTime.fromMillisecondsSinceEpoch(5),
      ),
      signal: false,
      data: false,
    );
    expect(partial.keys, ['widget.router', 'widget.online', 'widget.at']);
    expect(keys['widget.signal'], 'B3');
    expect(keys.keys.last, 'widget.at');
  });
}
