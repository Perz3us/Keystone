// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/adguard_home_screen.dart';

class AdGuardHomeModule extends LuciModule {
  @override
  String get id => 'adguard_home';

  @override
  Set<String> get requiredConfigs => const {'adguardhome'};

  @override
  String get name => 'AdGuard Home';

  @override
  String get description => 'Block ads and trackers for every device';

  @override
  IconData get icon => Icons.shield_outlined;

  @override
  IconData get selectedIcon => Icons.shield;

  @override
  LuciModuleCategory get category => LuciModuleCategory.security;

  @override
  int get priority => 52;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    final routerId = params?['routerId'] as String?;
    return AdGuardHomeScreen(routerId: routerId);
  }
}
