// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';

void main() {
  group('Firewall Custom Security Rules', () {
    test('FirewallCustomRule parsing with sectionKey and copyWith work', () {
      final json = {
        '.name': 'rule_icmp',
        'name': 'Allow-Ping',
        'src': 'wan',
        'dest': 'lan',
        'target': 'ACCEPT',
        'enabled': '1',
      };

      final rule = FirewallCustomRule.fromJson('rule_icmp', json);
      expect(rule.sectionKey, equals('rule_icmp'));
      expect(rule.name, equals('Allow-Ping'));
      expect(rule.enabled, isTrue);
      expect(rule.target, equals('ACCEPT'));

      final disabledRule = rule.copyWith(enabled: false);
      expect(disabledRule.sectionKey, equals('rule_icmp'));
      expect(disabledRule.enabled, isFalse);
      expect(disabledRule.name, equals('Allow-Ping'));
    });

    test(
      'FirewallCustomRule parses various enabled formats (int, string, bool)',
      () {
        expect(
          FirewallCustomRule.fromJson('r1', {'enabled': 0}).enabled,
          isFalse,
        );
        expect(
          FirewallCustomRule.fromJson('r2', {'enabled': '0'}).enabled,
          isFalse,
        );
        expect(
          FirewallCustomRule.fromJson('r3', {'enabled': false}).enabled,
          isFalse,
        );
        expect(
          FirewallCustomRule.fromJson('r4', {'enabled': 1}).enabled,
          isTrue,
        );
        expect(
          FirewallCustomRule.fromJson('r5', {'enabled': '1'}).enabled,
          isTrue,
        );
        expect(
          FirewallCustomRule.fromJson('r6', {'enabled': true}).enabled,
          isTrue,
        );
        expect(FirewallCustomRule.fromJson('r7', {}).enabled, isTrue);
      },
    );

    test('Staging logic tracks modified firewall custom rules', () {
      final rules = [
        const FirewallCustomRule(
          sectionKey: 'r1',
          name: 'Allow-HTTP',
          srcZone: 'wan',
          destZone: 'lan',
          target: 'ACCEPT',
          enabled: true,
        ),
        const FirewallCustomRule(
          sectionKey: 'r2',
          name: 'Block-Telnet',
          srcZone: 'wan',
          destZone: 'lan',
          target: 'DROP',
          enabled: false,
        ),
      ];

      final stagedMap = <String, bool>{};

      final r1 = rules.firstWhere((r) => r.sectionKey == 'r1');
      stagedMap[r1.sectionKey] = false;
      expect(stagedMap.containsKey('r1'), isTrue);
      expect(stagedMap['r1'], isFalse);

      if (true == r1.enabled) {
        stagedMap.remove(r1.sectionKey);
      }
      expect(stagedMap.containsKey('r1'), isFalse);
      expect(stagedMap.isEmpty, isTrue);
    });
  });

  group('Firewall Flow Offloading', () {
    test(
      'FirewallDefaultPolicy parses flow offloading fields and sectionKey',
      () {
        final json = {
          '.type': 'defaults',
          '.name': 'cfg01e63d',
          'input': 'ACCEPT',
          'output': 'ACCEPT',
          'forward': 'REJECT',
          'syn_flood': '1',
          'flow_offloading': '1',
          'flow_offloading_hw': '0',
        };

        final policy = FirewallDefaultPolicy.fromJson(
          json,
          sectionKey: 'cfg01e63d',
        );
        expect(policy.sectionKey, equals('cfg01e63d'));
        expect(policy.flowOffloading, isTrue);
        expect(policy.flowOffloadingHw, isFalse);
        expect(policy.hasAnyFlowOffloading, isTrue);
        expect(policy.synFlood, isTrue);
      },
    );

    test('FirewallDefaultPolicy copyWith updates properties accurately', () {
      const initial = FirewallDefaultPolicy(
        sectionKey: 'cfg01e63d',
        input: 'ACCEPT',
        output: 'ACCEPT',
        forward: 'REJECT',
        synFlood: true,
        flowOffloading: true,
        flowOffloadingHw: false,
      );

      final updated = initial.copyWith(
        flowOffloading: false,
        flowOffloadingHw: false,
      );

      expect(updated.sectionKey, equals('cfg01e63d'));
      expect(updated.flowOffloading, isFalse);
      expect(updated.flowOffloadingHw, isFalse);
      expect(updated.hasAnyFlowOffloading, isFalse);
    });

    test('Fw4FirewallParser extracts defaults section key', () {
      final uci = {
        'values': {
          'cfg01e63d': {
            '.type': 'defaults',
            '.name': 'cfg01e63d',
            'input': 'REJECT',
            'output': 'ACCEPT',
            'forward': 'REJECT',
            'syn_flood': '1',
            'flow_offloading': '1',
          },
          'lan': {
            '.type': 'zone',
            'name': 'lan',
            'input': 'ACCEPT',
            'output': 'ACCEPT',
            'forward': 'ACCEPT',
            'network': ['lan'],
          },
        },
      };

      final overview = Fw4FirewallParser.parse(uci);
      expect(overview.isAvailable, isTrue);
      expect(overview.defaultPolicy.sectionKey, equals('cfg01e63d'));
      expect(overview.defaultPolicy.flowOffloading, isTrue);
      expect(overview.defaultPolicy.flowOffloadingHw, isFalse);
    });

    test(
      'Flow offloading staging logic disarms hardware when software is turned off',
      () {
        const policy = FirewallDefaultPolicy(
          sectionKey: 'cfg01e63d',
          input: 'ACCEPT',
          output: 'ACCEPT',
          forward: 'REJECT',
          synFlood: true,
          flowOffloading: true,
          flowOffloadingHw: true,
        );

        bool? stagedSoftware;
        bool? stagedHardware;

        stagedSoftware = false;
        final effectiveSoftware = stagedSoftware;
        if (!effectiveSoftware) {
          if (policy.flowOffloadingHw) {
            stagedHardware = false;
          } else {
            stagedHardware = null;
          }
        }

        expect(stagedSoftware, isFalse);
        expect(stagedHardware, isFalse);
      },
    );
  });
}
