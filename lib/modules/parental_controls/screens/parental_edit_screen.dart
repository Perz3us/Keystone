// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/wireless_management/screens/wifi_access_control_screen.dart'
    show parseMac;
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/parental_controls_controller.dart';
import '../models/parental_controls_store.dart';
import '../models/parental_profile.dart';
import 'parental_controls_screen.dart';
import 'parental_words.dart';

const parentalLimits = [30, 60, 90, 120, 180, 240];

class ParentalEditScreen extends ConsumerStatefulWidget {
  const ParentalEditScreen({super.key, this.existing});
  final ParentalProfile? existing;

  @override
  ConsumerState<ParentalEditScreen> createState() => _ParentalEditScreenState();
}

class _ParentalEditScreenState extends ConsumerState<ParentalEditScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _macs = <String>{
    ...?widget.existing?.macAddresses.map((m) => parseMac(m) ?? m),
  };
  late bool _bedtime = widget.existing?.hasSchedule ?? false;
  late TimeSchedule _schedule =
      widget.existing?.schedule ??
      TimeSchedule(
        activeDays: ScheduleDay.values.toSet(),
        blockHour: 21,
        blockMinute: 0,
        resumeHour: 7,
        resumeMinute: 0,
      );
  late int? _limit = widget.existing?.hasTimeLimit ?? false
      ? widget.existing!.dailyTimeLimitMinutes
      : null;
  late ContentFilterDns _filter =
      widget.existing?.contentFilter ?? ContentFilterDns.none;
  late final _dns1 = TextEditingController(
    text: widget.existing?.customDnsServers.firstOrNull ?? '',
  );
  late final _dns2 = TextEditingController(
    text: (widget.existing?.customDnsServers.length ?? 0) > 1
        ? widget.existing!.customDnsServers[1]
        : '',
  );
  final _typed = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _dns1, _dns2, _typed]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      !_saving &&
      (_filter != ContentFilterDns.custom || _dns1.text.trim().isNotEmpty);

  Future<void> _pick(bool off) async {
    final t = await showTimePicker(
      context: context,
      initialTime: off
          ? TimeOfDay(hour: _schedule.blockHour, minute: _schedule.blockMinute)
          : TimeOfDay(
              hour: _schedule.resumeHour,
              minute: _schedule.resumeMinute,
            ),
    );
    if (t == null) return;
    setState(
      () => _schedule = off
          ? _schedule.copyWith(blockHour: t.hour, blockMinute: t.minute)
          : _schedule.copyWith(resumeHour: t.hour, resumeMinute: t.minute),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final e = widget.existing;
    final p = ParentalProfile(
      id: e?.id ?? ParentalControlsStore.generateId(),
      name: _name.text.trim(),
      icon: e?.icon ?? '',
      color: e?.color ?? '#3B82F6',
      macAddresses: _macs.toList(),
      isPaused: e?.isPaused ?? false,
      isEnabled: e?.isEnabled ?? true,
      pauseExpiresAt: e?.pauseExpiresAt,
      schedule: _bedtime
          ? _schedule.copyWith(
              enabled: true,
              activeDays: _schedule.activeDays.isEmpty
                  ? ScheduleDay.values.toSet()
                  : _schedule.activeDays,
            )
          : null,
      dailyTimeLimitMinutes: _limit,
      contentFilter: _filter,
      customDnsServers: _filter == ContentFilterDns.custom
          ? [
              for (final d in [_dns1.text.trim(), _dns2.text.trim()])
                if (d.isNotEmpty) d,
            ]
          : const [],
    );
    final app = ref.read(appStateProvider);
    final c = ParentalControlsController.instance;
    final r = e == null
        ? await c.addProfile(p, app, context: context)
        : await c.updateProfile(p, e, app, context: context);
    if (!mounted) return;
    setState(() => _saving = false);
    if (parentalSay(context, r)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final known = {
      for (final c in app.clients) ?parseMac(c.macAddress): c.displayName,
    };
    final listed = {..._macs, ...known.keys}.toList()
      ..sort((a, b) {
        final pa = _macs.contains(a), pb = _macs.contains(b);
        if (pa != pb) return pa ? -1 : 1;
        return (known[a] ?? a).toLowerCase().compareTo(
          (known[b] ?? b).toLowerCase(),
        );
      });
    final filterChanged =
        _filter != (widget.existing?.contentFilter ?? ContentFilterDns.none);

    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(widget.existing == null ? 'Add' : 'Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          children: [
            KsTitle(widget.existing == null ? 'Add a person' : 'Edit'),
            KsField(
              label: 'Name',
              controller: _name,
              hint: 'For example Sam',
              onChanged: (_) => setState(() {}),
            ),
            const KsSection('Their devices'),
            if (listed.isEmpty)
              Text(
                'No devices seen yet. Add one by its address below.',
                style: KeystoneType.secondary(ks.mu),
              ),
            for (final m in listed)
              CheckboxListTile(
                value: _macs.contains(m),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(known[m] ?? m, style: KeystoneType.body(ks.tx)),
                subtitle: known[m] == null
                    ? null
                    : Text(m, style: KeystoneType.caption(ks.mu)),
                onChanged: (v) =>
                    setState(() => v == true ? _macs.add(m) : _macs.remove(m)),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: KsField(
                    label: 'Add by address',
                    controller: _typed,
                    hint: 'AA:BB:CC:DD:EE:FF',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 28, left: 8),
                  child: TextButton(
                    onPressed: () {
                      final m = parseMac(_typed.text);
                      if (m == null) {
                        ksSay(context, "That isn't a device address.");
                        return;
                      }
                      setState(() {
                        _macs.add(m);
                        _typed.clear();
                      });
                    },
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
            const KsSection('Bedtime'),
            KsSwitchRow(
              title: 'No internet at night',
              subtitle: _bedtime ? bedtimeWords(_schedule) : 'Off',
              value: _bedtime,
              onChanged: (v) => setState(() => _bedtime = v),
            ),
            if (_bedtime) ...[
              KsRow(
                title: 'Internet off at',
                trailing: Text(
                  hhmm(_schedule.blockHour, _schedule.blockMinute),
                  style: KeystoneType.bodyStrong(ks.tx),
                ),
                chevron: false,
                onTap: () => _pick(true),
              ),
              KsRow(
                title: 'Back on at',
                trailing: Text(
                  hhmm(_schedule.resumeHour, _schedule.resumeMinute),
                  style: KeystoneType.bodyStrong(ks.tx),
                ),
                chevron: false,
                onTap: () => _pick(false),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final d in ScheduleDay.values)
                    FilterChip(
                      label: Text(d.shortLabel),
                      selected: _schedule.activeDays.contains(d),
                      onSelected: (v) => setState(() {
                        final days = {..._schedule.activeDays};
                        v ? days.add(d) : days.remove(d);
                        _schedule = _schedule.copyWith(activeDays: days);
                      }),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'The nights it starts on.',
                  style: KeystoneType.caption(ks.mu),
                ),
              ),
            ],
            const KsSection('Daily limit'),
            KsChips<int?>(
              options: [
                (null, 'None'),
                for (final m in parentalLimits) (m, limitWords(m)),
              ],
              selected: _limit,
              onSelected: (v) => setState(() => _limit = v),
            ),
            const KsSection('Site filter'),
            KsChoice<ContentFilterDns>(
              label: 'Filter',
              value: _filter,
              options: [
                for (final f in ContentFilterDns.values) (f, filterWords(f)),
              ],
              onChanged: (v) => setState(() => _filter = v),
            ),
            if (_filter == ContentFilterDns.custom) ...[
              KsField(
                label: 'Filter service address',
                controller: _dns1,
                hint: '1.1.1.3',
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
              KsField(
                label: 'Second address (optional)',
                controller: _dns2,
                keyboardType: TextInputType.number,
              ),
            ],
            if (filterChanged)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Devices pick up a new filter the next time they join '
                  'Wi-Fi. Turn their Wi-Fi off and on to make it '
                  'immediate.',
                  style: KeystoneType.caption(ks.mu),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
