// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_rpc.dart';
import 'alert_models.dart';
import 'alerts_client.dart';
import 'alerts_screen.dart';

const _kinds = [
  (AlertType.internet, 'Internet down', 'When it drops and comes back'),
  (AlertType.device, 'New device', 'A device joins for the first time'),
  (AlertType.data, 'Data use', 'Nearing the cap or the fair-use limit'),
  (AlertType.signal, 'Weak signal', 'Mobile signal below a level for 5 min'),
  (AlertType.restart, 'Restarts', 'The router or modem restarted'),
];

class AlertSettingsScreen extends StatefulWidget {
  const AlertSettingsScreen({
    super.key,
    required this.client,
    required this.phone,
    required this.settings,
  });

  final AlertsClient client;
  final AlertsPhone phone;
  final AlertSettings settings;

  @override
  State<AlertSettingsScreen> createState() => _AlertSettingsScreenState();
}

class _AlertSettingsScreenState extends State<AlertSettingsScreen> {
  final _form = GlobalKey<FormState>();
  late AlertSettings _s = widget.settings;
  late final _rsrp = TextEditingController(text: '${_s.rsrpBelow}');
  late final _warn = TextEditingController(text: '${_s.warnPct}');
  late final _fair = TextEditingController(text: '${_s.fairusePct}');
  bool _busy = false, _notify = false, _blocked = false, _working = false;
  Duration? _every;
  String? _error;

  @override
  void initState() {
    super.initState();
    _phoneState();
  }

  Future<void> _phoneState() async {
    final p = widget.phone;
    final key = await p.readKey(), every = await p.interval();
    final on = key != null && !p.store.muted && every != null;
    final allowed = on && await p.notificationsAllowed();
    if (!mounted) return;
    setState(() {
      _every = every;
      _notify = on;
      _blocked = on && !allowed;
    });
  }

  @override
  void dispose() {
    _rsrp.dispose();
    _warn.dispose();
    _fair.dispose();
    super.dispose();
  }

  String? Function(String?) _range(int lo, int hi, String words) => (v) {
    final n = int.tryParse(v?.trim() ?? '');
    return n == null || n < lo || n > hi ? words : null;
  };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.client.save(
        _s.copyWith(
          rsrpBelow: int.parse(_rsrp.text.trim()),
          warnPct: int.parse(_warn.text.trim()),
          fairusePct: int.parse(_fair.text.trim()),
        ),
      );
      if (mounted) await Navigator.of(context).maybePop();
    } catch (e) {
      _error = e is NoobRpcError
          ? "The router couldn't save that: ${e.message}"
          : "Couldn't reach the router. Check you're on its Wi-Fi.";
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setNotify(bool on) async {
    final p = widget.phone;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      if (on) {
        final allowed =
            await p.notificationsAllowed() || await p.askForNotifications();
        final info = await widget.client.info();
        await p.pairIfNeeded(widget.client, info?.keyId ?? '');
        await p.store.setMuted(false);
        if (await p.interval() == null) {
          await p.setInterval(const Duration(minutes: 15));
        }
        _blocked = !allowed;
      } else {
        await p.store.setMuted(true);
        _blocked = false;
      }
      _notify = on;
      _every = await p.interval();
    } catch (_) {
      _error =
          "Couldn't reach the router to set this up. Try again on its Wi-Fi.";
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _setEvery(Duration? d) async {
    await widget.phone.setInterval(d);
    if (mounted) setState(() => _every = d);
  }

  Future<void> _resetKey() async {
    final ok = await ksConfirm(
      context,
      title: 'Reset the alerts key?',
      body:
          'Other phones stop getting alerts until someone opens Keystone on '
          'them while signed in. Use this if a phone was lost.',
      action: 'Reset',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _working = true);
    try {
      await widget.client.resetKey();
      await widget.phone.writeKey(await widget.client.pair());
      if (mounted) {
        ksSay(context, 'New key made. This phone still gets alerts.');
      }
    } catch (_) {
      _error = "Couldn't reach the router. Check you're on its Wi-Fi.";
    }
    if (mounted) setState(() => _working = false);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    const modes = [
      (AlertMode.buzz, 'Notify'),
      (AlertMode.log, 'Log only'),
      (AlertMode.off, 'Off'),
    ];
    return KsFormPage(
      title: 'Alert settings',
      subtitle:
          "This phone's settings apply now. The rest is saved on the router, "
          'for every phone.',
      action: 'Save',
      busy: _busy,
      formKey: _form,
      onAction: _save,
      children: [
        if (_error != null) KsBanner(_error!, bad: true),
        const KsSection('This phone'),
        KsSwitchRow(
          title: 'Notify this phone',
          subtitle: 'Checks while this phone is on the router\'s Wi-Fi',
          value: _notify,
          busy: _working,
          onChanged: _setNotify,
        ),
        if (_blocked)
          KsNote(
            'Notifications are off for Keystone',
            action: 'Open settings',
            onAction: widget.phone.openNotificationSettings,
          ),
        KsSegmented<int>(
          label: 'Check in the background',
          value: _every?.inMinutes ?? 0,
          options: const [
            (0, 'Off'),
            (15, '15 min'),
            (30, '30 min'),
            (60, '1 hour'),
          ],
          onChanged: (m) => _setEvery(m == 0 ? null : Duration(minutes: m)),
          help: 'Android may wait longer when the phone is idle.',
        ),
        const KsSection('What to tell you about'),
        for (final (type, title, help) in _kinds)
          KsSegmented<AlertMode>(
            key: ValueKey('mode-${type.name}'),
            label: title,
            help: help,
            value: _s.modes[type]!,
            options: modes,
            onChanged: (m) => setState(() => _s = _s.copyWith(mode: (type, m))),
          ),
        const KsSection('Levels'),
        KsField(
          key: const ValueKey('rsrp'),
          label: 'Weak signal below, in dBm',
          controller: _rsrp,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          validator: _range(-140, -60, '-140 to -60'),
        ),
        KsField(
          label: 'Warn when this much of the cap is used, in %',
          controller: _warn,
          keyboardType: TextInputType.number,
          validator: _range(50, 99, '50 to 99'),
        ),
        KsField(
          label: 'Warn near the fair-use limit, in %',
          controller: _fair,
          keyboardType: TextInputType.number,
          validator: _range(50, 99, '50 to 99'),
        ),
        const KsSection('Key'),
        KsRow(
          title: 'Reset alerts key',
          subtitle: 'Stops alerts on every other phone',
          danger: true,
          onTap: _working ? null : _resetKey,
        ),
        const SizedBox(height: 8),
        Text(
          'Background checks never send your router password. They prove they '
          'have this key instead.',
          style: KeystoneType.caption(ks.mu),
        ),
      ],
    );
  }
}
