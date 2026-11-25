// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

class GatewayUtils {
  static Future<String?> detectGatewayIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isWifiOrEth =
            name.contains('wlan') ||
            name.contains('wifi') ||
            name.contains('wl') ||
            name.contains('eth') ||
            (name.contains('en') && !name.contains('entry')) ||
            name.contains('lan');

        if (isWifiOrEth &&
            interface.addresses.any(
              (a) => !a.isLoopback && a.type == InternetAddressType.IPv4,
            )) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              final parts = addr.address.split('.');
              if (parts.length == 4) {
                return '${parts[0]}.${parts[1]}.${parts[2]}.1';
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
