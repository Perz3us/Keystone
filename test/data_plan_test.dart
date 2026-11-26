import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';

SimPlan plan(
  PlanKind kind, {
  int? gb,
  double usedGb = 0,
  int day = 15,
  DateTime? start,
  DateTime? end,
  DateTime? since,
}) => SimPlan(
  sim: 'main',
  kind: kind,
  allowanceGb: gb,
  billingDay: day,
  periodStart: start ?? DateTime.utc(2026, 11, 15),
  periodEnd: end ?? DateTime.utc(2026, 12, 14),
  down: (usedGb * 1e9).round(),
  up: 0,
  since: since,
);

Map<String, dynamic> entry([Map<String, dynamic> over = const {}]) => {
  'sim': 'main',
  'plan': 'capped',
  'allowance_gb': 50,
  'billing_day': 15,
  'period_start': '2026-11-15',
  'period_end': '2026-12-14',
  'down': 30,
  'up': 3,
  ...over,
};

void main() {
  final now = DateTime(2026, 11, 20, 23, 30);

  group('capStatus', () {
    test('capped shows the share used and days left, today included', () {
      final s = capStatus(plan(PlanKind.capped, gb: 10, usedGb: 6.2), now);
      expect(s.fraction, closeTo(0.62, 0.001));
      expect(s.daysLeft, 25);
    });
    test('last day of the period still has one day left', () {
      final s = capStatus(
        plan(PlanKind.capped, gb: 10),
        DateTime(2026, 12, 14),
      );
      expect(s.daysLeft, 1);
    });
    test('a period that ended while the app was open never goes negative', () {
      final s = capStatus(plan(PlanKind.capped, gb: 10), DateTime(2027, 1, 5));
      expect(s.daysLeft, 0);
    });

    final nov = (DateTime.utc(2026, 11), DateTime.utc(2026, 11, 30));
    SimPlan inNov(double used, [PlanKind k = PlanKind.capped]) =>
        plan(k, gb: 10, usedGb: used, day: 1, start: nov.$1, end: nov.$2);
    test('running too fast gives the day it runs out', () {
      expect(
        capStatus(inNov(4), DateTime(2026, 11, 5)).runsOutOn,
        DateTime.utc(2026, 11, 13),
      );
    });
    test('counting that began late measures the pace from that day', () {
      final p = plan(
        PlanKind.capped,
        gb: 10,
        usedGb: 4,
        day: 1,
        start: nov.$1,
        end: nov.$2,
        since: DateTime.utc(2026, 11, 10),
      );
      expect(
        capStatus(p, DateTime(2026, 11, 14)).runsOutOn,
        DateTime.utc(2026, 11, 22),
      );
    });
    test('and waits three counted days before guessing', () {
      final p = plan(
        PlanKind.capped,
        gb: 10,
        usedGb: 4,
        day: 1,
        start: nov.$1,
        end: nov.$2,
        since: DateTime.utc(2026, 11, 13),
      );
      expect(capStatus(p, DateTime(2026, 11, 14)).runsOutOn, isNull);
    });
    test('on pace', () {
      expect(capStatus(inNov(1), DateTime(2026, 11, 5)).runsOutOn, isNull);
    });
    test('too early to tell', () {
      expect(capStatus(inNov(4), DateTime(2026, 11, 2)).runsOutOn, isNull);
    });
    test('nothing used', () {
      expect(capStatus(inNov(0), DateTime(2026, 11, 9)).runsOutOn, isNull);
    });
    test('already used up does not also predict', () {
      expect(capStatus(inNov(11), DateTime(2026, 11, 9)).runsOutOn, isNull);
    });
    test('fair use has a limit but no run-out day', () {
      final s = capStatus(inNov(4, PlanKind.fairuse), DateTime(2026, 11, 5));
      expect(s.limit, 10000000000);
      expect(s.runsOutOn, isNull);
    });
    test('unlimited has no limit', () {
      final s = capStatus(inNov(4, PlanKind.unlimited), now);
      expect(s.fraction, isNull);
      expect(s.limit, isNull);
      expect(s.used, 4000000000);
    });
    test('capped without an allowance behaves like no limit', () {
      expect(capStatus(plan(PlanKind.capped), now).fraction, isNull);
    });
  });

  group('client', () {
    DataPlanClient client(
      Map<String, dynamic> Function(String, Map<String, dynamic>) f,
    ) => DataPlanClient((m, p) async => f(m, p));

    test('reads plans and the active SIM', () async {
      final d = await client(
        (_, _) => {
          'active_sim': 'main',
          'plans': [
            entry({'sim': 'other'}),
            entry(),
          ],
        },
      ).load();
      expect(d!.active!.allowanceGb, 50);
      expect(d.active!.used, 33);
      expect(d.active!.periodEnd, DateTime.utc(2026, 12, 14));
      expect(d.active!.since, isNull);
    });
    test('reads the day counting began', () async {
      final d = await client(
        (_, _) => {
          'active_sim': 'main',
          'plans': [
            entry({'since': '2026-11-18'}),
          ],
        },
      ).load();
      expect(d!.active!.since, DateTime.utc(2026, 11, 18));
    });
    test('a SIM without a plan', () async {
      final d = await client(
        (_, _) => {
          'active_sim': 'main',
          'plans': [
            entry({'plan': '', 'allowance_gb': 0}),
          ],
        },
      ).load();
      expect(d!.active!.kind, PlanKind.none);
      expect(d.active!.allowanceGb, isNull);
    });
    test('a plan kind from a newer router counts as none', () async {
      final d = await client(
        (_, _) => {
          'active_sim': 'main',
          'plans': [
            entry({'plan': 'rollover'}),
          ],
        },
      ).load();
      expect(d!.active!.kind, PlanKind.none);
    });
    test('bad rows are skipped', () async {
      final d = await client(
        (_, _) => {
          'active_sim': 'main',
          'plans': [
            'x',
            entry({'period_start': 'soon'}),
            entry({'sim': null}),
            entry(),
          ],
        },
      ).load();
      expect(d!.plans, hasLength(1));
    });
    test('an active SIM with no traffic yet', () async {
      final d = await client(
        (_, _) => {'active_sim': 'new', 'plans': <Object>[]},
      ).load();
      expect(d!.active, isNull);
      expect(d.activeSim, 'new');
    });
    test('older keystone-history', () async {
      expect(await client((_, _) => {'version': '0.2.0'}).load(), isNull);
    });
    test('not installed', () async {
      expect(
        await client(
          (_, _) => throw const NoobRpcError('Method not found'),
        ).load(),
        isNull,
      );
      expect(await client((_, _) => throw NoobRpcError.refused).load(), isNull);
    });
    test('a dropped connection is an error, not "not installed"', () {
      expect(
        client((_, _) => throw const NoobRpcError('Timed out')).load(),
        throwsA(isA<NoobRpcError>()),
      );
    });
    test('save sends the plan', () async {
      Map<String, dynamic>? sent;
      final p =
          await client((m, p) {
            expect(m, 'set_plan');
            sent = p;
            return entry();
          }).save(
            sim: 'main',
            kind: PlanKind.capped,
            allowanceGb: 50,
            billingDay: 15,
          );
      expect(sent, {
        'sim': 'main',
        'plan': 'capped',
        'allowance_gb': 50,
        'billing_day': 15,
      });
      expect(p.allowanceGb, 50);
    });
    test('unlimited sends no allowance', () async {
      Map<String, dynamic>? sent;
      await client((_, p) {
        sent = p;
        return entry({'plan': 'unlimited', 'allowance_gb': 0});
      }).save(
        sim: 'main',
        kind: PlanKind.unlimited,
        allowanceGb: 9,
        billingDay: 1,
      );
      expect(sent!.containsKey('allowance_gb'), isFalse);
    });
    test('save error from the router', () {
      expect(
        client(
          (_, _) => {'error': 'billing_day must be 1-31'},
        ).save(sim: 'main', kind: PlanKind.unlimited, billingDay: 40),
        throwsA(
          isA<NoobRpcError>().having(
            (e) => e.message,
            'message',
            'billing_day must be 1-31',
          ),
        ),
      );
    });
  });
}
