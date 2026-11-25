// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

@immutable
class NetworkAccessPolicy {
  final String targetMac;
  final bool internetAccess;
  final bool ipv4Access;
  final bool ipv6Access;
  final DateTime? scheduleExpiry;

  const NetworkAccessPolicy({
    required this.targetMac,
    this.internetAccess = true,
    this.ipv4Access = true,
    this.ipv6Access = true,
    this.scheduleExpiry,
  });

  factory NetworkAccessPolicy.unrestricted(String targetMac) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(targetMac),
      internetAccess: true,
      ipv4Access: true,
      ipv6Access: true,
    );
  }

  factory NetworkAccessPolicy.blocked(
    String targetMac, {
    DateTime? scheduleExpiry,
  }) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(targetMac),
      internetAccess: false,
      ipv4Access: false,
      ipv6Access: false,
      scheduleExpiry: scheduleExpiry,
    );
  }

  bool get isExpired {
    if (scheduleExpiry == null) return false;
    return DateTime.now().isAfter(scheduleExpiry!);
  }

  bool get isIndefinite => scheduleExpiry == null;

  bool get effectiveInternetAccess {
    if (!internetAccess && isExpired) return true;
    return internetAccess;
  }

  bool get effectiveIpv4Access {
    if (!effectiveInternetAccess) return false;
    if (!ipv4Access && isExpired) return true;
    return ipv4Access;
  }

  bool get effectiveIpv6Access {
    if (!effectiveInternetAccess) return false;
    if (!ipv6Access && isExpired) return true;
    return ipv6Access;
  }

  bool get isEffectivelyBlocked =>
      !effectiveInternetAccess ||
      (!effectiveIpv4Access && !effectiveIpv6Access);

  bool get isIpv4OnlyBlocked =>
      effectiveInternetAccess && !effectiveIpv4Access && effectiveIpv6Access;

  bool get isIpv6OnlyBlocked =>
      effectiveInternetAccess && effectiveIpv4Access && !effectiveIpv6Access;

  bool get hasAnyRestriction =>
      !effectiveInternetAccess || !effectiveIpv4Access || !effectiveIpv6Access;

  NetworkAccessPolicy copyWith({
    String? targetMac,
    bool? internetAccess,
    bool? ipv4Access,
    bool? ipv6Access,
    DateTime? scheduleExpiry,
    bool clearScheduleExpiry = false,
  }) {
    return NetworkAccessPolicy(
      targetMac: targetMac ?? this.targetMac,
      internetAccess: internetAccess ?? this.internetAccess,
      ipv4Access: ipv4Access ?? this.ipv4Access,
      ipv6Access: ipv6Access ?? this.ipv6Access,
      scheduleExpiry: clearScheduleExpiry
          ? null
          : (scheduleExpiry ?? this.scheduleExpiry),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'targetMac': ClientNamingHelper.normalizeMac(targetMac),
      'internetAccess': internetAccess,
      'ipv4Access': ipv4Access,
      'ipv6Access': ipv6Access,
      if (scheduleExpiry != null)
        'scheduleExpiry': scheduleExpiry!.toIso8601String(),
    };
  }

  factory NetworkAccessPolicy.fromJson(Map<String, dynamic> json) {
    return NetworkAccessPolicy(
      targetMac: ClientNamingHelper.normalizeMac(
        json['targetMac']?.toString() ?? '',
      ),
      internetAccess: json['internetAccess'] as bool? ?? true,
      ipv4Access: json['ipv4Access'] as bool? ?? true,
      ipv6Access: json['ipv6Access'] as bool? ?? true,
      scheduleExpiry: json['scheduleExpiry'] != null
          ? DateTime.tryParse(json['scheduleExpiry'].toString())
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkAccessPolicy &&
        ClientNamingHelper.normalizeMac(other.targetMac) ==
            ClientNamingHelper.normalizeMac(targetMac) &&
        other.internetAccess == internetAccess &&
        other.ipv4Access == ipv4Access &&
        other.ipv6Access == ipv6Access &&
        other.scheduleExpiry == scheduleExpiry;
  }

  @override
  int get hashCode => Object.hash(
    ClientNamingHelper.normalizeMac(targetMac),
    internetAccess,
    ipv4Access,
    ipv6Access,
    scheduleExpiry,
  );

  @override
  String toString() {
    return 'NetworkAccessPolicy(targetMac: $targetMac, internetAccess: $internetAccess, '
        'ipv4Access: $ipv4Access, ipv6Access: $ipv6Access, '
        'effectiveIpv4: $effectiveIpv4Access, effectiveIpv6: $effectiveIpv6Access, '
        'scheduleExpiry: $scheduleExpiry)';
  }
}
