// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/fivegmodem_history.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

void main() {
  final now = DateTime(2026, 11, 25, 14, 30);

  test('maps uptime seconds to clock times', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(70, -92.0)],
      },
      towerLog: '',
      uptimeNow: 13515,
      now: now,
    );
    expect(pts.single.t, now.subtract(const Duration(seconds: 13445)));
    expect(pts.single.rsrp, -92);
  });

  test('merges samples within 5 s into one point', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(258, -94.0), (338, -94.0), (1241, -92.0)],
        'sinr': [(259, 16.0), (338, 16.0), (1241, 17.0)],
        'ping': [(258, 40.0), (306, 41.0), (1240, 42.0)],
      },
      towerLog: '',
      uptimeNow: 2000,
      now: now,
    );
    expect(pts.map((p) => (p.rsrp, p.sinr, p.ping)), [
      (-94, 16, 40),
      (null, null, 41),
      (-94, 16, null),
      (-92, 17, 42),
    ]);
    expect(pts.first.t, now.subtract(const Duration(seconds: 1742)));
  });

  test('samples more than 5 s apart stay separate', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(100, -90.0), (101, -91.0)],
        'sinr': [(107, 10.0)],
      },
      towerLog: '',
      uptimeNow: 200,
      now: now,
    );
    expect(pts.map((p) => (p.rsrp, p.sinr)), [
      (-90, null),
      (-91, null),
      (null, 10),
    ]);
  });

  test('5G ping of 0 or less is no reading', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(100, -90.0), (200, -91.0)],
        'ping': [(100, 0.0), (200, -1.0)],
      },
      towerLog: '',
      uptimeNow: 300,
      now: now,
    );
    expect(pts.map((p) => p.ping), [null, null]);
    expect(pts.map((p) => p.rsrp), [-90, -91]);
  });

  test('attaches tower log to the nearest point', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(60, -92.0), (500, -90.0)],
      },
      towerLog: '50 -92 -11 17 -63 151 1725 B3 (1800 MHz) @20 MHz\n',
      uptimeNow: 13515,
      now: now,
    );
    expect(pts[0].pci, '151');
    expect(pts[0].earfcn, '1725');
    expect(pts[0].band, 'B3 (1800 MHz) @20 MHz');
    expect(pts[1].pci, isNull);
  });

  test('drops future points and keeps bad values null', () {
    final pts = parseFiveG(
      series: {
        'rsrp': [(70, -92.0), (99999, -80.0)],
        'sinr': [(70, double.nan)],
      },
      towerLog: '',
      uptimeNow: 13515,
      now: now,
    );
    expect(pts, hasLength(1));
    expect(pts.single.sinr, isNull);
    expect(pts.single.ping, isNull);
  });

  test('parses traffic with operator label', () {
    final t = parseTraffic(
      {
        'labels': {'op.sim-8994052209514477652': 'airtel'},
      },
      {
        'sim-8994052209514477652|2026-11': {
          'rx': 92425467438,
          'tx': 16022206476,
        },
      },
    );
    expect(t.single.sim, 'sim-8994052209514477652');
    expect(t.single.label, 'airtel');
    expect(t.single.month, '2026-11');
    expect(t.single.down, 92425467438);
    expect(t.single.up, 16022206476);
  });

  test('load returns null when the stats script is missing', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: (_) async => throw const NoobRpcError('Not found'),
    );
    expect(await h.load(now, now), isNull);
    final g = FiveGModemHistory(
      _FakeApp(),
      stats: (_) async => 'sh: stats.sh: not found',
    );
    expect(await g.load(now, now), isNull);
  });

  test('load throws when the router denies the stats script', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: (_) async => throw const NoobRpcError('Permission denied'),
    );
    await expectLater(h.load(now, now), throwsA(isA<NoobRpcError>()));
  });

  test('load throws when the router times out', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: (_) async => throw TimeoutException('slow'),
    );
    await expectLater(h.load(now, now), throwsA(isA<TimeoutException>()));
  });

  test('load throws when uptime read fails on the network', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: (_) async => '{}',
      readFile: (_) async => throw TimeoutException('slow'),
    );
    await expectLater(h.load(now, now), throwsA(isA<TimeoutException>()));
  });

  Future<String> Function(List<String>) stats({
    bool pingFails = false,
  }) => (a) async {
    if (a[0] == 'list') {
      return '{"rsrp":["m_4_1"],"sinr":["m_4_1"],"ping":["modem"],"labels":{}}';
    }
    if (a[0] == 'traffic') throw Exception('x');
    if (a[1].startsWith('ping') && pingFails) throw Exception('x');
    return '{"series":[[100,-90],[13000,-91]]}';
  };
  Future<String> Function(String) files(String uptime) =>
      (p) async => p == '/proc/uptime' ? uptime : '';

  test('failed ping series still yields rsrp points', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: stats(pingFails: true),
      readFile: files('13515.09 46527.27'),
      now: () => now,
    );
    final d = await h.load(DateTime(2000), now);
    expect(d!.points, hasLength(2));
    expect(d.points.first.rsrp, -90);
    expect(d.points.first.ping, isNull);
    expect(d.pingMethod, 'icmp');
  });

  test('unparseable uptime returns null', () async {
    final h = FiveGModemHistory(
      _FakeApp(),
      stats: stats(),
      readFile: files('garbage'),
      now: () => now,
    );
    expect(await h.load(DateTime(2000), now), isNull);
  });

  test('filters to range and sets since only when data starts late', () async {
    FiveGModemHistory h() => FiveGModemHistory(
      _FakeApp(),
      stats: stats(),
      readFile: files('13515.09 1'),
      now: () => now,
    );
    final first = now.subtract(const Duration(seconds: 13415));
    final d = (await h().load(first.add(const Duration(hours: -1)), now))!;
    expect(d.points, hasLength(2));
    expect(d.since, first);
    final e = (await h().load(first.add(const Duration(minutes: 1)), now))!;
    expect(e.points, hasLength(1));
    final f = (await h().load(first, now))!;
    expect(f.since, isNull);
  });

  test('skips traffic entries with no rx and tx', () {
    expect(
      parseTraffic({}, {
        'a|2026-11': {'x': 1},
      }),
      isEmpty,
    );
  });
}
