// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';

bool looksLikeOpenWrt(dynamic boardReply) {
  if (boardReply is! List || boardReply.isEmpty || boardReply[0] is! int) {
    return false;
  }
  if (boardReply[0] != 0) return true;
  final data = boardReply.length > 1 ? boardReply[1] : null;
  return data is Map && data['release'] is Map;
}

class RouterUnreachableException implements Exception {
  final String address;
  const RouterUnreachableException(this.address);

  String get message =>
      "Can't reach $address. Check the address and that this phone is on "
      "the router's network.";

  @override
  String toString() => message;
}

Future<bool> canReachRouter(
  String address,
  bool useHttps, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final uri = Uri.tryParse('//${address.trim()}');
  final host = uri?.host ?? address;
  if (host.isEmpty) return false;
  final ports = (uri?.hasPort ?? false)
      ? [uri!.port]
      : (useHttps ? [443, 80] : [80, 443]);

  Future<bool> tryPort(int port) => Socket.connect(host, port, timeout: timeout)
      .then((s) {
        s.destroy();
        return true;
      })
      .catchError((_) => false);

  final results = await Future.wait(ports.map(tryPort));
  return results.contains(true);
}
