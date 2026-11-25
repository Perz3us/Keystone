// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/sqm_screen.dart';

class SqmModule extends LuciModule {
  @override
  String get id => 'sqm';

  @override
  Set<String> get requiredConfigs => const {'sqm'};

  @override
  String get name => 'Smooth connection (SQM)';

  @override
  String get description => 'Keep calls and games smooth while others download';

  @override
  IconData get icon => Icons.waves_outlined;

  @override
  IconData get selectedIcon => Icons.waves_rounded;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 33;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    final routerId = params?['routerId'] as String?;
    return SqmScreen(routerId: routerId);
  }
}
