// SPDX-License-Identifier: GPL-3.0-or-later

import 'diagnostic_capabilities.dart';
import 'diagnostic_status.dart';
import 'diagnostic_test_result.dart';
import 'root_cause_finding.dart';

class NetworkDiagnosticReport {
  final String sessionId;

  final DateTime timestamp;

  final String routerScope;

  final DiagnosticStatus overallStatus;

  final String overallSummary;

  final List<DiagnosticTestResult> testResults;

  final List<RootCauseFinding> findings;

  final DiagnosticCapabilities capabilities;

  final List<String> unverifiedAreas;

  const NetworkDiagnosticReport({
    required this.sessionId,
    required this.timestamp,
    required this.routerScope,
    required this.overallStatus,
    required this.overallSummary,
    required this.testResults,
    required this.findings,
    required this.capabilities,
    required this.unverifiedAreas,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'timestamp': timestamp.toIso8601String(),
    'routerScope': routerScope,
    'overallStatus': overallStatus.name,
    'overallSummary': overallSummary,
    'testResults': testResults.map((e) => e.toJson()).toList(),
    'findings': findings.map((e) => e.toJson()).toList(),
    'capabilities': capabilities.toJson(),
    'unverifiedAreas': unverifiedAreas,
  };
}
