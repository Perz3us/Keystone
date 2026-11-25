// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_settings_screen.dart';

class WirelessManagementModule extends LuciModule {
  @override
  String get id => 'wireless_management';

  @override
  String get name => 'Wi-Fi settings';

  @override
  String get description => 'Every network, channels and who can join';

  @override
  IconData get icon => Icons.wifi_outlined;

  @override
  IconData get selectedIcon => Icons.wifi;

  @override
  LuciModuleCategory get category => LuciModuleCategory.wireless;

  @override
  int get priority => 25;

  @override
  bool get showInBottomNav => true;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const WifiSettingsScreen();
  }
}
