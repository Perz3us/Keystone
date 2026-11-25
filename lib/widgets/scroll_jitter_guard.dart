// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';

class ScrollJitterGuard extends ConsumerWidget {
  final Widget child;

  const ScrollJitterGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        final appState = ref.read(appStateProvider);
        if (notification is ScrollStartNotification) {
          appState.setScrollState(true);
        } else if (notification is ScrollEndNotification) {
          appState.setScrollState(false);
        }
        return false;
      },
      child: child,
    );
  }
}
