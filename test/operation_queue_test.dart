// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';

void main() {
  group('RouterScopedOperationQueue', () {
    late RouterScopedOperationQueue queue;

    setUp(() {
      queue = RouterScopedOperationQueue.instance;
    });

    test(
      'Same domain operations on same router execute sequentially',
      () async {
        const routerId = 'router-1';
        const domain = 'network';

        final executionOrder = <int>[];
        final completer1 = Completer<void>();

        final future1 = queue.runLocked(
          routerId: routerId,
          domain: domain,
          action: () async {
            executionOrder.add(1);
            await completer1.future;
            executionOrder.add(2);
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        final future2 = queue.runLocked(
          routerId: routerId,
          domain: domain,
          action: () async {
            executionOrder.add(3);
          },
        );

        await Future.delayed(const Duration(milliseconds: 20));
        expect(executionOrder, equals([1]));

        completer1.complete();
        await Future.wait([future1, future2]);

        expect(executionOrder, equals([1, 2, 3]));
      },
    );

    test('Different domains on same router execute concurrently', () async {
      const routerId = 'router-1';

      final running = <String>{};
      final completerNetwork = Completer<void>();
      final completerFirewall = Completer<void>();

      final futureNet = queue.runLocked(
        routerId: routerId,
        domain: 'network',
        action: () async {
          running.add('network');
          await completerNetwork.future;
          running.remove('network');
        },
      );

      final futureFw = queue.runLocked(
        routerId: routerId,
        domain: 'firewall',
        action: () async {
          running.add('firewall');
          await completerFirewall.future;
          running.remove('firewall');
        },
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(running, containsAll(['network', 'firewall']));

      completerNetwork.complete();
      completerFirewall.complete();
      await Future.wait([futureNet, futureFw]);
      expect(running, isEmpty);
    });

    test('Same domain on different routers execute concurrently', () async {
      final running = <String>{};
      final completerA = Completer<void>();
      final completerB = Completer<void>();

      final futureA = queue.runLocked(
        routerId: 'router-A',
        domain: 'network',
        action: () async {
          running.add('router-A');
          await completerA.future;
          running.remove('router-A');
        },
      );

      final futureB = queue.runLocked(
        routerId: 'router-B',
        domain: 'network',
        action: () async {
          running.add('router-B');
          await completerB.future;
          running.remove('router-B');
        },
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(running, containsAll(['router-A', 'router-B']));

      completerA.complete();
      completerB.complete();
      await Future.wait([futureA, futureB]);
      expect(running, isEmpty);
    });

    test(
      'Exclusive operation (*) waits for active domains to finish',
      () async {
        const routerId = 'router-exclusive-test';
        final executionOrder = <String>[];

        final netCompleter = Completer<void>();
        final fwCompleter = Completer<void>();

        final futureNet = queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async {
            executionOrder.add('net_start');
            await netCompleter.future;
            executionOrder.add('net_end');
          },
        );

        final futureFw = queue.runLocked(
          routerId: routerId,
          domain: 'firewall',
          action: () async {
            executionOrder.add('fw_start');
            await fwCompleter.future;
            executionOrder.add('fw_end');
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        final futureExclusive = queue.runLocked(
          routerId: routerId,
          domain: '*',
          action: () async {
            executionOrder.add('exclusive');
          },
        );

        await Future.delayed(const Duration(milliseconds: 20));
        expect(executionOrder, isNot(contains('exclusive')));

        netCompleter.complete();
        await Future.delayed(const Duration(milliseconds: 10));
        expect(executionOrder, isNot(contains('exclusive')));

        fwCompleter.complete();
        await Future.wait([futureNet, futureFw, futureExclusive]);

        expect(executionOrder, containsAllInOrder(['net_end', 'exclusive']));
        expect(executionOrder, containsAllInOrder(['fw_end', 'exclusive']));
      },
    );

    test(
      'Exclusive waiting prevents new normal operations from starving it',
      () async {
        const routerId = 'router-starvation-test';
        final log = <String>[];

        final net1Completer = Completer<void>();

        final futureNet1 = queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async {
            log.add('net1_start');
            await net1Completer.future;
            log.add('net1_end');
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        final futureExclusive = queue.runLocked(
          routerId: routerId,
          domain: '*',
          action: () async {
            log.add('exclusive_run');
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        final futureNet2 = queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async {
            log.add('net2_run');
          },
        );

        await Future.delayed(const Duration(milliseconds: 20));
        expect(log, equals(['net1_start']));

        net1Completer.complete();
        await Future.wait([futureNet1, futureExclusive, futureNet2]);

        expect(
          log,
          equals(['net1_start', 'net1_end', 'exclusive_run', 'net2_run']),
        );
      },
    );

    test(
      'Active exclusive operation blocks subsequent normal operations',
      () async {
        const routerId = 'router-exclusive-active-test';
        final log = <String>[];
        final exclusiveCompleter = Completer<void>();

        final futureExclusive = queue.runLocked(
          routerId: routerId,
          domain: '*',
          action: () async {
            log.add('exclusive_start');
            await exclusiveCompleter.future;
            log.add('exclusive_end');
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        final futureNet = queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async {
            log.add('net_run');
          },
        );

        final futureFw = queue.runLocked(
          routerId: routerId,
          domain: 'firewall',
          action: () async {
            log.add('fw_run');
          },
        );

        await Future.delayed(const Duration(milliseconds: 20));
        expect(log, equals(['exclusive_start']));

        exclusiveCompleter.complete();
        await Future.wait([futureExclusive, futureNet, futureFw]);

        expect(log, containsAllInOrder(['exclusive_end', 'net_run']));
        expect(log, containsAllInOrder(['exclusive_end', 'fw_run']));
      },
    );

    test('Multiple exclusive operations execute sequentially', () async {
      const routerId = 'router-multi-exclusive';
      final log = <String>[];
      final excl1Completer = Completer<void>();

      final future1 = queue.runLocked(
        routerId: routerId,
        domain: '*',
        action: () async {
          log.add('excl1_start');
          await excl1Completer.future;
          log.add('excl1_end');
        },
      );

      await Future.delayed(const Duration(milliseconds: 10));

      final future2 = queue.runLocked(
        routerId: routerId,
        domain: '*',
        action: () async {
          log.add('excl2_run');
        },
      );

      await Future.delayed(const Duration(milliseconds: 20));
      expect(log, equals(['excl1_start']));

      excl1Completer.complete();
      await Future.wait([future1, future2]);

      expect(log, equals(['excl1_start', 'excl1_end', 'excl2_run']));
    });

    test(
      'Action throwing an exception immediately releases the lock',
      () async {
        const routerId = 'router-error-test';

        expect(
          () => queue.runLocked(
            routerId: routerId,
            domain: 'network',
            action: () async {
              throw const FormatException('Simulated network error');
            },
          ),
          throwsA(isA<FormatException>()),
        );

        await Future.delayed(const Duration(milliseconds: 20));

        final result = await queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async => 'recovered',
        );

        expect(result, equals('recovered'));
      },
    );

    test(
      'Timeout while waiting to acquire lock releases and throws TimeoutException',
      () async {
        const routerId = 'router-timeout-test';
        final blockerCompleter = Completer<void>();

        final blockerFuture = queue.runLocked(
          routerId: routerId,
          domain: 'firewall',
          action: () async {
            await blockerCompleter.future;
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        expect(
          () => queue.runLocked(
            routerId: routerId,
            domain: 'firewall',
            action: () async => 'never_runs',
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );

        await Future.delayed(const Duration(milliseconds: 70));

        blockerCompleter.complete();
        await blockerFuture;

        final cleanResult = await queue.runLocked(
          routerId: routerId,
          domain: 'firewall',
          action: () async => 'clean',
          timeout: const Duration(milliseconds: 100),
        );

        expect(cleanResult, equals('clean'));
      },
    );

    test(
      'isBusy accurately reports domain and exclusive states for polling',
      () async {
        const routerId = 'router-busy-test';
        final netCompleter = Completer<void>();

        expect(queue.isBusy(routerId, 'network'), isFalse);
        expect(queue.isBusy(routerId, 'firewall'), isFalse);
        expect(queue.isBusy(routerId, '*'), isFalse);

        final futureNet = queue.runLocked(
          routerId: routerId,
          domain: 'network',
          action: () async {
            await netCompleter.future;
          },
        );

        await Future.delayed(const Duration(milliseconds: 10));

        expect(queue.isBusy(routerId, 'network'), isTrue);
        expect(queue.isBusy(routerId, 'firewall'), isFalse);
        expect(queue.isBusy(routerId, '*'), isTrue);

        netCompleter.complete();
        await futureNet;

        expect(queue.isBusy(routerId, 'network'), isFalse);
        expect(queue.isBusy(routerId, '*'), isFalse);
      },
    );

    test(
      'Reentrant same-domain calls within same async zone execute without deadlocking',
      () async {
        const routerId = 'router-reentrant-test';

        final result = await queue.runLocked(
          routerId: routerId,
          domain: 'uci',
          action: () async {
            final innerResult = await queue.runLocked(
              routerId: routerId,
              domain: 'uci',
              action: () async {
                return 'inner-done';
              },
            );
            return 'outer-$innerResult';
          },
        );

        expect(result, equals('outer-inner-done'));
        expect(queue.isBusy(routerId, 'uci'), isFalse);
      },
    );

    test(
      'Reentrant calls from exclusive lock to domain lock execute without deadlocking',
      () async {
        const routerId = 'router-reentrant-exclusive-test';

        final result = await queue.runLocked(
          routerId: routerId,
          domain: '*',
          action: () async {
            final innerResult = await queue.runLocked(
              routerId: routerId,
              domain: 'uci',
              action: () async {
                return 'nested-uci';
              },
            );
            return 'exclusive-$innerResult';
          },
        );

        expect(result, equals('exclusive-nested-uci'));
        expect(queue.isBusy(routerId, '*'), isFalse);
      },
    );
  });
}
