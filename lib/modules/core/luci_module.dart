// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../../models/router_capabilities.dart';

enum LuciModuleCategory {
  core,
  monitoring,
  network,
  wireless,
  security,
  system,
  services,
  applications,
  tools,
}

class LuciModuleQuickAction {
  final String id;
  final String label;
  final IconData icon;
  final void Function(BuildContext context) onTap;

  const LuciModuleQuickAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

abstract class LuciModule {
  String get id;

  String get name;

  String get description;

  IconData get icon;

  IconData get selectedIcon => icon;

  LuciModuleCategory get category;

  int get priority => 100;

  bool get isEnabled => true;

  Set<String> get requiredUbus => const {};

  Set<String> get requiredConfigs => const {};

  bool isAvailableOn(RouterCapabilities? caps) {
    if (caps == null || caps.probeFailed || caps.installedUbus.isEmpty) {
      return true;
    }
    if (!caps.installedUbus.containsAll(requiredUbus)) return false;
    return caps.installedConfigs.isEmpty ||
        caps.installedConfigs.containsAll(requiredConfigs);
  }

  bool get showInBottomNav => false;

  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params});

  List<LuciModuleQuickAction> get quickActions => const [];

  Future<void> initialize() async {}

  Future<void> dispose() async {}
}
