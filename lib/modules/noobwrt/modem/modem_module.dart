// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../core/luci_module.dart';
import 'modem_screen.dart';

class ModemModule extends LuciModule {
  @override
  String get id => 'noobwrt_modem';

  @override
  Set<String> get requiredConfigs => const {'5gmodem'};

  @override
  String get name => 'Modem';

  @override
  String get description => 'Signal, bands, the tower and SIM details';

  @override
  IconData get icon => Icons.cell_tower_outlined;

  @override
  IconData get selectedIcon => Icons.cell_tower;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 12;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const ModemScreen();
}
