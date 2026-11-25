// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_history.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_merge.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

HistoryPoint _p(int s, {double? rsrp}) =>
    HistoryPoint(t: DateTime.fromMillisecondsSinceEpoch(s * 1000), rsrp: rsrp);

SimTraffic _t(String sim) =>
    SimTraffic(sim: sim, label: sim, month: '2026-11', down: 1, up: 2);

class _Src implements HistorySource {
  _Src(this.d) : fail = false;
  _Src.fail() : d = null, fail = true;
  final HistoryData? d;
  final bool fail;

  @override
  Future<HistoryData?> load(DateTime from, DateTime to) async {
    if (fail) throw TimeoutException('slow');
    return d;
  }
}

void main() {
  final from = DateTime.fromMillisecondsSinceEpoch(0);
  final to = DateTime.fromMillisecondsSinceEpoch(10000 * 1000);

  test('parses helper rows and dashes', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (m, p) async {
        if (m == 'info') return {'ping_method': 'tcp'};
        expect(m, 'history');
        expect(p['from'], 0);
        expect(p['to'], 10000);
        return {
          'points': [
            [100, -90, 12.5, 30, '55', '1725', 'B3'],
            [200, '-', null, '-', '-', null, '-'],
          ],
          'traffic': [
            {'month': '2026-11', 'down': 10, 'up': 5},
          ],
        };
      },
    );
    final d = (await h.load(from, to))!;
    expect(d.points.length, 2);
    expect(d.points[0].t, DateTime.fromMillisecondsSinceEpoch(100000));
    expect(d.points[0].rsrp, -90);
    expect(d.points[0].sinr, 12.5);
    expect(d.points[0].ping, 30);
    expect(d.points[0].pci, '55');
    expect(d.points[0].band, 'B3');
    expect(d.points[1].rsrp, isNull);
    expect(d.points[1].ping, isNull);
    expect(d.points[1].band, isNull);
    expect(d.traffic.single.down, 10);
    expect(d.traffic.single.up, 5);
    expect(d.traffic.single.month, '2026-11');
    expect(d.traffic.single.sim, 'helper');
    expect(d.pingMethod, 'tcp');
  });

  test('ping method is null when info fails', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (m, p) async {
        if (m == 'info') throw const NoobRpcError('Method not found');
        return {'points': []};
      },
    );
    expect((await h.load(from, to))!.pingMethod, isNull);
  });

  HistoryPoint at(int s, {double? rsrp, double? sinr, double? ping}) =>
      HistoryPoint(
        t: DateTime.fromMillisecondsSinceEpoch(s * 1000),
        rsrp: rsrp,
        sinr: sinr,
        ping: ping,
      );
  HistoryData g(List<HistoryPoint> p) =>
      HistoryData(points: p, traffic: const [], pingMethod: 'icmp');
  HistoryData h(List<HistoryPoint> p) =>
      HistoryData(points: p, traffic: const [], pingMethod: 'tcp');

  test('merge takes the helper ping method only for helper pings', () {
    expect(mergeHistory(g([_p(100)]), h([at(50, ping: 9)]))!.pingMethod, 'tcp');
    expect(mergeHistory(g([_p(100)]), h([_p(50)]))!.pingMethod, 'icmp');
    expect(mergeHistory(g([_p(100)]), h(const []))!.pingMethod, 'icmp');
  });

  test('null 5G values fill from the nearest helper point', () {
    final m = mergeHistory(
      g([
        at(1000, rsrp: -90, sinr: 10),
        at(2000, rsrp: -91),
        at(3000, rsrp: -92),
      ]),
      h([
        at(900, ping: 1),
        at(1030, ping: 30, sinr: 5),
        at(1990, ping: 40, sinr: 6),
        at(2100, ping: 50),
      ]),
    )!;
    expect(m.points.map((p) => p.t.millisecondsSinceEpoch ~/ 1000), [
      900,
      1000,
      2000,
      3000,
    ]);
    expect(m.points.map((p) => p.ping), [1, 30, 40, null]);
    expect(m.points.map((p) => p.sinr), [null, 10, 6, null]);
    expect(m.points.map((p) => p.rsrp), [null, -90, -91, -92]);
    expect(m.pingMethod, 'tcp');
  });

  test('5G ping present is kept', () {
    final m = mergeHistory(
      g([at(1000, rsrp: -90, sinr: 10, ping: 20)]),
      h([at(1000, rsrp: -80, sinr: 1, ping: 99)]),
    )!;
    expect(m.points.single.ping, 20);
    expect(m.points.single.rsrp, -90);
    expect(m.pingMethod, 'icmp');
  });

  test('returns null when the helper is not on the router', () async {
    for (final m in ['Method not found', 'Not found', 'Permission denied']) {
      final h = HelperHistory(
        _FakeApp(),
        call: (_, _) async => throw NoobRpcError(m),
      );
      expect(await h.load(from, to), isNull);
    }
  });

  test('throws when the call times out', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (_, _) async => throw TimeoutException('slow'),
    );
    await expectLater(h.load(from, to), throwsA(isA<TimeoutException>()));
  });

  group('loadHistory', () {
    final a = HistoryData(points: [_p(100)], traffic: const []);
    final b = HistoryData(points: [_p(50)], traffic: const []);

    test('merges sources in order', () async {
      final d = await loadHistory([_Src(a), _Src(b)], from, to);
      expect(d!.points.map((p) => p.t), [_p(50).t, _p(100).t]);
    });

    test('one source failing still returns the other', () async {
      final d = await loadHistory([_Src.fail(), _Src(b)], from, to);
      expect(identical(d, b), isTrue);
    });

    test('throws when no source has data and one threw', () async {
      await expectLater(
        loadHistory([_Src(null), _Src.fail()], from, to),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        loadHistory([_Src.fail(), _Src.fail()], from, to),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('null when no source is present', () async {
      expect(await loadHistory([_Src(null), _Src(null)], from, to), isNull);
      expect(await loadHistory(const [], from, to), isNull);
    });
  });

  test('helperVersion', () async {
    expect(
      await helperVersion(
        _FakeApp(),
        call: (m, p) async => {'version': '0.1.0'},
      ),
      '0.1.0',
    );
    expect(await helperVersion(_FakeApp(), call: (m, p) async => {}), isNull);
    expect(
      await helperVersion(_FakeApp(), call: (m, p) async => throw 'x'),
      isNull,
    );
  });

  test('keeps 5G points and only older helper points', () {
    final m = mergeHistory(
      HistoryData(points: [_p(100, rsrp: 1), _p(200)], traffic: const []),
      HistoryData(points: [_p(50), _p(100), _p(150)], traffic: const []),
    )!;
    expect(m.points.map((p) => p.t.millisecondsSinceEpoch ~/ 1000), [
      50,
      100,
      200,
    ]);
    expect(m.points[1].rsrp, 1);
  });

  test('5G traffic wins, else helper', () {
    final a = HistoryData(points: [_p(1)], traffic: [_t('a')]);
    final b = HistoryData(points: [_p(0)], traffic: [_t('b')]);
    expect(mergeHistory(a, b)!.traffic.single.sim, 'a');
    final e = HistoryData(points: [_p(1)], traffic: const []);
    expect(mergeHistory(e, b)!.traffic.single.sim, 'b');
  });

  test('one source returned unchanged', () {
    final a = HistoryData(points: [_p(1)], traffic: const []);
    expect(identical(mergeHistory(a, null), a), isTrue);
    expect(identical(mergeHistory(null, a), a), isTrue);
    expect(mergeHistory(null, null), isNull);
  });

  test('since: helper empty keeps 5G since', () {
    final since = DateTime.fromMillisecondsSinceEpoch(77000);
    final m = mergeHistory(
      HistoryData(points: [_p(100)], traffic: const [], since: since),
      const HistoryData(points: [], traffic: []),
    )!;
    expect(m.since, since);
  });

  test('since: helper fills older data uses earliest point', () {
    final m = mergeHistory(
      HistoryData(
        points: [_p(100)],
        traffic: const [],
        since: DateTime.fromMillisecondsSinceEpoch(100000),
      ),
      HistoryData(points: [_p(50), _p(60)], traffic: const []),
    )!;
    expect(m.since, DateTime.fromMillisecondsSinceEpoch(50000));
  });

  test('bad traffic values are skipped, non-list points are empty', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (m, p) async => {
        'points': 'nope',
        'traffic': [
          {'month': '2026-10', 'down': '-', 'up': 'x'},
          {'month': '2026-11', 'down': '7', 'up': 3},
        ],
      },
    );
    final d = (await h.load(from, to))!;
    expect(d.points, isEmpty);
    expect(d.traffic.single.down, 7);
    expect(d.traffic.single.up, 3);
    final h2 = HelperHistory(
      _FakeApp(),
      call: (m, p) async => {'points': [], 'traffic': 5},
    );
    expect((await h2.load(from, to))!.traffic, isEmpty);
  });

  test('rows are sorted, string t accepted, short rows skipped', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (m, p) async => {
        'points': [
          [300, -1, 1, 1, null, null, null],
          ['100', -2, 1, 1, null, null, null],
          [200, -3],
        ],
      },
    );
    final d = (await h.load(from, to))!;
    expect(d.points.map((p) => p.rsrp), [-2, -1]);
  });

  test('non-finite timestamps skip the row only', () async {
    final h = HelperHistory(
      _FakeApp(),
      call: (m, p) async => {
        'points': [
          ['NaN', -1, 1, 1, null, null, null],
          ['Infinity', -2, 1, 1, null, null, null],
          [100, -3, 1, 1, null, null, null],
        ],
      },
    );
    final d = (await h.load(from, to))!;
    expect(d.points.map((p) => p.rsrp), [-3]);
  });
}
