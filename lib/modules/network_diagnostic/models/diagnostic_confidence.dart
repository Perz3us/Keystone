// SPDX-License-Identifier: GPL-3.0-or-later

enum DiagnosticConfidence {
  high,

  moderate,

  low,

  inconclusive;

  String get label {
    switch (this) {
      case DiagnosticConfidence.high:
        return 'High Confidence';
      case DiagnosticConfidence.moderate:
        return 'Moderate Confidence';
      case DiagnosticConfidence.low:
        return 'Low Confidence';
      case DiagnosticConfidence.inconclusive:
        return 'Inconclusive Evidence';
    }
  }

  String get description {
    switch (this) {
      case DiagnosticConfidence.high:
        return 'Corroborated by multiple independent observations with no conflicting evidence.';
      case DiagnosticConfidence.moderate:
        return 'Supported by key observations, though secondary factors could contribute.';
      case DiagnosticConfidence.low:
        return 'Plausible hypothesis based on limited diagnostic data.';
      case DiagnosticConfidence.inconclusive:
        return 'Available evidence does not allow a definitive conclusion.';
    }
  }
}
