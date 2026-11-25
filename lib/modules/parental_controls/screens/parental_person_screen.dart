// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/parental_controls_controller.dart';
import 'parental_controls_screen.dart';
import 'parental_edit_screen.dart';
import 'parental_words.dart';

class ParentalPersonScreen extends ConsumerStatefulWidget {
  const ParentalPersonScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ParentalPersonScreen> createState() =>
      _ParentalPersonScreenState();
}

class _ParentalPersonScreenState extends ConsumerState<ParentalPersonScreen> {
  final _c = ParentalControlsController.instance;

  @override
  void initState() {
    super.initState();
    _c.store.addListener(_changed);
  }

  @override
  void dispose() {
    _c.store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final p = _c.store.profiles.where((p) => p.id == widget.id).firstOrNull;
    if (p == null) {
      return const KsPage(title: 'Removed', children: [SizedBox.shrink()]);
    }
    final busy = _c.isProfileOperationPending(p.id);
    final paused = isPausedNow(p);
    void edit() => Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ParentalEditScreen(existing: p),
      ),
    );

    return KsPage(
      title: p.name,
      subtitle: personStatus(p, used: minutesUsed(p, _c.store)),
      actions: [
        TextButton(
          onPressed: edit,
          child: Text('Edit', style: KeystoneType.body(ks.mu)),
        ),
      ],
      children: [
        const SizedBox(height: 8),
        if (p.isEnabled && p.hasMacs)
          FilledButton(
            onPressed: busy
                ? null
                : () => paused
                      ? resumePerson(context, ref, p)
                      : pausePerson(context, ref, p),
            child: Text(paused ? 'Resume internet' : 'Pause internet'),
          ),
        const KsSection('Devices'),
        if (!p.hasMacs)
          KsNote(
            'No devices yet. Rules only work on the devices you pick.',
            action: 'Pick devices',
            onAction: edit,
          )
        else
          for (final m in p.macAddresses)
            KsRow(
              title:
                  app.clients
                      .where(
                        (c) =>
                            ClientNamingHelper.normalizeMac(c.macAddress) ==
                            ClientNamingHelper.normalizeMac(m),
                      )
                      .firstOrNull
                      ?.displayName ??
                  m,
              subtitle: m,
              chevron: false,
            ),
        const KsSection('Rules'),
        KsRow(
          title: 'Bedtime',
          subtitle: p.hasSchedule ? bedtimeWords(p.schedule!) : 'None',
          onTap: edit,
        ),
        KsRow(
          title: 'Daily limit',
          subtitle: p.hasTimeLimit
              ? '${limitWords(p.dailyTimeLimitMinutes!)} a day'
              : 'None',
          onTap: edit,
        ),
        KsRow(
          title: 'Site filter',
          subtitle: filterWords(p.contentFilter),
          onTap: edit,
        ),
        KsSwitchRow(
          title: 'Rules on',
          subtitle: 'Turn off for free access without losing the rules',
          value: p.isEnabled,
          busy: busy,
          onChanged: (_) async {
            final r = await _c.toggleProfileEnabled(
              p.id,
              app,
              context: context,
            );
            if (context.mounted) parentalSay(context, r);
          },
        ),
        const SizedBox(height: 16),
        KsRow(
          title: 'Remove ${p.name}',
          danger: true,
          chevron: false,
          onTap: () async {
            final ok = await ksConfirm(
              context,
              title: 'Remove ${p.name}?',
              body: 'Their devices get normal internet again.',
              action: 'Remove',
              danger: true,
            );
            if (!ok || !context.mounted) return;
            final r = await _c.deleteProfile(p.id, app, context: context);
            if (context.mounted && parentalSay(context, r)) {
              Navigator.pop(context);
            }
          },
        ),
      ],
    );
  }
}
