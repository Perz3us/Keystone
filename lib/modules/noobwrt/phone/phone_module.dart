// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import '../../core/luci_module.dart';
import 'phone_screen.dart';

class PhoneModule extends LuciModule {
  @override
  String get id => 'noobwrt_phone';

  @override
  Set<String> get requiredUbus => const {'fxs'};

  @override
  String get name => 'Phone';

  @override
  String get description => 'The phone line, calls and text messages';

  @override
  IconData get icon => Icons.phone_outlined;

  @override
  IconData get selectedIcon => Icons.phone;

  @override
  LuciModuleCategory get category => LuciModuleCategory.services;

  @override
  int get priority => 13;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      const PhoneScreen();
}
