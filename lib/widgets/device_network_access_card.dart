// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class DeviceNetworkAccessCard extends ConsumerStatefulWidget {
  final Client client;

  const DeviceNetworkAccessCard({super.key, required this.client});

  static Future<void> showAsBottomSheet(
    BuildContext context, {
    required Client client,
  }) => ksSheet<void>(context, (_) => DeviceNetworkAccessCard(client: client));

  @override
  ConsumerState<DeviceNetworkAccessCard> createState() =>
      _DeviceNetworkAccessCardState();
}

class _DeviceNetworkAccessCardState
    extends ConsumerState<DeviceNetworkAccessCard> {
  bool _busy = false;

  static String _left(DateTime until) {
    final d = until.difference(DateTime.now());
    if (d.isNegative) return 'now';
    if (d.inHours >= 24) return '${d.inDays}d ${d.inHours % 24}h';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m';
    return '${d.inMinutes}m';
  }

  Future<bool> _safeToBlock(String what) =>
      SelfDeviceGuard.checkSelfActionGuardrail(
        context,
        actionName: what,
        targetMac: widget.client.macAddress,
        targetIp: widget.client.ipAddress,
        targetHostname: widget.client.displayName,
      );

  Future<void> _apply(NetworkAccessPolicy policy) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await ref
          .read(appStateProvider)
          .setDeviceNetworkAccessPolicy(
            policy: policy,
            context: mounted ? context : null,
          );
      if (!mounted) return;
      final name = widget.client.displayName;
      ksSay(
        context,
        !ok
            ? 'The router didn\'t change that. Nothing was changed.'
            : policy.isEffectivelyBlocked
            ? '$name is off the internet.'
            : '$name is back on the internet.',
      );
    } catch (_) {
      if (mounted) ksSay(context, 'Couldn\'t reach the router. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _until(NetworkAccessPolicy policy) async {
    final now = DateTime.now();
    final start = now.add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null || !mounted) return;
    final at = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    if (at.isBefore(now)) {
      ksSay(context, 'Pick a time later than now.');
      return;
    }
    await _apply(policy.copyWith(scheduleExpiry: at));
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final c = widget.client;
    final p = app.getDeviceNetworkAccessPolicy(c.macAddress);
    final ipv6 = app.capabilities?.supportsIpv6InternetFirewall ?? false;
    final blocked = p.isEffectivelyBlocked;

    final state = blocked
        ? (p.scheduleExpiry == null
              ? 'Off the internet until you turn it back on.'
              : p.isExpired
              ? 'The block has ended.'
              : 'Off the internet. Back on in ${_left(p.scheduleExpiry!)}.')
        : p.isIpv4OnlyBlocked
        ? 'IPv4 internet is off. IPv6 still works.'
        : p.isIpv6OnlyBlocked
        ? 'IPv6 internet is off. IPv4 still works.'
        : 'On the internet. It can still reach devices at home either way.';

    final hours = [
      (0, 'Always'),
      (1, '1 hour'),
      (2, '2 hours'),
      (8, '8 hours'),
      (24, 'A day'),
      (-1, 'Until…'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Internet for ${c.displayName}',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 4),
        Text(state, style: KeystoneType.secondary(blocked ? ks.warnTx : ks.mu)),
        if (c.isDumbApClient)
          KsNote(
            'It joins through ${c.apName ?? 'another access point'}, so '
            'this router does the blocking.',
          ),
        const SizedBox(height: 8),
        KsSwitchRow(
          title: 'Internet',
          value: p.effectiveInternetAccess,
          busy: _busy,
          onChanged: _busy
              ? null
              : (on) async {
                  if (!on && !await _safeToBlock('Block Internet Access')) {
                    return;
                  }
                  await _apply(
                    on
                        ? NetworkAccessPolicy.unrestricted(c.macAddress)
                        : NetworkAccessPolicy.blocked(c.macAddress),
                  );
                },
        ),
        if (ipv6 && p.effectiveInternetAccess) ...[
          KsSwitchRow(
            title: 'IPv4 internet',
            value: p.effectiveIpv4Access,
            onChanged: _busy
                ? null
                : (on) async {
                    if (!on &&
                        !p.ipv6Access &&
                        !await _safeToBlock('Block IPv4 Internet')) {
                      return;
                    }
                    await _apply(p.copyWith(ipv4Access: on));
                  },
          ),
          KsSwitchRow(
            title: 'IPv6 internet',
            value: p.effectiveIpv6Access,
            onChanged: _busy
                ? null
                : (on) async {
                    if (!on &&
                        !p.ipv4Access &&
                        !await _safeToBlock('Block IPv6 Internet')) {
                      return;
                    }
                    await _apply(p.copyWith(ipv6Access: on));
                  },
          ),
        ],
        if (blocked) ...[
          const KsSection('Keep it off for'),
          KsChips<int>(
            options: hours,
            selected: p.scheduleExpiry == null ? 0 : -2,
            onSelected: (h) => switch (h) {
              0 => _apply(p.copyWith(clearScheduleExpiry: true)),
              -1 => _until(p),
              _ => _apply(
                p.copyWith(
                  scheduleExpiry: DateTime.now().add(Duration(hours: h)),
                ),
              ),
            },
          ),
        ] else ...[
          const KsSection('Pause it for'),
          KsChips<int>(
            options: hours.where((o) => o.$1 != 0).toList(),
            selected: -2,
            onSelected: (h) async {
              if (!await _safeToBlock('Block Internet Access')) return;
              final off = NetworkAccessPolicy.blocked(c.macAddress);
              await (h == -1
                  ? _until(off)
                  : _apply(
                      off.copyWith(
                        scheduleExpiry: DateTime.now().add(Duration(hours: h)),
                      ),
                    ));
            },
          ),
        ],
      ],
    );
  }
}
