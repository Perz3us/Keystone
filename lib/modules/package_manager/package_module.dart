// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/package_manager_screen.dart';

class PackageManagerModule extends LuciModule {
  @override
  String get id => 'package_manager';

  @override
  String get name => 'Software';

  @override
  String get description => 'Install, update and remove router software';

  @override
  IconData get icon => Icons.inventory_2_outlined;

  @override
  IconData get selectedIcon => Icons.inventory_2;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 60;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const PackageManagerScreen();
  }
}
