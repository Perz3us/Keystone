// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_preset.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';

void main() {
  group('SqmPreset Model & Matching', () {
    test('Standard default templates are defined', () {
      expect(SqmPreset.cakeFiber.qdisc, equals('cake'));
      expect(SqmPreset.cakeFiber.script, equals('piece_of_cake.qos'));
      expect(SqmPreset.cakeFiber.overhead, equals(0));
      expect(SqmPreset.cakeFiber.linklayer, equals('none'));

      expect(SqmPreset.vdslPppoe.qdisc, equals('cake'));
      expect(SqmPreset.vdslPppoe.script, equals('piece_of_cake.qos'));
      expect(SqmPreset.vdslPppoe.overhead, equals(44));
      expect(SqmPreset.vdslPppoe.linklayer, equals('ethernet'));

      expect(SqmPreset.layerCake.qdisc, equals('cake'));
      expect(SqmPreset.layerCake.script, equals('layer_cake.qos'));
      expect(SqmPreset.layerCake.qdiscAdvanced, isTrue);

      expect(SqmPreset.docsisCable.overhead, equals(34));
      expect(SqmPreset.docsisCable.linklayer, equals('ethernet'));

      expect(SqmPreset.lowCpu.qdisc, equals('fq_codel'));
      expect(SqmPreset.lowCpu.script, equals('simplest.qos'));

      expect(SqmPreset.adslAtm.linklayer, equals('atm'));
      expect(SqmPreset.adslAtm.overhead, equals(40));
    });

    test('Accurately matches queues against default templates', () {
      const qFiber = SqmQueue(
        name: 'test',
        interface: 'wan',
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'none',
        overhead: 0,
      );
      expect(SqmPreset.match(qFiber)?.id, equals('cake_fiber'));

      const qPppoe = SqmQueue(
        name: 'test',
        interface: 'pppoe-wan',
        qdisc: 'cake',
        script: 'piece_of_cake.qos',
        linklayer: 'ethernet',
        overhead: 44,
      );
      expect(SqmPreset.match(qPppoe)?.id, equals('vdsl_pppoe'));

      const qGaming = SqmQueue(
        name: 'test',
        interface: 'eth1',
        qdisc: 'cake',
        script: 'layer_cake.qos',
      );
      expect(SqmPreset.match(qGaming)?.id, equals('layer_cake'));

      const qLowCpu = SqmQueue(
        name: 'test',
        interface: 'eth0',
        qdisc: 'fq_codel',
        script: 'simplest.qos',
      );
      expect(SqmPreset.match(qLowCpu)?.id, equals('low_cpu'));
    });
  });

  group('Accurate Interface Mapping Across All Router Setups', () {});

  group('Template Handling & Existing Queue Preservation', () {
    test(
      'Identifies OpenWrt anonymous section cfg01b68a as default template',
      () {
        const q = SqmQueue(
          name: 'cfg01b68a',
          enabled: false,
          interface: 'pppoe-wan',
          download: 0,
          upload: 0,
        );

        expect(q.isDefaultTemplate, isTrue);
        expect(q.isConfigured, isFalse);
        expect(
          q.displayName(primaryWanInterface: 'pppoe-wan'),
          equals('Primary WAN Queue (pppoe-wan)'),
        );
      },
    );

    test('Identifies named queue', () {
      const q = SqmQueue(
        name: 'guest_shaper',
        enabled: true,
        interface: 'br-guest',
        download: 10000,
        upload: 2000,
      );

      expect(q.isDefaultTemplate, isFalse);
      expect(q.isConfigured, isTrue);
      expect(q.displayName(), equals('guest_shaper'));
    });
  });
}
