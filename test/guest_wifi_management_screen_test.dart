// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/guest_wifi_management_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  GuestWifiView view({
    List<GuestNet> networks = const [],
    List<GuestOnline> guests = const [],
    bool canEdit = true,
    void Function(String, bool)? onToggle,
    void Function(String, bool)? onPause,
    VoidCallback? onSetUp,
  }) => GuestWifiView(
    networks: networks,
    guests: guests,
    canEdit: canEdit,
    onToggle: onToggle ?? (_, _) {},
    onEdit: (_) {},
    onShare: () {},
    onSetUp: onSetUp ?? () {},
    onGuest: (_) {},
    onPause: onPause ?? (_, _) {},
  );

  const off = GuestNet(
    id: 'g1',
    name: 'MyHome_Guest',
    line: '5 GHz · no password · no guests',
    enabled: false,
  );

  testWidgets('no guest network offers to set one up', (tester) async {
    var setUp = 0;
    await tester.pumpWidget(_wrap(view(onSetUp: () => setUp++)));
    await tester.tap(find.text('Set up guest Wi-Fi'));
    expect(setUp, 1);
  });

  testWidgets('a read-only sign-in is told why it cannot set up', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(view(canEdit: false)));
    expect(find.text('Set up guest Wi-Fi'), findsNothing);
    expect(find.textContaining('Sign in as root'), findsOneWidget);
  });

  testWidgets('the switch turns a guest network on; share waits for it', (
    tester,
  ) async {
    (String, bool)? toggled;
    await tester.pumpWidget(
      _wrap(view(networks: [off], onToggle: (id, on) => toggled = (id, on))),
    );
    expect(find.text('Turn a guest network on to share it.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((w) => w is FilledButton),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(Switch));
    expect(toggled, ('g1', true));
    expect(find.text('Nobody is on guest Wi-Fi right now.'), findsOneWidget);
  });

  testWidgets('a guest online can be paused and resumed', (tester) async {
    (String, bool)? paused;
    await tester.pumpWidget(
      _wrap(
        view(
          networks: [off],
          guests: const [
            GuestOnline(
              mac: 'AA',
              name: 'Visitor',
              line: 'good',
              paused: false,
            ),
            GuestOnline(mac: 'BB', name: 'Kid', line: 'good', paused: true),
          ],
          onPause: (mac, p) => paused = (mac, p),
        ),
      ),
    );
    expect(find.text('Guests online · 2'), findsOneWidget);
    expect(find.text('Paused · good'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    expect(paused, ('AA', true));
    await tester.tap(find.text('Resume'));
    expect(paused, ('BB', false));
  });
}
