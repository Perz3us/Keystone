// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';
import '../../core/luci_module.dart';

class BandixModule extends LuciModule {
  @override
  String get id => 'noobwrt_bandix';

  @override
  Set<String> get requiredUbus => const {'luci.bandix'};

  @override
  String get name => 'Traffic per device';

  @override
  String get description => 'Which devices used the most data';

  @override
  IconData get icon => Icons.swap_vert_circle_outlined;

  @override
  IconData get selectedIcon => Icons.swap_vert_circle;

  @override
  LuciModuleCategory get category => LuciModuleCategory.monitoring;

  @override
  int get priority => 15;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const AllDevicesScreen(byData: true);
}
