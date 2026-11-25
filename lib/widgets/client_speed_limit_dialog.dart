// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class ClientSpeedLimitDialog extends ConsumerStatefulWidget {
  final Client client;
  final ClientSpeedLimit? initialLimit;
  final String? routerId;

  const ClientSpeedLimitDialog({
    super.key,
    required this.client,
    this.initialLimit,
    this.routerId,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Client client,
    ClientSpeedLimit? initialLimit,
    String? routerId,
  }) => ksSheet<bool>(
    context,
    (_) => ClientSpeedLimitDialog(
      client: client,
      initialLimit: initialLimit,
      routerId: routerId,
    ),
  );

  @override
  ConsumerState<ClientSpeedLimitDialog> createState() =>
      _ClientSpeedLimitDialogState();
}

class _ClientSpeedLimitDialogState
    extends ConsumerState<ClientSpeedLimitDialog> {
  late final TextEditingController _down;
  late final TextEditingController _up;
  String _downUnit = 'Mbps';
  String _upUnit = 'Mbps';
  bool _saving = false;
  bool _hadLimit = false;
  String? _error;

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void initState() {
    super.initState();
    final existing =
        widget.initialLimit ??
        ref
            .read(appStateProvider)
            .getClientSpeedLimit(widget.client.macAddress);
    _hadLimit = existing != null && existing.isEffectivelyRestricted;
    if (_hadLimit) {
      _downUnit = existing!.downloadUnit;
      _upUnit = existing.uploadUnit;
      _down = TextEditingController(
        text: existing.downloadValue > 0 ? _num(existing.downloadValue) : '',
      );
      _up = TextEditingController(
        text: existing.uploadValue > 0 ? _num(existing.uploadValue) : '',
      );
    } else {
      _down = TextEditingController(text: '10');
      _up = TextEditingController(text: '2');
    }
  }

  @override
  void dispose() {
    _down.dispose();
    _up.dispose();
    super.dispose();
  }

  double _value(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    final down = _value(_down), up = _value(_up);
    if (down <= 0 && up <= 0) {
      setState(() => _error = 'Set a download or upload speed.');
      return;
    }
    final mac = ClientNamingHelper.normalizeMac(widget.client.macAddress);
    if (await SelfDeviceGuard.isSelfDevice(mac)) {
      if (!mounted) return;
      final go = await ksConfirm(
        context,
        title: 'This is your phone',
        body: 'Limiting it also slows Keystone\'s connection to the router.',
        action: 'Limit anyway',
      );
      if (!go) return;
    }
    if (!mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final limit = ClientSpeedLimit(
      targetMac: mac,
      ipAddress: widget.client.ipAddress,
      ipv6Addresses: widget.client.ipv6Addresses ?? const [],
      downloadValue: down,
      downloadUnit: _downUnit,
      uploadValue: up,
      uploadUnit: _upUnit,
      enabled: true,
      hostname: widget.client.displayName,
      updatedAt: DateTime.now(),
    );
    final ok = await ref
        .read(appStateProvider)
        .setClientSpeedLimit(
          speedLimit: limit,
          routerId: widget.routerId,
          context: mounted ? context : null,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ksSay(context, '${widget.client.displayName} is limited now.');
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'The router didn\'t save that. Try again.');
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    final ok = await ref
        .read(appStateProvider)
        .removeClientSpeedLimit(
          widget.client.macAddress,
          routerId: widget.routerId,
          context: mounted ? context : null,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      ksSay(context, '${widget.client.displayName} has full speed again.');
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'The router didn\'t remove it. Try again.');
    }
  }

  Widget _speed(
    String label,
    TextEditingController c,
    String unit,
    ValueChanged<String> setUnit,
  ) => KsField(
    label: label,
    controller: c,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    hint: 'No limit',
    onChanged: (_) => setState(() => _error = null),
    suffix: TextButton(
      onPressed: () => setUnit(unit == 'Mbps' ? 'Kbps' : 'Mbps'),
      child: Text(unit),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Limit ${widget.client.displayName}',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 4),
        Text(
          'Keeps this device from slowing the others. Leave a box empty '
          'for no limit. Tap the unit to change it.',
          style: KeystoneType.secondary(ks.mu),
        ),
        _speed(
          'Download',
          _down,
          _downUnit,
          (u) => setState(() => _downUnit = u),
        ),
        _speed('Upload', _up, _upUnit, (u) => setState(() => _upUnit = u)),
        if (_error != null) KsBanner(_error!, bad: true),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Limit speed'),
        ),
        if (_hadLimit)
          TextButton(
            onPressed: _saving ? null : _remove,
            child: Text('Remove the limit', style: KeystoneType.body(ks.bad)),
          ),
      ],
    );
  }
}
