// SPDX-License-Identifier: GPL-3.0-or-later

enum LogLevel {
  emergency,
  alert,
  critical,
  error,
  warning,
  notice,
  info,
  debug,
  unknown,
}

class LogEntry {
  final int index;
  final String raw;
  final String? timestamp;
  final String? facility;
  final String? tag;
  final LogLevel level;
  final String message;

  const LogEntry({
    required this.index,
    required this.raw,
    this.timestamp,
    this.facility,
    this.tag,
    required this.level,
    required this.message,
  });

  static LogLevel _parseSeverity(String? severity) {
    if (severity == null) return LogLevel.unknown;
    final s = severity.trim().toLowerCase();
    switch (s) {
      case 'emerg':
      case 'emergency':
        return LogLevel.emergency;
      case 'alert':
        return LogLevel.alert;
      case 'crit':
      case 'critical':
        return LogLevel.critical;
      case 'err':
      case 'error':
        return LogLevel.error;
      case 'warn':
      case 'warning':
        return LogLevel.warning;
      case 'notice':
        return LogLevel.notice;
      case 'info':
      case 'informational':
        return LogLevel.info;
      case 'debug':
        return LogLevel.debug;
      default:
        return LogLevel.unknown;
    }
  }

  factory LogEntry.fromSyslogLine(int index, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return LogEntry(
        index: index,
        raw: line,
        level: LogLevel.unknown,
        message: '',
      );
    }

    final format1 = RegExp(
      r'^(\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\s+\d{4})\s+(\w+)\.(\w+)\s+(\S+?):\s*(.*)$',
    ).firstMatch(trimmed);

    if (format1 != null) {
      return LogEntry(
        index: index,
        raw: line,
        timestamp: format1.group(1),
        facility: format1.group(2),
        level: _parseSeverity(format1.group(3)),
        tag: format1.group(4),
        message: format1.group(5) ?? '',
      );
    }

    final format2 = RegExp(
      r'^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+\S+\s+(\w+)\.(\w+)\s+(\S+?):\s*(.*)$',
    ).firstMatch(trimmed);

    if (format2 != null) {
      return LogEntry(
        index: index,
        raw: line,
        timestamp: format2.group(1),
        facility: format2.group(2),
        level: _parseSeverity(format2.group(3)),
        tag: format2.group(4),
        message: format2.group(5) ?? '',
      );
    }

    final format3 = RegExp(
      r'^(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+\S+\s+(\w+):\s*(.*)$',
    ).firstMatch(trimmed);

    if (format3 != null) {
      return LogEntry(
        index: index,
        raw: line,
        timestamp: format3.group(1),
        facility: format3.group(2),
        level: LogLevel.unknown,
        tag: null,
        message: format3.group(3) ?? '',
      );
    }

    return LogEntry(
      index: index,
      raw: line,
      level: LogLevel.unknown,
      message: trimmed,
    );
  }

  factory LogEntry.fromDmesgLine(int index, String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return LogEntry(
        index: index,
        raw: line,
        level: LogLevel.unknown,
        message: '',
      );
    }

    final priorityMatch = RegExp(r'^\s*<(\d+)>').firstMatch(trimmed);
    LogLevel level = LogLevel.unknown;
    String remainder = trimmed;

    if (priorityMatch != null) {
      final n = int.tryParse(priorityMatch.group(1)!);
      if (n != null && n >= 0 && n <= 7) {
        level = LogLevel.values[n];
      }
      remainder = trimmed.substring(priorityMatch.end).trimLeft();
    }

    final timestampMatch = RegExp(
      r'^\[\s*([\d\.]+)\]\s*(.*)$',
    ).firstMatch(remainder);
    String? timestamp;
    String message = remainder;

    if (timestampMatch != null) {
      timestamp = timestampMatch.group(1);
      message = timestampMatch.group(2) ?? '';
    }

    return LogEntry(
      index: index,
      raw: line,
      timestamp: timestamp,
      facility: null,
      tag: null,
      level: level,
      message: message,
    );
  }
}
