// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

import '../../../services/app_update.dart';
import '../history/helper_installer.dart';
import '../history/helper_sheet.dart';

@immutable
class Addon {
  const Addon({
    required this.name,
    required this.about,
    required this.helper,
    required this.open,
  });
  final String name;
  final String about;
  final HelperInstaller helper;
  final Future<void> Function(BuildContext, HelperInstaller) open;
}

List<Addon> addonsFor(AppState app) => [
  Addon(
    name: 'Signal history',
    about: 'Signal, line ping and data over time',
    helper: HelperInstaller(app),
    open: showHelperSheet,
  ),
];

@immutable
class AddonStatus {
  const AddonStatus({this.have, this.release, this.offline = false});
  final String? have;
  final HelperRelease? release;
  final bool offline;

  bool get listed => have != null || release != null || offline;

  bool get update {
    final h = have, r = release;
    return h != null && r != null && isNewerVersion(r.version, h);
  }
}

Future<AddonStatus> addonStatus(HelperInstaller helper) async {
  final have = await helper.installed();
  try {
    return AddonStatus(have: have, release: await helper.latestRelease());
  } catch (_) {
    return AddonStatus(have: have, offline: true);
  }
}

final addonUpdates = ValueNotifier<(String, int)?>(null);

int addonUpdatesFor(String? routerId) {
  final u = addonUpdates.value;
  return u != null && u.$1 == routerId ? u.$2 : 0;
}

String addonsLine(int updates) => switch (updates) {
  0 => 'Extra features for this router',
  1 => '1 update available',
  _ => '$updates updates available',
};

void noteAddons(String? routerId, Iterable<AddonStatus> all) {
  if (routerId == null || all.any((s) => s.offline)) return;
  final n = all.where((s) => s.update).length;
  if (n > 0) {
    addonUpdates.value = (routerId, n);
  } else if (addonUpdates.value?.$1 == routerId) {
    addonUpdates.value = null;
  }
}

String? _checked;

Future<void> checkAddons(AppState app, {List<Addon>? addons}) async {
  final id = app.selectedRouter?.id;
  if (id == null || id == _checked || app.reviewerModeEnabled) return;
  _checked = id;
  noteAddons(id, [
    for (final a in addons ?? addonsFor(app)) await addonStatus(a.helper),
  ]);
}
