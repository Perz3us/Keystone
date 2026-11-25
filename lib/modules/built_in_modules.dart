// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'core/luci_module.dart';
import 'core/luci_module_registry.dart';
import 'wireless_management/wireless_module.dart';
import 'firewall_security/firewall_module.dart';
import 'services_system/services_module.dart';
import 'vpn_connectivity/vpn_module.dart';
import 'package_manager/package_module.dart';
import 'system_backup_upgrade/system_backup_upgrade_module.dart';
import 'parental_controls/parental_controls_module.dart';
import 'diagnostics/diagnostics_module.dart';
import 'sqm/sqm_module.dart';
import 'adguard_home/adguard_home_module.dart';
import 'ssh_console/ssh_console_module.dart';
import 'noobwrt/cellular/cellular_module.dart';
import 'noobwrt/modem/modem_module.dart';
import 'noobwrt/phone/phone_module.dart';
import 'noobwrt/passwall/passwall_module.dart';
import 'noobwrt/bandix/bandix_module.dart';
import 'noobwrt/tools/tools_module.dart';
import 'noobwrt/apps/apps_module.dart';
import '../screens/network/network_screen.dart';

class InterfacesModule extends LuciModule {
  @override
  String get id => 'interfaces';

  @override
  String get name => 'Network';

  @override
  String get description => 'Internet and home network connections';

  @override
  IconData get icon => Icons.lan_outlined;

  @override
  IconData get selectedIcon => Icons.lan;

  @override
  LuciModuleCategory get category => LuciModuleCategory.network;

  @override
  int get priority => 30;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const NetworkScreen();
  }
}

void registerBuiltInModules() {
  final registry = LuciModuleRegistry.instance;
  registry.registerModules([
    ModemModule(),
    CellularModule(),
    PhoneModule(),
    PasswallModule(),
    PasswallModule(PasswallKind.v1),
    BandixModule(),
    ToolsModule(),
    AppsModule(),
    WirelessManagementModule(),
    FirewallSecurityModule(),
    ServicesSystemModule(),
    VpnConnectivityModule(),
    PackageManagerModule(),
    SystemBackupUpgradeModule(),
    ParentalControlsModule(),
    DiagnosticsModule(),
    SqmModule(),
    AdGuardHomeModule(),
    SshConsoleModule(),
    InterfacesModule(),
  ]);
}
