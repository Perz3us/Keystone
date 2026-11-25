// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';

enum DnsBlockingEngine { adguardHome, dnsmasqNative, none }

enum DomainBlockScope { global, perDevice }

class DomainValidator {
  static final RegExp _ipv4Pattern = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
  static final RegExp _labelValidPattern = RegExp(
    r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$',
  );

  static String? validate(String? input) {
    if (input == null || input.trim().isEmpty) {
      return 'Domain cannot be empty';
    }

    final normalized = normalize(input);
    if (normalized == null || normalized.isEmpty) {
      return 'Invalid domain format';
    }

    if (normalized.length > 253) {
      return 'Domain exceeds maximum length of 253 characters';
    }

    if (_ipv4Pattern.hasMatch(normalized) || normalized.contains(':')) {
      return 'Domain blocking does not accept IP addresses';
    }

    if (!normalized.contains('.')) {
      return 'Domain must contain at least one dot (e.g. example.com)';
    }

    if (normalized.contains('..')) {
      return 'Domain contains consecutive dots';
    }

    final labels = normalized.split('.');
    for (int i = 0; i < labels.length; i++) {
      final label = labels[i];
      if (label.isEmpty) {
        return 'Domain labels cannot be empty';
      }
      if (label.length > 63) {
        return 'Domain label "$label" exceeds maximum length of 63 characters';
      }
      if (label.startsWith('-') || label.endsWith('-')) {
        return 'Domain label cannot start or end with a hyphen';
      }

      if (!_labelValidPattern.hasMatch(label)) {
        return 'Domain contains invalid characters in label "$label"';
      }
    }

    final tld = labels.last;
    if (RegExp(r'^\d+$').hasMatch(tld)) {
      return 'Top-level domain cannot be purely numeric';
    }

    return null;
  }

  static bool isValid(String? input) => validate(input) == null;

  static String? parseBlockedDomainFromAdGuardRule(String rawRule) {
    final trimmed = rawRule.trim();
    if (trimmed.isEmpty || trimmed.startsWith('!') || trimmed.startsWith('#')) {
      return null;
    }
    if (trimmed.startsWith('@@')) return null;
    if (trimmed.startsWith('||')) {
      var rest = trimmed.substring(2);
      final caretIndex = rest.indexOf('^');
      if (caretIndex != -1) {
        rest = rest.substring(0, caretIndex);
      }
      final dollarIndex = rest.indexOf(r'$');
      if (dollarIndex != -1) {
        rest = rest.substring(0, dollarIndex);
      }
      final norm = normalize(rest);
      return (norm != null && isValid(norm)) ? norm : null;
    }
    return null;
  }

  static String? parseBlockedDomainFromAddress(String rawEntry) {
    final trimmed = rawEntry.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;
    if (trimmed.startsWith('/')) {
      final parts = trimmed.substring(1).split('/');
      if (parts.isNotEmpty && parts[0].isNotEmpty) {
        final candidate = parts[0].trim();
        final suffix = parts.length > 1 ? parts[1].trim() : '';
        if (suffix == '#' ||
            suffix == '0.0.0.0' ||
            suffix == '::' ||
            suffix == '127.0.0.1' ||
            suffix.isEmpty) {
          final norm = normalize(candidate);
          return (norm != null && isValid(norm)) ? norm : null;
        }
      }
    }
    return null;
  }

  static String? normalize(String? input) {
    if (input == null) return null;
    String raw = input.trim();
    if (raw.isEmpty) return null;

    final schemeIndex = raw.indexOf('://');
    if (schemeIndex != -1) {
      raw = raw.substring(schemeIndex + 3);
    }

    final atIndex = raw.indexOf('@');
    if (atIndex != -1) {
      raw = raw.substring(atIndex + 1);
    }

    final pathSeparatorIndex = raw.indexOf(RegExp(r'[/?#]'));
    if (pathSeparatorIndex != -1) {
      raw = raw.substring(0, pathSeparatorIndex);
    }

    final colonIndex = raw.indexOf(':');
    if (colonIndex != -1 && !raw.contains(']')) {
      raw = raw.substring(0, colonIndex);
    }

    if (raw.startsWith('*.')) {
      raw = raw.substring(2);
    } else if (raw.startsWith('.')) {
      raw = raw.substring(1);
    }

    while (raw.endsWith('.')) {
      raw = raw.substring(0, raw.length - 1);
    }

    raw = raw.trim().toLowerCase();
    if (raw.isEmpty) return null;

    return toPunycode(raw);
  }

  static String toPunycode(String domain) {
    return domain.split('.').map(_encodePunycodeLabel).join('.');
  }

