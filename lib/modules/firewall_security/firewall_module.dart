// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/firewall_security_screen.dart';

class FirewallSecurityModule extends LuciModule {
  @override
  String get id => 'firewall_security';

  @override
  String get name => 'Firewall';

  @override
  String get description => 'Port forwarding and what may come in from outside';

  @override
  IconData get icon => Icons.shield_outlined;

  @override
  IconData get selectedIcon => Icons.shield;

  @override
  LuciModuleCategory get category => LuciModuleCategory.security;

  @override
  int get priority => 40;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const FirewallSecurityScreen();
  }
}
