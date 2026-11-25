// SPDX-License-Identifier: GPL-3.0-or-later

import 'diagnostic_confidence.dart';
import 'diagnostic_evidence.dart';
import 'diagnostic_scope.dart';
import 'diagnostic_status.dart';

class DiagnosticTestResult {
  final String id;

  final String title;

  final DiagnosticScope scope;

  final DiagnosticStatus status;

  final DiagnosticConfidence confidence;

  final String explanation;

  final String whyItMatters;

  final String? recommendedStep;

  final DiagnosticEvidence evidence;

  final String? technicalDetails;

  final String? skipOrFailureReason;

  final DateTime startedAt;

  final DateTime? completedAt;

  final Duration? duration;

  const DiagnosticTestResult({
    required this.id,
    required this.title,
    required this.scope,
    required this.status,
    required this.confidence,
    required this.explanation,
    required this.whyItMatters,
    this.recommendedStep,
    this.evidence = const DiagnosticEvidence(),
    this.technicalDetails,
    this.skipOrFailureReason,
    required this.startedAt,
    this.completedAt,
    this.duration,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'scope': scope.name,
    'status': status.name,
    'confidence': confidence.name,
    'explanation': explanation,
    'whyItMatters': whyItMatters,
    if (recommendedStep != null) 'recommendedStep': recommendedStep,
    'evidence': evidence.toJson(),
    if (technicalDetails != null) 'technicalDetails': technicalDetails,
    if (skipOrFailureReason != null) 'skipOrFailureReason': skipOrFailureReason,
    'startedAt': startedAt.toIso8601String(),
    if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
    if (duration != null) 'durationMs': duration!.inMilliseconds,
  };
}
