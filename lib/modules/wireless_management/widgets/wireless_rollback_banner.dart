// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import '../models/wireless_info.dart';
import 'edit_radio_dialog.dart';
import 'edit_ssid_dialog.dart';

class WirelessRollbackBanner extends ConsumerWidget {
  const WirelessRollbackBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);

    if (!appState.isAccessControlPendingConfirmation) {
      return const SizedBox.shrink();
    }

    final hasUciWrite =
        (appState.capabilities?.hasUciWriteAccess ?? true) &&
        appState.isAdministrativeUser;
    final pendingSection = appState.pendingSectionName ?? 'Wireless';

    final ks = context.ks;
    Future<void> keep() async {
      final ok = await appState.confirmWifiAccessControlChanges();
      if (context.mounted) {
        ksSay(context, ok ? 'Kept.' : "The router didn't get that. Try again.");
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: ks.sheet,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ks.warn.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep the change to $pendingSection?',
            style: KeystoneType.bodyStrong(ks.tx),
          ),
          const SizedBox(height: 4),
          Text(
            "Check everything still works, then keep it. Undo puts the "
            'old settings back.',
            style: KeystoneType.secondary(ks.mu),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _handleRevert(context, ref, appState),
                child: const Text('Undo'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: hasUciWrite ? keep : null,
                child: const Text('Keep it'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleRevert(
    BuildContext context,
    WidgetRef ref,
    AppState appState,
  ) async {
    final pendingSection = appState.pendingSectionName;
    final pendingType = appState.pendingTargetType;
    final targetRadio = appState.pendingTargetRadio;
    final targetInterface = appState.pendingTargetInterface;

    ksSay(context, 'Reverting staged wireless changes...');

    final reverted = await appState.revertWifiAccessControlChanges(
      context: context,
    );

    if (!context.mounted) return;

    if (reverted) {
      ksSay(context, 'Wireless changes reverted & verified on router.');
    } else {
      ksSay(context, 'Revert signal sent. Verifying router UCI status...');
    }

    final overview = WirelessOverview.fromDashboardData(
      appState.dashboardData,
      isReviewerMode: appState.reviewerModeEnabled,
    );

    if (pendingType == 'radio' &&
        (targetRadio != null || pendingSection != null)) {
      final radioToEdit =
          targetRadio ??
          overview.radios.firstWhere(
            (r) => r.name == pendingSection,
            orElse: () => overview.radios.first,
          );
      await showDialog(
        context: context,
        builder: (ctx) => EditRadioDialog(radio: radioToEdit),
      );
    } else if (pendingType == 'ssid' && targetInterface != null) {
      final parentRadio =
          targetRadio ??
          overview.radios.firstWhere(
            (r) => r.interfaces.any(
              (i) => i.sectionName == targetInterface.sectionName,
            ),
            orElse: () => overview.radios.first,
          );
      await showDialog(
        context: context,
        builder: (ctx) =>
            EditSsidDialog(radio: parentRadio, interface: targetInterface),
      );
    }
  }
}
