// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/system_backup_upgrade_screen.dart';

class SystemBackupUpgradeModule extends LuciModule {
  @override
  String get id => 'system_backup_upgrade';

  @override
  String get name => 'Backup and firmware';

  @override
  String get description =>
      'Save or restore settings, reset, or update the firmware';

  @override
  IconData get icon => Icons.system_update_alt_outlined;

  @override
  IconData get selectedIcon => Icons.system_update_alt;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 75;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const SystemBackupUpgradeScreen();
  }
}
