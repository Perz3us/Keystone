import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/wifi/channel_check.dart';
import 'package:yet_another_luci_app/screens/wifi/channel_check_screen.dart';

Map<String, dynamic> net(int ch, [int dbm = -60]) => {
  'ssid': 'n$ch',
  'channel': ch,
  'signal': dbm,
};

final all24 = {for (var c = 1; c <= 13; c++) c};
const all5 = {
  36,
  40,
  44,
  48,
  52,
  56,
  60,
  64,
  100,
  104,
  108,
  112,
  149,
  153,
  157,
  161,
  165,
};

void main() {
  group('loads', () {
    test('2.4 GHz networks spill onto neighbours', () {
      final l = channelLoads([net(1), net(2), net(3)], is5g: false);
      int n(int c) => l.firstWhere((x) => x.channel == c).networks;
      expect(n(1), 3);
      expect(n(6), 0);
      expect(n(4), 2);
    });
    test('5 GHz counts its own channel only', () {
      final l = channelLoads([net(36), net(36), net(40)], is5g: true);
      expect(l.firstWhere((x) => x.channel == 36).networks, 2);
      expect(l.firstWhere((x) => x.channel == 40).networks, 1);
    });
    test('strongest is kept', () {
      final l = channelLoads([net(6, -80), net(6, -40)], is5g: false);
      expect(l.firstWhere((x) => x.channel == 6).strongest, -40);
    });
    test('broken rows are skipped', () {
      expect(
        channelLoads([
          {'channel': 'x'},
          {'ssid': 'a'},
          'nope',
        ], is5g: false).every((l) => l.networks == 0),
        isTrue,
      );
    });
  });

  group('suggestion', () {
    int pick(
      List<Map<String, dynamic>> scan, {
      bool is5g = false,
      int current = 6,
      Set<int>? allowed,
    }) => suggestChannel(
      channelLoads(scan, is5g: is5g),
      is5g: is5g,
      current: current,
      allowed: allowed ?? (is5g ? all5 : all24),
    );

    test('2.4 GHz away from the crowd', () {
      expect(pick([net(1), net(2), net(3), net(6)], current: 1), 11);
    });
    test('2.4 GHz only 1, 6 or 11', () {
      for (var i = 0; i < 20; i++) {
        expect({1, 6, 11}, contains(pick([net(1 + i % 11)])));
      }
    });
    test('5 GHz prefers channels without radar checks', () {
      expect(
        pick(
          [net(36), net(40), net(44), net(48), net(149, -50)],
          is5g: true,
          current: 36,
        ),
        anyOf(153, 157, 161, 165),
      );
    });
    test('5 GHz takes a radar channel when it is much clearer', () {
      final crowd = [
        for (final c in [36, 40, 44, 48, 149, 153, 157, 161, 165]) ...[
          net(c),
          net(c),
        ],
      ];
      expect({
        52,
        56,
        60,
        64,
        100,
        104,
        108,
        112,
      }, contains(pick(crowd, is5g: true, current: 36)));
    });
    test('stays inside what the country allows', () {
      expect(
        pick([net(6)], current: 6, allowed: {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}),
        1,
      );
    });
    test('a tie keeps the current channel', () {
      expect(pick([], current: 11), 11);
    });
    test('a tie away from current takes the lowest', () {
      expect(pick([net(6)], current: 6), 1);
    });
    test('auto counts as no current channel', () {
      expect(pick([], current: 0), 1);
    });
  });

  group('screen', () {
    int? picked;
    Future<void> open(
      WidgetTester t,
      Future<List<Map<String, dynamic>>> Function() scan,
    ) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [KeystoneColors.light]),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async {
                final ch = await Navigator.of(c).push<int>(
                  MaterialPageRoute(
                    builder: (_) => ChannelCheckScreen(
                      scan: scan,
                      is5g: false,
                      current: 1,
                      allowed: all24,
                    ),
                  ),
                );
                picked = ch;
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    testWidgets('suggests and hands the channel back', (t) async {
      await open(t, () async => [net(1), net(1), net(2)]);
      expect(find.textContaining('Channel 6 is the quietest'), findsOneWidget);
      expect(
        find.textContaining('Wi-Fi drops for a few seconds'),
        findsOneWidget,
      );
      await t.tap(find.text('Use channel 6'));
      await t.pumpAndSettle();
      expect(picked, 6);
    });
    testWidgets('already on the best one', (t) async {
      await open(t, () async => [net(6), net(11)]);
      expect(find.text('Channel 1 is already the quietest'), findsOneWidget);
      expect(find.textContaining('Use channel'), findsNothing);
    });
    testWidgets('lists the channels networks are on, and yours', (t) async {
      await open(t, () async => [net(6), net(6), net(11)]);
      expect(find.text('Channel 6'), findsOneWidget);
      expect(find.text('Channel 11'), findsOneWidget);
      expect(find.text('Channel 4'), findsNothing);
      expect(find.text('Channel 1'), findsOneWidget);
      expect(find.text('Yours'), findsOneWidget);
      expect(find.textContaining('No networks'), findsOneWidget);
    });
    testWidgets('radio that cannot scan', (t) async {
      await open(t, () async => throw const ScanUnsupported());
      expect(find.text("This router can't scan on this band"), findsOneWidget);
    });
    testWidgets('other failures', (t) async {
      await open(t, () async => throw Exception('wifi'));
      expect(find.textContaining("Couldn't scan"), findsOneWidget);
    });
  });
}
