// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/cellular/lock_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_controls.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _Fake {
  final calls = <String>[];
  final Map<String, String> out;
  final Set<String> fail;
  _Fake(this.out, {this.fail = const {}});

  Future<String> run(String script, List<String> args) async {
    final key = '${script.split('/').last} ${args.join(' ')}'.trim();
    calls.add(key);
    if (fail.contains(key)) throw const NoobRpcError('boom');
    return out[key] ?? '';
  }
}

class _FakeApp extends Fake implements AppState {}

FiveGModemControls _make(
  _Fake f, {
  Future<List<Map<String, dynamic>>> Function(String)? sections,
  List<String>? sets,
}) => FiveGModemControls(
  _FakeApp(),
  run: f.run,
  sections: sections ?? (_) async => const [],
  uciSet: (c, s, v) async => sets?.add('$c $s $v'),
);

Future<List<Map<String, dynamic>>> _apnSections(String c) async => switch (c) {
  '5gmodem' => [
    {'active_modem': '1-1.2', 'network': 'wan5g'},
    {'.name': 'm_1_1_2', 'apn_mode': 'auto', 'network': 'wwan'},
  ],
  _ => [],
};

void main() {
  test('netModes parses modes and current', () async {
    final f = _Fake({
      'bands.sh json':
          '{"modes":[{"id":"0","label":"Auto"},{"id":"3","label":"4G+5G"}],"currentmode":"3"}',
    });
    final r = (await _make(f).netModes())!;
    expect(r.$1.map((m) => m.label), ['Auto', '4G+5G']);
    expect(r.$2, '3');
    await _make(f).setNetMode('2');
    expect(f.calls.last, 'bands.sh setmode 2');
  });

  test('speed reads 0/1 and null otherwise', () async {
    final f = _Fake({
      'bands.sh getcaenabled': 'Unsupported',
      'bands.sh get256qam': '1',
      'bands.sh getulca': '0',
    });
    final c = _make(f);
    expect(await c.speed(SpeedOption.ca), isNull);
    expect(await c.speed(SpeedOption.qam256), true);
    expect(await c.speed(SpeedOption.ulca), false);
    final bad = _make(_Fake({}, fail: {'bands.sh getulca'}));
    expect(await bad.speed(SpeedOption.ulca), isNull);
    await c.setSpeed(SpeedOption.qam256, true);
    expect(f.calls.last, 'bands.sh set256qam 1');
  });

  test('sims needs two slots', () async {
    final f = _Fake({
      'simslot.sh':
          '{"slots":[{"id":"1","label":"SIM1","present":"1"},{"id":"2","label":"SIM2","present":"0"}],"active":"1"}',
    });
    final s = (await _make(f).sims())!;
    expect(s.slots, [('1', 'SIM1', true), ('2', 'SIM2', false)]);
    expect(s.active, '1');
    final one = _Fake({
      'simslot.sh':
          '{"slots":[{"id":"1","label":"SIM1","present":"1"}],"active":"1"}',
    });
    expect(await _make(one).sims(), isNull);
    await _make(f).setSim('2');
    expect(f.calls.last, 'simslot.sh set 2');
  });

  test('actions and power cycle support', () async {
    final f = _Fake({'reboot_modem.sh hasusbpower': '{"method":"gpio"}'});
    final c = _make(f);
    await c.restart();
    await c.reconnect();
    await c.powerCycle();
    expect(f.calls, [
      'reboot_modem.sh soft',
      'setopt.sh reconnect',
      'reboot_modem.sh usbpower',
    ]);
    expect(await c.canPowerCycle(), true);
    expect(
      await _make(
        _Fake({'reboot_modem.sh hasusbpower': '{"method":""}'}),
      ).canPowerCycle(),
      false,
    );
    expect(
      await _make(_Fake({}, fail: {'reboot_modem.sh haspower'})).canRestart(),
      false,
    );
    expect(await c.canRestart(), true);
  });

  test('apn and roaming read UCI', () async {
    Future<List<Map<String, dynamic>>> sec(String c) async => switch (c) {
      '5gmodem' => [
        {'.type': '5gmodem', 'active_modem': '1-1.2', 'network': 'wan5g'},
        {'.name': 'm_1_1_2', 'apn_mode': 'manual', 'network': 'wwan'},
      ],
      'network' => [
        {'.name': 'wwan', 'apn': 'airtel', 'allow_roaming': '1'},
      ],
      _ => [],
    };
    final c = _make(_Fake({}), sections: sec);
    expect(await c.apn(), (true, 'airtel'));
    expect(await c.roaming(), true);
    Future<List<Map<String, dynamic>>> bad(String c) async =>
        throw const NoobRpcError('x');
    final b = _make(_Fake({}), sections: bad);
    expect(await b.apn(), isNull);
    expect(await b.roaming(), isNull);
  });

  test('setApn writes uci then reconnects', () async {
    final f = _Fake({});
    final sets = <String>[];
    final c = _make(f, sets: sets, sections: _apnSections);
    await c.setApn(manual: true, apn: 'dialog');
    expect(sets, [
      '5gmodem m_1_1_2 {apn_mode: manual}',
      'network wwan {apn: dialog}',
    ]);
    expect(f.calls, ['setopt.sh reconnect']);
  });

  test('setApn without active modem throws', () async {
    final f = _Fake({});
    final c = _make(f);
    await expectLater(c.setApn(manual: false), throwsA(isA<NoobRpcError>()));
    expect(f.calls, isEmpty);
  });

  test('setRoaming runs setopt with the modem path', () async {
    final f = _Fake({});
    await _make(f, sections: _apnSections).setRoaming(true);
    expect(f.calls, ['setopt.sh roaming 1-1.2 1']);
  });

  group('QmodemControls', () {
    final calls = <(String, Map<String, dynamic>)>[];
    Map<String, Map<String, dynamic>> replies = {};

    QmodemControls make() {
      calls.clear();
      return QmodemControls((m, [e = const {}]) async {
        calls.add((m, e));
        final r = replies[m];
        if (r == null) throw StateError('no such method $m');
        return r;
      });
    }

    setUp(() => replies = {});

    test(
      'netModes lists auto plus each type and finds the current one',
      () async {
        replies['get_network_prefer'] = {
          'network_prefer': {'3G': '0', '4G': '1', '5G': '0'},
        };
        final (modes, cur) = (await make().netModes())!;
        expect(modes.map((m) => m.id), ['auto', '3G', '4G', '5G', '4G,5G']);
        expect(cur, '4G');
      },
    );

    test('netModes current is auto when every type is on', () async {
      replies['get_network_prefer'] = {
        'network_prefer': {'3G': '1', '4G': '1', '5G': '1'},
      };
      expect((await make().netModes())!.$2, 'auto');
    });

    test('netModes offers 4G+5G and detects it', () async {
      replies['get_network_prefer'] = {
        'network_prefer': {'3G': '0', '4G': '1', '5G': '1'},
      };
      final (modes, cur) = (await make().netModes())!;
      expect(modes.map((m) => m.id), ['auto', '3G', '4G', '5G', '4G,5G']);
      expect(cur, '4G,5G');
      replies['set_network_prefer'] = {};
      await make().setNetMode('4G,5G');
      expect(calls.single.$2, {
        'params': ['4G', '5G'],
      });
    });

    test('netModes skips 4G+5G when it equals auto', () async {
      replies['get_network_prefer'] = {
        'network_prefer': {'4G': '1', '5G': '0'},
      };
      final (modes, cur) = (await make().netModes())!;
      expect(modes.map((m) => m.id), ['auto', '4G', '5G']);
      expect(cur, '4G');
    });

    test('netModes is null with fewer than two types', () async {
      replies['get_network_prefer'] = {
        'network_prefer': {'4G': '1'},
      };
      expect(await make().netModes(), isNull);
    });

    test('netModes is null when the method is missing or empty', () async {
      expect(await make().netModes(), isNull);
      replies['get_network_prefer'] = {};
      expect(await make().netModes(), isNull);
    });

    test('setNetMode sends the chosen types as the params list', () async {
      replies['set_network_prefer'] = {};
      await make().setNetMode('5G');
      expect(calls.single.$1, 'set_network_prefer');
      expect(calls.single.$2, {
        'params': ['5G'],
      });
    });

    test('setNetMode auto sends every type the modem reports', () async {
      replies['get_network_prefer'] = {
        'network_prefer': {'4G': '1', '5G': '0'},
      };
      replies['set_network_prefer'] = {};
      await make().setNetMode('auto');
      expect(calls.last.$2, {
        'params': ['4G', '5G'],
      });
    });

    test('sims reads capabilities and the active slot', () async {
      replies['get_sim_switch_capabilities'] = {
        'supportSwitch': '1',
        'simSlots': ['0', '1'],
      };
      replies['get_sim_slot'] = {'sim_slot': '1'};
      final s = (await make().sims())!;
      expect(s.active, '1');
      expect(s.slots.map((e) => e.$1), ['0', '1']);
      expect(s.slots.map((e) => e.$2), ['SIM 1', 'SIM 2']);
      expect(s.slots.every((e) => e.$3), isTrue);
    });

    test('sims is null when switching is unsupported or fails', () async {
      replies['get_sim_switch_capabilities'] = {'supportSwitch': '0'};
      replies['get_sim_slot'] = {'sim_slot': '1'};
      expect(await make().sims(), isNull);
      replies['get_sim_switch_capabilities'] = {'supportSwitch': '1'};
      expect(await make().sims(), isNull);
      replies['get_sim_switch_capabilities'] = {
        'supportSwitch': '1',
        'simSlots': ['0', '1'],
      };
      replies['get_sim_slot'] = {'sim_slot': '7'};
      expect(await make().sims(), isNull);
      replies.remove('get_sim_switch_capabilities');
      expect(await make().sims(), isNull);
    });

    test('setSim sends the slot', () async {
      replies['set_sim_slot'] = {'success': true};
      await make().setSim('2');
      expect(calls.single.$1, 'set_sim_slot');
      expect(calls.single.$2['slot'], '2');
      expect(calls.single.$2['params'], '2');
    });

    test('restart and its capability', () async {
      replies['do_reboot'] = {};
      await make().restart();
      expect(calls.single.$2, {
        'params': {'method': 'soft'},
      });
      replies['get_reboot_caps'] = {
        'reboot_caps': {'soft_reboot_caps': 1, 'hard_reboot_caps': 0},
      };
      expect(await make().canRestart(), isTrue);
      replies['get_reboot_caps'] = {
        'reboot_caps': {'soft_reboot_caps': '0'},
      };
      expect(await make().canRestart(), isFalse);
      replies.remove('get_reboot_caps');
      expect(await make().canRestart(), isFalse);
    });

    test('unsupported controls stay hidden', () async {
      final c = make();
      expect(await c.speed(SpeedOption.ca), isNull);
      expect(await c.apn(), isNull);
      expect(await c.roaming(), isNull);
      expect(await c.canReconnect(), isFalse);
      expect(await c.canPowerCycle(), isFalse);
    });
  });
}
