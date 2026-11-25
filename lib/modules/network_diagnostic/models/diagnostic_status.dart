// SPDX-License-Identifier: GPL-3.0-or-later

enum DiagnosticStatus {
  healthy,
  degraded,
  failureConfirmed,
  suspected,
  inconclusive,
  notTested,
  unsupported,
  notApplicable;

  String get label {
    switch (this) {
      case DiagnosticStatus.healthy:
        return 'Healthy';
      case DiagnosticStatus.degraded:
        return 'Degraded';
      case DiagnosticStatus.failureConfirmed:
        return 'Failure Confirmed';
      case DiagnosticStatus.suspected:
        return 'Suspected Issue';
      case DiagnosticStatus.inconclusive:
        return 'Inconclusive';
      case DiagnosticStatus.notTested:
        return 'Not Tested';
      case DiagnosticStatus.unsupported:
        return 'Unsupported';
      case DiagnosticStatus.notApplicable:
        return 'Not Applicable';
    }
  }

  bool get isProblem =>
      this == DiagnosticStatus.failureConfirmed ||
      this == DiagnosticStatus.degraded ||
      this == DiagnosticStatus.suspected;

  bool get isOperational => this == DiagnosticStatus.healthy;

  bool get isNonFailure =>
      this == DiagnosticStatus.notTested ||
      this == DiagnosticStatus.unsupported ||
      this == DiagnosticStatus.notApplicable ||
      this == DiagnosticStatus.inconclusive;
}
