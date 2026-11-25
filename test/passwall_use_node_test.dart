// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/passwall/passwall_module.dart';

void main() {
  PasswallInfo p(Map<String, dynamic> g) => PasswallInfo(g, const [], null);

  test('Passwall 1 moves the UDP node with the TCP node', () {
    expect(p({'tcp_node': 'a', 'udp_node': 'a'}).useNode('b'), {
      'tcp_node': 'b',
      'udp_node': 'b',
    });
  });

  test('a UDP node that follows TCP or is off is left alone', () {
    expect(p({'tcp_node': 'a', 'udp_node': 'tcp'}).useNode('b'), {
      'tcp_node': 'b',
    });
    expect(p({'tcp_node': 'a', 'udp_node': 'nil'}).useNode('b'), {
      'tcp_node': 'b',
    });
  });

  test('Passwall2 has one node', () {
    expect(p({'node': 'a'}).useNode('b'), {'node': 'b'});
  });
}
