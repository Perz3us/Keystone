// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

Future<bool> confirmReviewerMode(BuildContext context) => ksConfirm(
  context,
  title: 'Open the demo?',
  body:
      'Look around Keystone with a made-up router and devices. Nothing you '
      'do reaches a real router. Leave it from More, Leave the demo.',
  action: 'Open the demo',
);
