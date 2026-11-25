// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class BanWirelessClientDialog extends StatefulWidget {
  const BanWirelessClientDialog({
    super.key,
    required this.macAddress,
    required this.displayName,
    this.ipAddress,
    this.ssid,
    this.iface,
    this.isAlreadyBanned = false,
    required this.onBanConfirmed,
    this.onUnbanConfirmed,
  });

  final String macAddress;
  final String displayName;
  final String? ipAddress;
  final String? ssid;
  final String? iface;
  final bool isAlreadyBanned;

  final Future<void> Function(int banTimeSeconds) onBanConfirmed;
  final Future<void> Function()? onUnbanConfirmed;

  @override
  State<BanWirelessClientDialog> createState() =>
      _BanWirelessClientDialogState();
}

class _BanWirelessClientDialogState extends State<BanWirelessClientDialog> {
  static const _presets = [
    (300, '5 min'),
    (900, '15 min'),
    (3600, '1 hour'),
    (86400, 'A day'),
    (-1, 'Until…'),
  ];

  int _preset = 300;
  DateTime _until = DateTime.now().add(const Duration(minutes: 30));
  bool _busy = false;
  bool _isSelf = false;

  @override
  void initState() {
    super.initState();
    SelfDeviceGuard.isSelfDevice(widget.macAddress, widget.ipAddress).then((v) {
      if (mounted) setState(() => _isSelf = v);
    });
  }

  int get _seconds {
    if (_preset != -1) return _preset;
    final s = _until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  String _when(DateTime d) {
    final t = TimeOfDay.fromDateTime(d).format(context);
    final today = DateUtils.isSameDay(d, DateTime.now());
    return today
        ? 'Today at $t'
        : '${MaterialLocalizations.of(context).formatMediumDate(d)} at $t';
  }

  Future<void> _pickUntil() async {
    final now = DateTime.now();
    final start = _until.isAfter(now)
        ? _until
        : now.add(const Duration(minutes: 30));
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
    final picked = DateTime(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    if (picked.isBefore(now.add(const Duration(seconds: 30)))) {
      ksSay(context, 'Pick a time later than now.');
      return;
    }
    setState(() {
      _until = picked;
      _preset = -1;
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final name = widget.displayName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.isAlreadyBanned ? '$name is blocked' : 'Block $name',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 4),
        Text(
          widget.isAlreadyBanned
              ? 'Change how long, or let it back on.'
              : 'It can\'t join your Wi-Fi until the time is up.',
          style: KeystoneType.secondary(ks.mu),
        ),
        if (_isSelf)
          const KsBanner(
            'This is your phone. Blocking it also cuts Keystone off from '
            'the router.',
            bad: true,
          ),
        const SizedBox(height: 16),
        KsChips<int>(
          options: _presets,
          selected: _preset,
          onSelected: (v) =>
              v == -1 ? _pickUntil() : setState(() => _preset = v),
        ),
        if (_preset == -1)
          KsRow(title: 'Until', subtitle: _when(_until), onTap: _pickUntil),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy || _seconds < 30
              ? null
              : () => _run(() => widget.onBanConfirmed(_seconds)),
          style: FilledButton.styleFrom(
            backgroundColor: ks.bad,
            foregroundColor: ks.bg,
          ),
          child: Text(widget.isAlreadyBanned ? 'Change' : 'Block'),
        ),
        if (widget.isAlreadyBanned && widget.onUnbanConfirmed != null)
          TextButton(
            onPressed: _busy ? null : () => _run(widget.onUnbanConfirmed!),
            child: const Text('Let it back on'),
          ),
      ],
    );
  }
}