  static String _encodePunycodeLabel(String label) {
    if (label.isEmpty) return label;
    final runes = label.runes.toList();
    if (!runes.any((r) => r >= 128)) {
      return label;
    }

    const base = 36;
    const tMin = 1;
    const tMax = 26;
    const skew = 38;
    const damp = 700;
    const initialBias = 72;
    const initialN = 128;

    int adapt(int delta, int numPoints, bool firstTime) {
      var d = firstTime ? delta ~/ damp : delta ~/ 2;
      d += d ~/ numPoints;
      var k = 0;
      while (d > ((base - tMin) * tMax) ~/ 2) {
        d ~/= (base - tMin);
        k += base;
      }
      return k + (((base - tMin + 1) * d) ~/ (d + skew));
    }

    int encodeDigit(int d) {
      if (d < 26) return 97 + d;
      return 48 + (d - 26);
    }

    final output = StringBuffer();
    for (final r in runes) {
      if (r < 128) {
        output.writeCharCode(r);
      }
    }

    final basicCount = output.length;
    var h = basicCount;
    if (basicCount > 0) {
      output.write('-');
    }

    var n = initialN;
    var delta = 0;
    var bias = initialBias;

    while (h < runes.length) {
      var m = 0x7FFFFFFF;
      for (final r in runes) {
        if (r >= n && r < m) {
          m = r;
        }
      }

      delta += (m - n) * (h + 1);
      n = m;

      for (final r in runes) {
        if (r < n) {
          delta++;
        } else if (r == n) {
          var q = delta;
          for (var k = base; ; k += base) {
            final t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias);
            if (q < t) break;
            final digit = t + ((q - t) % (base - t));
            output.writeCharCode(encodeDigit(digit));
            q = (q - t) ~/ (base - t);
          }
          output.writeCharCode(encodeDigit(q));
          bias = adapt(delta, h + 1, h == basicCount);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }

    return 'xn--$output';
  }
}

@immutable
class DomainBlockRule {
  final String domain;

  final String? rawPattern;

  final DnsBlockingEngine engine;

  final DomainBlockScope scope;

  final String? targetMac;

  final String? targetIp;

  final bool isEnabled;

  final DateTime? createdAt;

  final String? comment;

  const DomainBlockRule({
    required this.domain,
    this.rawPattern,
    required this.engine,
    this.scope = DomainBlockScope.global,
    this.targetMac,
    this.targetIp,
    this.isEnabled = true,
    this.createdAt,
    this.comment,
  });

  factory DomainBlockRule.global({
    required String domain,
    required DnsBlockingEngine engine,
    String? rawPattern,
    bool isEnabled = true,
    DateTime? createdAt,
    String? comment,
  }) {
    final norm =
        DomainValidator.normalize(domain) ?? domain.trim().toLowerCase();
    return DomainBlockRule(
      domain: norm,
      rawPattern: rawPattern,
      engine: engine,
      scope: DomainBlockScope.global,
      isEnabled: isEnabled,
      createdAt: createdAt ?? DateTime.now(),
      comment: comment,
    );
  }

  String toAdGuardRule() {
    return '||$domain^';
  }

  String toDnsmasqAddress() {
    return '/$domain/#';
  }

  DomainBlockRule copyWith({
    String? domain,
    String? rawPattern,
    DnsBlockingEngine? engine,
    DomainBlockScope? scope,
    String? targetMac,
    String? targetIp,
    bool? isEnabled,
    DateTime? createdAt,
    String? comment,
  }) {
    return DomainBlockRule(
      domain: domain ?? this.domain,
      rawPattern: rawPattern ?? this.rawPattern,
      engine: engine ?? this.engine,
      scope: scope ?? this.scope,
      targetMac: targetMac ?? this.targetMac,
      targetIp: targetIp ?? this.targetIp,
      isEnabled: isEnabled ?? this.isEnabled,
      createdAt: createdAt ?? this.createdAt,
      comment: comment ?? this.comment,
    );
  }

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'rawPattern': rawPattern,
    'engine': engine.name,
    'scope': scope.name,
    'targetMac': targetMac,
    'targetIp': targetIp,
    'isEnabled': isEnabled,
    'createdAt': createdAt?.toIso8601String(),
    'comment': comment,
  };

  factory DomainBlockRule.fromJson(Map<String, dynamic> json) =>
      DomainBlockRule(
        domain: json['domain']?.toString() ?? '',
        rawPattern: json['rawPattern']?.toString(),
        engine: DnsBlockingEngine.values.firstWhere(
          (e) => e.name == json['engine'],
          orElse: () => DnsBlockingEngine.none,
        ),
        scope: DomainBlockScope.values.firstWhere(
          (s) => s.name == json['scope'],
          orElse: () => DomainBlockScope.global,
        ),
        targetMac: json['targetMac']?.toString(),
        targetIp: json['targetIp']?.toString(),
        isEnabled: json['isEnabled'] == true,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())
            : null,
        comment: json['comment']?.toString(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainBlockRule &&
          runtimeType == other.runtimeType &&
          domain == other.domain &&
          engine == other.engine &&
          scope == other.scope &&
          targetMac == other.targetMac;

  @override
  int get hashCode => Object.hash(domain, engine, scope, targetMac);

  @override
  String toString() =>
      'DomainBlockRule(domain: $domain, engine: ${engine.name}, scope: ${scope.name})';
}
