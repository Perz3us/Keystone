import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/ping_result.dart';
import 'package:yet_another_luci_app/modules/diagnostics/screens/diagnostics_screen.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_capabilities.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_confidence.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_scope.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/diagnostic_status.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/network_diagnostic_report.dart';
import 'package:yet_another_luci_app/modules/network_diagnostic/models/root_cause_finding.dart';

Widget _app(Widget w) => MaterialApp(
  theme: KeystoneTheme.buildLightTheme(),
  home: Scaffold(body: ListView(children: [w])),
);

void main() {
  testWidgets('before the check: what it does, and the button', (t) async {
    var ran = 0;
    await t.pumpWidget(_app(CheckView(running: false, onRun: () => ran++)));
    expect(find.textContaining('changes nothing'), findsOneWidget);
    await t.tap(find.text('Check everything'));
    expect(ran, 1);
  });

  testWidgets('while checking: progress and the step', (t) async {
    await t.pumpWidget(
      _app(const CheckView(running: true, progress: 0.4, step: 'Names')),
    );
    expect(find.text('Names'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('after: the summary and each problem with its steps', (t) async {
    await t.pumpWidget(
      _app(
        CheckView(
          running: false,
          report: NetworkDiagnosticReport(
            sessionId: 's',
            timestamp: DateTime(2026),
            routerScope: '192.168.1.1',
            overallStatus: DiagnosticStatus.failureConfirmed,
            overallSummary: 'Names are not working.',
            testResults: const [],
            findings: const [
              RootCauseFinding(
                id: 'dns',
                title: 'The DNS server is not answering',
                description: 'Websites by name fail; addresses work.',
                status: DiagnosticStatus.failureConfirmed,
                confidence: DiagnosticConfidence.high,
                primaryScope: DiagnosticScope.ipv4,
                recommendedSteps: ['Restart the address service'],
              ),
              RootCauseFinding(
                id: 'ok',
                title: 'The cable is fine',
                description: '',
                status: DiagnosticStatus.healthy,
                confidence: DiagnosticConfidence.high,
                primaryScope: DiagnosticScope.ipv4,
              ),
            ],
            capabilities: const DiagnosticCapabilities(),
            unverifiedAreas: const [],
          ),
        ),
      ),
    );
    expect(find.text('Names are not working.'), findsOneWidget);
    expect(find.text('The DNS server is not answering'), findsOneWidget);
    expect(find.text('1. Restart the address service'), findsOneWidget);
    expect(find.text('The cable is fine'), findsNothing);
    expect(find.text('Check again'), findsOneWidget);
  });

  test('ping in plain words', () {
    PingResult p(int got, {String? err}) => PingResult(
      target: '1.1.1.1',
      isSuccess: got > 0,
      packetsTransmitted: 5,
      packetsReceived: got,
      packetLossPercent: (5 - got) * 20,
      avgRttMs: got > 0 ? 12.4 : null,
      maxRttMs: got > 0 ? 30 : null,
      replies: const [],
      rawOutput: '',
      errorMessage: err,
      timestamp: DateTime(2026),
    );
    expect(pingLine(p(5)), '5 of 5 answered · 12 ms on average, slowest 30 ms');
    expect(pingLine(p(0)), "1.1.1.1 didn't answer.");
  });

  test('checks in plain words; problems keep what the engine saw', () {
    expect(plainCheck('dns_resolution', DiagnosticStatus.healthy, 'x'), (
      'Website names',
      'Names turn into addresses.',
    ));
    expect(
      plainCheck(
        'dns_resolution',
        DiagnosticStatus.failureConfirmed,
        'NXDOMAIN',
      ),
      ('Website names', 'NXDOMAIN'),
    );
    expect(
      plainCheck('new_check', DiagnosticStatus.healthy, 'ok').$1,
      'new_check',
    );
  });
}
