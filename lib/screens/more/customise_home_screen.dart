// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class CustomiseHomeScreen extends ConsumerWidget {
  const CustomiseHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = HomePrefsStore.instance;
    return ValueListenableBuilder<HomePrefs>(
      valueListenable: store,
      builder: (context, p, _) {
        void set(HomePrefs n) => store.save(n);
        final pinnedNames = _pinnedNames(ref, p.pinned);
        return KsPage(
          title: 'Home',
          back: 'Customise',
          subtitle: 'Changes show on Home straight away.',
          children: [
            const KsSection('The picture'),
            KsSegmented<HomeLayout>(
              label: 'Layout',
              value: p.layout,
              options: const [
                (HomeLayout.side, 'Side by side'),
                (HomeLayout.topDown, 'Top to bottom'),
              ],
              onChanged: (v) => set(p.copyWith(layout: v)),
            ),
            KsSegmented<int>(
              label: 'Devices shown',
              value: p.deviceCount,
              options: const [(3, '3'), (4, '4'), (5, '5')],
              onChanged: (v) => set(p.copyWith(deviceCount: v)),
            ),
            KsSegmented<HomePick>(
              label: 'Which devices',
              value: p.pick,
              help: p.pick == HomePick.pinned
                  ? 'Pinned devices show when they\'re online; the busiest '
                        'fill any spare spots.'
                  : 'The ones using the most data right now.',
              options: const [
                (HomePick.busiest, 'Busiest'),
                (HomePick.pinned, 'Pinned'),
              ],
              onChanged: (v) => set(p.copyWith(pick: v)),
            ),
            if (p.pick == HomePick.pinned)
              KsRow(
                title: 'Pinned devices',
                subtitle: pinnedNames.isEmpty
                    ? 'None yet'
                    : pinnedNames.join(', '),
                onTap: () => _pickPinned(context, ref, p),
              ),
            KsSwitchRow(
              title: 'Moving dots',
              subtitle: 'Dots run along a line while data moves on it',
              value: p.flow,
              onChanged: (v) => set(p.copyWith(flow: v)),
            ),
            if (_hasModem(ref)) ...[
              const KsSection('Signal'),
              KsSwitchRow(
                title: 'Signal bars',
                subtitle: 'Like on a phone, under Internet',
                value: p.signalBars,
                onChanged: (v) => set(p.copyWith(signalBars: v)),
              ),
              KsSwitchRow(
                title: 'Beside the router',
                subtitle: 'A few readings in the space on its right',
                value: p.beside,
                onChanged: (v) => set(p.copyWith(beside: v)),
              ),
              if (p.beside) _besideChips(context, p, set),
              KsSwitchRow(
                title: 'Signal details',
                subtitle: 'A section under the picture',
                value: p.signal,
                onChanged: (v) => set(p.copyWith(signal: v)),
              ),
              if (p.signal)
                Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Column(
                    children: [
                      KsSwitchRow(
                        title: 'RSRP and SINR',
                        value: p.signalNumbers,
                        onChanged: (v) => set(p.copyWith(signalNumbers: v)),
                      ),
                      KsSwitchRow(
                        title: 'Carrier bar',
                        value: p.signalBar,
                        onChanged: (v) => set(p.copyWith(signalBar: v)),
                      ),
                      KsSwitchRow(
                        title: 'Carrier list',
                        value: p.signalList,
                        onChanged: (v) => set(p.copyWith(signalList: v)),
                      ),
                    ],
                  ),
                ),
              KsSwitchRow(
                title: 'Remember carriers when idle',
                subtitle:
                    'Extra carriers stay listed as idle when the line is quiet',
                value: p.idleCarriers,
                onChanged: (v) => set(p.copyWith(idleCarriers: v)),
              ),
            ],
            const KsSection('Sections'),
            KsSwitchRow(
              title: 'Shortcuts',
              value: p.shortcuts,
              onChanged: (v) => set(p.copyWith(shortcuts: v)),
            ),
            KsSwitchRow(
              title: 'Right now',
              subtitle: 'Live download and upload speed',
              value: p.speed,
              onChanged: (v) => set(p.copyWith(speed: v)),
            ),
            if (p.speed) ...[
              KsSwitchRow(
                title: 'Speed chart',
                value: p.chart,
                onChanged: (v) => set(p.copyWith(chart: v)),
              ),
              KsSegmented<SpeedUnit>(
                label: 'Show speeds in',
                value: p.unit,
                help:
                    'Mbps is what internet plans use. MB/s is what '
                    'downloads show.',
                options: const [
                  (SpeedUnit.mbps, 'Mbps'),
                  (SpeedUnit.mbs, 'MB/s'),
                ],
                onChanged: (v) => set(p.copyWith(unit: v)),
              ),
            ],
            KsSwitchRow(
              title: 'Data used',
              subtitle: 'How much the internet has carried since it came up',
              value: p.usage,
              onChanged: (v) => set(p.copyWith(usage: v)),
            ),
            const SizedBox(height: 8),
            KsRow(
              title: 'Back to how it was',
              onTap: () async {
                if (await ksConfirm(
                  context,
                  title: 'Reset Home?',
                  body:
                      'Home goes back to the standard layout and sections. '
                      'Your shortcuts stay.',
                  action: 'Reset',
                )) {
                  set(const HomePrefs());
                }
              },
            ),
          ],
        );
      },
    );
  }

  static bool _hasModem(WidgetRef ref) {
    final caps = ref.watch(appStateProvider).capabilities;
    return ['noobwrt_modem', 'noobwrt_cellular'].any(
      (id) =>
          LuciModuleRegistry.instance.getModule(id)?.isAvailableOn(caps) ??
          false,
    );
  }

  static Widget _besideChips(
    BuildContext context,
    HomePrefs p,
    void Function(HomePrefs) set,
  ) {
    final chosen = p.besideItems;
    final full = chosen.length >= maxSignalItems;
    VoidCallback tap(SignalItem i) {
      if (chosen.contains(i)) {
        return () =>
            set(p.copyWith(besideItems: chosen.where((c) => c != i).toList()));
      }
      return full
          ? () => ksSay(context, 'Turn one off first.')
          : () => set(p.copyWith(besideItems: [...chosen, i]));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Show up to $maxSignalItems',
            style: KeystoneType.caption(context.ks.mu),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final i in SignalItem.values)
                KsChip(
                  _itemName(i),
                  many: true,
                  selected: chosen.contains(i),
                  onTap: tap(i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _itemName(SignalItem i) => switch (i) {
    SignalItem.type => 'Network type',
    SignalItem.operatorName => 'Operator',
    SignalItem.rsrp => 'RSRP',
    SignalItem.sinr => 'SINR',
    SignalItem.rsrq => 'RSRQ',
    SignalItem.bands => 'Bands',
    SignalItem.width => 'Total width',
  };

  static List<String> _pinnedNames(WidgetRef ref, List<String> macs) {
    final clients = ref.watch(appStateProvider).clients;
    return [
      for (final m in macs)
        clients
                .where((c) => c.macAddress.toLowerCase() == m)
                .firstOrNull
                ?.displayName ??
            m.toUpperCase(),
    ];
  }

  Future<void> _pickPinned(
    BuildContext context,
    WidgetRef ref,
    HomePrefs p,
  ) async {
    final clients = [...ref.read(appStateProvider).clients]
      ..sort((a, b) {
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return a.displayName.compareTo(b.displayName);
      });
    final chosen = [...p.pinned];
    final done = await ksSheet<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ks = ctx.ks;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pin devices', style: KeystoneType.sheetTitle(ks.tx)),
              const SizedBox(height: 4),
              Text(
                'Up to ${p.deviceCount}. They show on Home whenever they\'re '
                'online.',
                style: KeystoneType.secondary(ks.mu),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * .5,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in clients)
                      () {
                        final mac = c.macAddress.toLowerCase();
                        final on = chosen.contains(mac);
                        final full = chosen.length >= p.deviceCount;
                        final tap = on || !full
                            ? () => setState(
                                () => on ? chosen.remove(mac) : chosen.add(mac),
                              )
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: on ? ks.acSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: tap,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      ClientNamingHelper.getDeviceIcon(c),
                                      size: 20,
                                      color: tap == null ? ks.mu : ks.tx2,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            c.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: KeystoneType.body(
                                              tap == null ? ks.mu : ks.tx,
                                            ),
                                          ),
                                          Text(
                                            c.isConnected
                                                ? 'Online'
                                                : 'Offline',
                                            style: KeystoneType.caption(ks.mu),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      on
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: on
                                          ? ks.ac
                                          : (full ? ks.line : ks.mu),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }(),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    if (done == true) {
      await HomePrefsStore.instance.save(p.copyWith(pinned: chosen));
    }
  }
}
