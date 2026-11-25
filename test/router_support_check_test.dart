// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/utils/router_support.dart';

void main() {
  test('OpenWrt board reply is supported', () {
    expect(
      looksLikeOpenWrt([
        0,
        {
          'board_name': 'arcadyan,aw1000',
          'release': {'distribution': 'OpenWrt', 'version': '25.12.5'},
        },
      ]),
      isTrue,
    );
  });

  test('ubus permission error is still OpenWrt', () {
    expect(looksLikeOpenWrt([6]), isTrue);
  });

  test('reply without release info is not OpenWrt', () {
    expect(
      looksLikeOpenWrt([
        0,
        ['not', 'a', 'map'],
      ]),
      isFalse,
    );
    expect(looksLikeOpenWrt([0, <String, dynamic>{}]), isFalse);
  });

  test('non-ubus replies are not OpenWrt', () {
    expect(looksLikeOpenWrt(null), isFalse);
    expect(looksLikeOpenWrt('<html>'), isFalse);
    expect(looksLikeOpenWrt(['x']), isFalse);
    expect(looksLikeOpenWrt(const []), isFalse);
  });

  test('reaches an address with an open port', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    addTearDown(server.close);
    expect(await canReachRouter('127.0.0.1:${server.port}', false), isTrue);
  });

  test('gives up quickly on a closed port', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final port = server.port;
    await server.close();
    final watch = Stopwatch()..start();
    expect(
      await canReachRouter(
        '127.0.0.1:$port',
        false,
        timeout: const Duration(seconds: 2),
      ),
      isFalse,
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
  });
}
