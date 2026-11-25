// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/services_system_screen.dart';

class ServicesSystemModule extends LuciModule {
  @override
  String get id => 'services_system';

  @override
  String get name => 'Services';

  @override
  String get description =>
      'Start or stop router services, scheduled tasks, dynamic DNS';

  @override
  IconData get icon => Icons.settings_applications_outlined;

  @override
  IconData get selectedIcon => Icons.settings_applications;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 50;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const ServicesSystemScreen();
  }
}
