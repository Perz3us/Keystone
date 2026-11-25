import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/screens/speed/speed_test.dart';

const _start =
    '{"type":"testStart","isp":"Bharti Airtel","interface":{"externalIp":"1.2.3.4"},'
    '"server":{"id":1,"name":"Jio","location":"Colombo","country":"Sri Lanka"}}';
const _ping =
    '{"type":"ping","ping":{"jitter":2.1,"latency":31.4,"progress":1.0}}';
const _down =
    '{"type":"download","download":{"bandwidth":5000000,"bytes":1,"elapsed":800,"progress":0.4}}';
const _up =
    '{"type":"upload","upload":{"bandwidth":1250000,"bytes":1,"elapsed":800,"progress":0.5}}';
const _result =
    '{"type":"result","ping":{"jitter":2.1,"latency":31.4},'
    '"download":{"bandwidth":5350000,"bytes":60000000},'
    '"upload":{"bandwidth":1150000,"bytes":12000000},"packetLoss":0.5,'
    '"isp":"Bharti Airtel","server":{"name":"Jio","location":"Colombo"},'
    '"result":{"url":"https://www.speedtest.net/result/c/abc"}}';

void main() {
  test('nothing yet', () {
    final p = SpeedTestProgress.parse('');
    expect(p.phase, SpeedPhase.starting);
  });

  test('ping, then download with a live number', () {
    final p = SpeedTestProgress.parse('$_start\n$_ping\n$_down\n');
    expect(p.phase, SpeedPhase.download);
    expect(p.liveMbps, closeTo(40, 0.01));
    expect(p.progress, 0.4);
    expect(p.pingMs, 31.4);
    expect(p.server, 'Jio · Colombo');
    expect(p.isp, 'Bharti Airtel');
  });

  test('upload keeps the download it measured', () {
    final p = SpeedTestProgress.parse('$_start\n$_ping\n$_down\n$_up\n');
    expect(p.phase, SpeedPhase.upload);
    expect(p.downMbps, closeTo(40, 0.01));
    expect(p.liveMbps, closeTo(10, 0.01));
  });

  test('the result', () {
    final p = SpeedTestProgress.parse('$_start\n$_down\n$_result\n');
    expect(p.phase, SpeedPhase.done);
    expect(p.downMbps, closeTo(42.8, 0.01));
    expect(p.upMbps, closeTo(9.2, 0.01));
    expect(p.jitterMs, 2.1);
    expect(p.packetLoss, 0.5);
    expect(p.resultUrl, 'https://www.speedtest.net/result/c/abc');
  });

  test('an error, or junk, says it failed', () {
    final e = SpeedTestProgress.parse(
      '{"type":"log","level":"error","message":"Cannot open socket"}\n',
    );
    expect(e.phase, SpeedPhase.failed);
    expect(e.error, 'Cannot open socket');
    final j = SpeedTestProgress.parse('sh: ookla-speedtest: not found\n');
    expect(j.phase, SpeedPhase.failed);
  });

  test('a half-written last line is ignored', () {
    final p = SpeedTestProgress.parse('$_start\n$_ping\n{"type":"downl');
    expect(p.phase, SpeedPhase.ping);
  });

  test('history round-trips', () {
    final r = SpeedResult(
      at: DateTime.utc(2026, 11, 23, 10),
      downMbps: 42.8,
      upMbps: 9.2,
      pingMs: 31,
    );
    expect(SpeedResult.fromJson(r.toJson()).downMbps, 42.8);
    expect(SpeedResult.fromJson(r.toJson()).at, r.at);
  });

  test('a real AW1000 run: IP, server, samples, loaded ping', () {
    final p = SpeedTestProgress.parse(
      File('test/fixtures/speedtest_aw1000.jsonl').readAsStringSync(),
    );
    expect(p.phase, SpeedPhase.done);
    expect(p.downMbps, closeTo(30.9, 0.05));
    expect(p.upMbps, closeTo(27.6, 0.05));
    expect(p.pingMs, closeTo(95.1, 0.05));
    expect(p.externalIp, '168.107.94.49');
    expect(p.server, 'AIXXYCODE.ID · Singapore');
    expect(p.isp, 'Oracle Cloud');
    expect(p.downSamples.length, greaterThan(20));
    expect(p.upSamples.length, greaterThan(20));
    expect(p.downSamples.length, lessThanOrEqualTo(60));
    expect(p.downLoadedPingMs, closeTo(99.7, 0.05));
    expect(p.upLoadedPingMs, closeTo(183.9, 0.05));
  });

  test('history keeps the server', () {
    final r = SpeedResult(
      at: DateTime.utc(2026),
      downMbps: 1,
      upMbps: 1,
      server: 'Jio · Colombo',
    );
    expect(SpeedResult.fromJson(r.toJson()).server, 'Jio · Colombo');
  });
}
