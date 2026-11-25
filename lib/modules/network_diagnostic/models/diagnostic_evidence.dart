// SPDX-License-Identifier: GPL-3.0-or-later

class DiagnosticEvidence {
  final List<String> facts;

  final Map<String, dynamic> metrics;

  final String? technicalOutput;

  final Map<String, DateTime> timestamps;

  const DiagnosticEvidence({
    this.facts = const [],
    this.metrics = const {},
    this.technicalOutput,
    this.timestamps = const {},
  });

  DiagnosticEvidence copyWith({
    List<String>? facts,
    Map<String, dynamic>? metrics,
    String? technicalOutput,
    Map<String, DateTime>? timestamps,
  }) {
    return DiagnosticEvidence(
      facts: facts ?? this.facts,
      metrics: metrics ?? this.metrics,
      technicalOutput: technicalOutput ?? this.technicalOutput,
      timestamps: timestamps ?? this.timestamps,
    );
  }

  Map<String, dynamic> toJson() => {
    'facts': facts,
    'metrics': metrics,
    if (technicalOutput != null) 'technicalOutput': technicalOutput,
    'timestamps': timestamps.map((k, v) => MapEntry(k, v.toIso8601String())),
  };
}
