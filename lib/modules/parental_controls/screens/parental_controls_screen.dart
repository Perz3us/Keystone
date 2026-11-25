// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/parental_controls_controller.dart';
import '../models/parental_profile.dart';
import 'parental_edit_screen.dart';
import 'parental_person_screen.dart';
import 'parental_words.dart';

bool parentalSay(BuildContext context, ParentalActionResult r) {
  if (!r.success) {
    ksSay(
      context,
      r.errorReason == null ? r.message : '${r.message} ${r.errorReason}',
    );
  }
  return r.success;
}

Future<void> pausePerson(
  BuildContext context,
  WidgetRef ref,
  ParentalProfile p,
) async {
  final d = await ksSheet<PauseDuration>(context, (c) {
    final ks = c.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pause ${p.name}', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'Their devices stay on Wi-Fi but get no internet.',
          style: KeystoneType.secondary(ks.mu),
        ),
        const SizedBox(height: 8),
        for (final d in PauseDuration.values)
          KsRow(
            title: pauseWords(d),
            chevron: false,
            onTap: () => Navigator.pop(c, d),
          ),
      ],
    );
  });
  if (d == null || !context.mounted) return;
  final r = await ParentalControlsController.instance.pauseProfile(
    p,
    d,
    ref.read(appStateProvider),
    context: context,
  );
  if (context.mounted) parentalSay(context, r);
}

Future<void> resumePerson(
  BuildContext context,
  WidgetRef ref,
  ParentalProfile p,
) async {
  final r = await ParentalControlsController.instance.resumeProfile(
    p,
    appState: ref.read(appStateProvider),
  );
  if (context.mounted) parentalSay(context, r);
}

class ParentalListView extends StatelessWidget {
  const ParentalListView({
    super.key,
    required this.people,
    required this.statusOf,
    required this.onOpen,
    required this.onPause,
    required this.onResume,
    required this.onAdd,
    this.pending = const {},
    this.onActivity,
  });

  final List<ParentalProfile> people;
  final String Function(ParentalProfile) statusOf;
  final ValueChanged<ParentalProfile> onOpen;
  final ValueChanged<ParentalProfile> onPause;
  final ValueChanged<ParentalProfile> onResume;
  final VoidCallback onAdd;
  final Set<String> pending;
  final VoidCallback? onActivity;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    if (people.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Add someone, pick their devices, then pause their internet '
            'with one tap, give them a bedtime or a daily limit, and filter '
            'adult sites.',
            style: KeystoneType.body(ks.tx2),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAdd, child: const Text('Add a person')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KsSection('People'),
        for (final p in people)
          KsRow(
            title: p.name,
            subtitle: statusOf(p),
            onTap: () => onOpen(p),
            chevron: false,
            trailing: pending.contains(p.id)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : !p.isEnabled || !p.hasMacs
                ? Icon(Icons.chevron_right_rounded, color: ks.mu)
                : TextButton(
                    onPressed: () => isPausedNow(p) ? onResume(p) : onPause(p),
                    child: Text(isPausedNow(p) ? 'Resume' : 'Pause'),
                  ),
          ),
        KsRow(
          title: 'Add a person',
          leading: Icon(Icons.add_rounded, color: ks.mu),
          onTap: onAdd,
        ),
        if (onActivity != null)
          KsRow(
            title: 'Activity',
            subtitle: 'Pauses, bedtimes and changes',
            onTap: onActivity,
          ),
      ],
    );
  }
}

class ParentalControlsScreen extends ConsumerStatefulWidget {
  const ParentalControlsScreen({super.key});

  @override
  ConsumerState<ParentalControlsScreen> createState() =>
      _ParentalControlsScreenState();
}

class _ParentalControlsScreenState extends ConsumerState<ParentalControlsScreen>
    with WidgetsBindingObserver {
  final _c = ParentalControlsController.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.store.addListener(_changed);
    _load();
  }

  Future<void> _load() async {
    final app = ref.read(appStateProvider);
    await _c.loadStore(app);
    _c.startExpiryTimer(app);
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c.store.removeListener(_changed);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) _c.handleLifecycleState(state, ref.read(appStateProvider));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _push(Widget page, {bool dialog = false}) => Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: dialog, builder: (_) => page),
  );

  @override
  Widget build(BuildContext context) {
    final people = _c.store.profiles;
    return KsPage(
      title: 'Parental Controls',
      subtitle: 'Bedtimes, daily limits and site filters per person',
      onRefresh: _load,
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          ParentalListView(
            people: people,
            statusOf: (p) => personStatus(p, used: minutesUsed(p, _c.store)),
            pending: {
              for (final p in people)
                if (_c.isProfileOperationPending(p.id)) p.id,
            },
            onOpen: (p) => _push(ParentalPersonScreen(id: p.id)),
            onPause: (p) => pausePerson(context, ref, p),
            onResume: (p) => resumePerson(context, ref, p),
            onAdd: () => _push(const ParentalEditScreen(), dialog: true),
            onActivity: _c.store.activityLog.isEmpty
                ? null
                : () => _push(const ParentalActivityScreen()),
          ),
      ],
    );
  }
}

class ParentalActivityScreen extends ConsumerWidget {
  const ParentalActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ks = context.ks;
    final c = ParentalControlsController.instance;
    final log = c.store.activityLog.reversed.take(200).toList();
    String when(DateTime t) {
      final l = t.toLocal();
      final now = DateTime.now();
      final day = l.year == now.year && l.month == now.month && l.day == now.day
          ? 'Today'
          : '${l.day}/${l.month}';
      return '$day ${hhmm(l.hour, l.minute)}';
    }

    return KsPage(
      title: 'Activity',
      actions: [
        if (log.isNotEmpty)
          TextButton(
            onPressed: () async {
              final ok = await ksConfirm(
                context,
                title: 'Clear the activity?',
                body: 'The rules stay as they are.',
                action: 'Clear',
                danger: true,
              );
              if (!ok || !context.mounted) return;
              final r = await c.clearActivityLog(ref.read(appStateProvider));
              if (!context.mounted) return;
              if (parentalSay(context, r)) Navigator.pop(context);
            },
            child: Text('Clear', style: KeystoneType.body(ks.mu)),
          ),
      ],
      children: [
        if (log.isEmpty)
          Text('Nothing yet.', style: KeystoneType.body(ks.mu))
        else
          for (final e in log)
            KsRow(
              title: '${e.profileName}: ${eventWords(e.eventType)}',
              subtitle: when(e.timestamp),
              chevron: false,
            ),
      ],
    );
  }
}
