import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_models.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alert_notify_plan.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';

Map<String, dynamic> row(
  int id, {
  Object? type = 'device',
  Object? start = 1800000000,
  Object? end,
  Object? approx = false,
  Object? detail = const {'mac': 'aa'},
}) => {
  'id': id,
  'type': type,
  'start': start,
  'end': end,
  'approx': approx,
  'detail': detail,
};

class FakeRouter {
  FakeRouter(this.first, this.last, {this.trimmed = false});
  final int first, last;
  final bool trimmed;
  int calls = 0;

  Future<Map<String, dynamic>> call(String m, Map<String, dynamic> p) async {
    calls++;
    final since = p['since'] as int;
    final from = since + 1 < first ? first : since + 1;
    return {
      'events': [for (var i = from; i <= last && i < from + 100; i++) row(i)],
      'trimmed': trimmed && calls == 1,
      'newest': last,
    };
  }
}

AlertEvent event(AlertType type, {int id = 1, DateTime? end}) => AlertEvent(
  id: id,
  type: type,
  start: DateTime(2026, 11, 20, 14),
  end: end,
  approx: false,
  detail: const {},
);

void main() {
  group('collectSince', () {
    test('pages to the newest', () async {
      final r = FakeRouter(1, 250);
      final c = await collectSince(AlertsClient(r.call), 0);
      expect(r.calls, 3);
      expect(c.events, hasLength(250));
      expect(c.newest, 250);
    });
    test('nothing new', () async {
      final r = FakeRouter(1, 250);
      final c = await collectSince(AlertsClient(r.call), 250);
      expect(r.calls, 1);
      expect(c.events, isEmpty);
      expect(c.newest, 250);
    });
    test('keeps only the newest 1000', () async {
      final c = await collectSince(AlertsClient(FakeRouter(1, 5000).call), 0);
      expect(c.events, hasLength(1000));
      expect(c.events.last.id, 5000);
      expect(c.newest, 5000);
    });
    test('remembers that older ones were removed', () async {
      final r = FakeRouter(300, 450, trimmed: true);
      expect((await collectSince(AlertsClient(r.call), 10)).trimmed, isTrue);
    });
    test('a reinstalled router starts over', () async {
      final c = await collectSince(AlertsClient(FakeRouter(1, 3).call), 90);
      expect(c.events, isEmpty);
      expect(c.newest, 3);
    });
    test('a router that never advances cannot loop forever', () async {
      var calls = 0;
      final c = await collectSince(
        AlertsClient((_, _) async {
          calls++;
          return {
            'events': [row(1)],
            'trimmed': false,
            'newest': 99,
          };
        }),
        0,
      );
      expect(calls, lessThan(4));
      expect(c.events, hasLength(1));
    });
    test('id gaps after a power cut', () async {
      var calls = 0;
      final c = await collectSince(
        AlertsClient((_, p) async {
          calls++;
          return {
            'events': [
              for (final i in [5, 1006])
                if (i > (p['since'] as int)) row(i),
            ],
            'trimmed': false,
            'newest': 1006,
          };
        }),
        4,
      );
      expect([for (final e in c.events) e.id], [5, 1006]);
      expect(calls, 1);
    });
  });

  group('parsing', () {
    Future<List<AlertEvent>> parse(List<Object?> rows) async =>
        (await AlertsClient(
          (_, _) async => {'events': rows, 'trimmed': false, 'newest': 9},
        ).events(0)).events;

    test('times', () async {
      final e = (await parse([
        row(1, type: 'internet', end: 1800000060),
      ])).single;
      expect(e.end!.difference(e.start!), const Duration(minutes: 1));
    });
    test('still going', () async {
      expect((await parse([row(1, type: 'internet')])).single.end, isNull);
    });
    test('approximate', () async {
      expect((await parse([row(1, approx: true)])).single.approx, isTrue);
    });
    test('unknown kinds and broken rows are skipped', () async {
      final e = await parse([
        'x',
        row(1, type: 'volcano'),
        {'type': 'device'},
        row(2, start: null, detail: 'x'),
      ]);
      expect(e.single.id, 2);
      expect(e.single.start, isNull);
      expect(e.single.detail, isEmpty);
    });
    test('cache round trip', () {
      final e = AlertEvent.from(
        event(AlertType.internet, end: DateTime(2026, 11, 20, 15)).toCache(),
      )!;
      expect(e.end, DateTime(2026, 11, 20, 15));
      expect(e.type, AlertType.internet);
    });
  });

  group('info and settings', () {
    final info = {
      'version': '0.1.0',
      'newest': 7,
      'oldest': 2,
      'settings': {
        'internet': {'mode': 'off'},
        'signal': {'mode': 'log', 'rsrp_below': -115},
        'device': {'mode': 'buzz'},
        'data': {'mode': 'buzz', 'warn_pct': 70, 'fairuse_pct': 85},
        'restart': {'mode': 'bang'},
      },
    };
    test('reads', () async {
      final i = (await AlertsClient((_, _) async => info).info())!;
      expect(i.newest, 7);
      expect(i.settings.modes[AlertType.internet], AlertMode.off);
      expect(i.settings.rsrpBelow, -115);
      expect(i.settings.warnPct, 70);
      expect(i.settings.modes[AlertType.restart], AlertMode.log);
    });
    test('not installed', () async {
      for (final e in [
        const NoobRpcError('Method not found'),
        NoobRpcError.refused,
      ]) {
        expect(await AlertsClient((_, _) async => throw e).info(), isNull);
      }
    });
    test('a lost connection is not "not installed"', () {
      expect(
        AlertsClient(
          (_, _) async => throw const NoobRpcError('Timed out'),
        ).info(),
        throwsA(isA<NoobRpcError>()),
      );
    });
    test('saves everything', () async {
      Map<String, dynamic>? sent;
      final c = AlertsClient((m, p) async {
        sent = p;
        return {};
      });
      await c.save(
        const AlertSettings().copyWith(
          mode: (AlertType.signal, AlertMode.buzz),
          rsrpBelow: -112,
        ),
      );
      expect(sent!['signal'], {'mode': 'buzz', 'rsrp_below': -112});
      expect(sent!['data'], {
        'mode': 'buzz',
        'warn_pct': 80,
        'fairuse_pct': 90,
      });
    });
    test('router refuses', () {
      expect(
        AlertsClient(
          (_, _) async => {'error': 'no'},
        ).save(const AlertSettings()),
        throwsA(isA<NoobRpcError>()),
      );
    });
  });

  group('what to notify', () {
    const s = AlertSettings();
    NotifyPlan plan(List<AlertEvent> e, {bool muted = false}) =>
        planNotifications(e, s, phoneMuted: muted);

    test('nothing', () => expect(plan([]), isA<NotifyNone>()));
    test('log only', () {
      expect(plan([event(AlertType.signal)]), isA<NotifyNone>());
    });
    test('one', () {
      final p = plan([event(AlertType.signal), event(AlertType.device, id: 2)]);
      expect((p as NotifyOne).event.id, 2);
    });
    test('several become one summary', () {
      final p = plan([
        for (var i = 1; i <= 3; i++) event(AlertType.device, id: i),
      ]);
      expect((p as NotifySummary).count, 3);
    });
    test('muted', () {
      expect(plan([event(AlertType.device)], muted: true), isA<NotifyNone>());
    });
    test('an outage still going counts', () {
      expect(plan([event(AlertType.internet)]), isA<NotifyOne>());
    });
  });

  group('words', () {
    AlertEvent e(AlertType t, Map<String, dynamic> d, {DateTime? end}) =>
        AlertEvent(
          id: 1,
          type: t,
          start: DateTime(2026, 11, 20, 14, 2),
          end: end,
          approx: false,
          detail: d,
        );
    final cases = {
      'Internet was down for 12 min': e(AlertType.internet, {
        'drops': 1,
      }, end: DateTime(2026, 11, 20, 14, 14)),
      'Internet is down': e(AlertType.internet, {}),
      'Internet was down for 1 h 5 min': e(
        AlertType.internet,
        {},
        end: DateTime(2026, 11, 20, 15, 7),
      ),
      'Internet was down for under a minute': e(
        AlertType.internet,
        {},
        end: DateTime(2026, 11, 20, 14, 2, 30),
      ),
      'New device: Pixel-9': e(AlertType.device, {
        'name': 'Pixel-9',
        'mac': 'aa:bb',
      }),
      'New device: aa:bb': e(AlertType.device, {'name': '', 'mac': 'aa:bb'}),
      'New device joined': e(AlertType.device, {}),
      '81% of your data used': e(AlertType.data, {'level': 'warn', 'pct': 81}),
      'Your data is used up': e(AlertType.data, {'level': 'full', 'pct': 101}),
      'Close to the fair-use limit': e(AlertType.data, {'level': 'fairuse'}),
      'At this rate data runs out on 13 Nov': e(AlertType.data, {
        'level': 'pace',
        'runs_out': '2026-11-13',
      }),
      'Data is being used too fast': e(AlertType.data, {'level': 'pace'}),
      'Signal dropped to -114 dBm': e(AlertType.signal, {'rsrp': -114}),
      'Signal dropped': e(AlertType.signal, {}),
      'Router restarted': e(AlertType.restart, {'what': 'router'}),
      'Modem restarted': e(AlertType.restart, {'what': 'modem'}),
    };
    cases.forEach((want, ev) => test(want, () => expect(alertTitle(ev), want)));
  });
}
