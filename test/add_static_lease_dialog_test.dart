// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';

void main() {
  testWidgets(
    'AddStaticLeaseDialog initializes without error when parameters are null',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const AddStaticLeaseDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Give a fixed address'), findsOneWidget);
      expect(find.text('Device (MAC address)'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      expect(find.text('MAC address cannot be empty'), findsNothing);
      expect(find.text('Hostname cannot be empty'), findsNothing);
      expect(find.text('IPv4 address cannot be empty'), findsNothing);
      expect(find.textContaining('You copied'), findsNothing);
    },
  );

  testWidgets(
    'AddStaticLeaseDialog renders Remove Lease button and confirmation dialog in edit mode',
    (WidgetTester tester) async {
      const mapping = DhcpStaticMapping(
        macAddress: '11:22:33:44:55:66',
        ipAddress: '192.168.1.150',
        hostname: 'Printer-Device',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) =>
                        const AddStaticLeaseDialog(existingMapping: mapping),
                  );
                },
                child: const Text('Open Edit Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Fixed address'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Remove the fixed address'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Remove the fixed address'), findsOneWidget);

      await tester.tap(find.text('Remove the fixed address'));
      await tester.pumpAndSettle();

      expect(find.text('Remove the fixed address?'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.textContaining('Printer-Device'), findsWidgets);
    },
  );
}
