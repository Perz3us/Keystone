// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import '../core/luci_module.dart';
import 'screens/parental_controls_screen.dart';

class ParentalControlsModule extends LuciModule {
  @override
  String get id => 'parental_controls';

  @override
  String get name => 'Parental Controls';

  @override
  String get description =>
      'Bedtimes, daily limits and site filters per device';

  @override
  IconData get icon => Icons.family_restroom_outlined;

  @override
  IconData get selectedIcon => Icons.family_restroom;

  @override
  LuciModuleCategory get category => LuciModuleCategory.security;

  @override
  int get priority => 35;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) {
    return const ParentalControlsScreen();
  }
}
