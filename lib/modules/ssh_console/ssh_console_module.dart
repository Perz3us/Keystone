// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/ssh_console_screen.dart';

class SshConsoleModule extends LuciModule {
  @override
  String get id => 'ssh_console';

  @override
  String get name => 'SSH Terminal';

  @override
  String get description => 'A command line on the router, with saved commands';

  @override
  IconData get icon => Icons.terminal_outlined;

  @override
  IconData get selectedIcon => Icons.terminal;

  @override
  LuciModuleCategory get category => LuciModuleCategory.system;

  @override
  int get priority => 56;

  @override
  bool get showInBottomNav => false;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const SshConsoleScreen();
  }
}
