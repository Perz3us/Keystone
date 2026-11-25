// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../../../services/app_update.dart';
import 'addons.dart';
import 'experimental.dart';

class AddonsScreen extends StatefulWidget {
  const AddonsScreen({super.key, required this.app, this.addons});
  final AppState app;
  final List<Addon>? addons;

  @override
  State<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends State<AddonsScreen> {
  late final List<Addon> _addons = widget.addons ?? addonsFor(widget.app);
  List<AddonStatus>? _status;
  bool? _beta;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    loadExperimental().then((v) {
      if (mounted) setState(() => _beta = v);
    });
    _check();
  }

  Future<void> _check() async {
    final run = ++_run;
    final id = widget.app.selectedRouter?.id;
    final all = await Future.wait([
      for (final a in _addons) addonStatus(a.helper),
    ]);
    if (run != _run) return;
    noteAddons(id, all);
    if (mounted) setState(() => _status = all);
  }

  Future<void> _open(Addon a) async {
    await a.open(context, a.helper);
    if (mounted) await _check();
  }

  Future<void> _setBeta(bool on) async {
    if (on && await ksSheet<bool>(context, _agree) != true) return;
    await saveExperimental(on);
    if (!mounted) return;
    setState(() {
      _beta = on;
      _status = null;
    });
    await _check();
  }

  Widget _agree(BuildContext c) {
    final ks = c.ks;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Show beta add-ons?', style: KeystoneType.sheetTitle(ks.tx)),
          for (final t in const [
            'You will see add-ons and updates before they are finished.',
            'Betas can have bugs, use more of the router, or lose the history '
                'they saved. They run with full access to the router.',
            'Nothing installs by itself. You can go back to the stable version '
                "from the add-on's page.",
          ]) ...[
            const SizedBox(height: 12),
            Text(t, style: KeystoneType.body(ks.tx2)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('I understand, show betas'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('Cancel', style: KeystoneType.body(ks.tx)),
          ),
        ],
      ),
    );
  }

  String _line(Addon a, AddonStatus s) {
    final have = s.have, rel = s.release;
    final beta = rel != null && isPreRelease(rel.version);
    if (s.update) {
      return '${beta ? 'Beta update' : 'Update'} available · '
          '$have → ${rel!.version}';
    }
    if (have == null) {
      return '${a.about} · ${beta ? 'Beta, not installed' : 'Not installed'}';
    }
    return [
      'Installed $have',
      if (isPreRelease(have)) 'beta',
      if (s.offline) "couldn't check for updates",
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final status = _status, beta = _beta;
    return KsPage(
      title: 'Add-ons',
      subtitle: 'Extra features for this router',
      back: 'More',
      onRefresh: _check,
      children: [
        const SizedBox(height: 8),
        if (status == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final (i, s) in status.indexed)
            if (s.listed)
              KsRow(
                title: _addons[i].name,
                subtitle: _line(_addons[i], s),
                subtitleColor: s.update ? ks.ac : null,
                onTap: () => _open(_addons[i]),
              ),
          if (!status.any((s) => s.listed)) const KsNote('No add-ons yet.'),
        ],
        const SizedBox(height: 24),
        KsSwitchRow(
          title: 'Show beta add-ons',
          subtitle: 'Try new add-ons and updates early',
          value: beta ?? false,
          onChanged: beta == null ? null : _setBeta,
        ),
      ],
    );
  }
}
