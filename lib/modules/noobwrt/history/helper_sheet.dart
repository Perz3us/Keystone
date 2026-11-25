// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../../../services/app_update.dart';
import '../cellular/preferred_towers.dart';
import '../noob_rpc.dart';
import 'fivegmodem_history.dart';
import 'helper_history.dart';
import 'helper_installer.dart';
import 'history_data.dart';
import 'history_merge.dart';
import 'history_screen.dart';

Future<void> showHelperSheet(BuildContext context, HelperInstaller helper) =>
    ksSheet<void>(context, (_) => _HelperSheet(helper));

class _HelperSheet extends StatefulWidget {
  const _HelperSheet(this.helper);
  final HelperInstaller helper;

  @override
  State<_HelperSheet> createState() => _HelperSheetState();
}

const _ubusWords = {
  'Invalid command',
  'Invalid argument',
  'Method not found',
  'Not found',
  'No data',
  'Timed out',
  'Not supported',
};

bool _denied(Object e) =>
    e is NoobRpcError &&
    (e.message == 'Permission denied' ||
        e.message == NoobRpcError.refused.message);

String _words(Object e) {
  if (_denied(e)) {
    return "Your router login can't do this. Sign in again or use an admin "
        'login.';
  }
  if (e is NoobRpcError && !_ubusWords.contains(e.message)) {
    return e.message;
  }
  return "Couldn't reach the router. Check you're on its Wi-Fi, then try again.";
}

class _HelperSheetState extends State<_HelperSheet> {
  bool _checking = true, _offline = false;
  String? _have, _routerError, _error, _working;
  HelperRelease? _rel, _stable;
  int? _keep, _max;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _routerError = null;
    });
    final h = widget.helper;
    final InstallState st;
    try {
      st = await h.status();
    } catch (e) {
      if (mounted) {
        setState(() {
          _checking = false;
          _routerError = _words(e);
        });
      }
      return;
    }
    if (st.phase != InstallPhase.idle &&
        (st.op == 'install' || st.op == 'remove')) {
      if (!mounted) return;
      setState(() => _checking = false);
      return _run(st.op);
    }
    final have = await h.installed();
    HelperRelease? rel;
    var offline = false;
    try {
      rel = await h.latestRelease();
    } catch (_) {
      offline = true;
    }
    HelperRelease? stable;
    if (have != null && isPreRelease(have)) {
      try {
        stable = await h.stableRelease();
      } catch (_) {}
    }
    final info = have == null ? null : await h.info();
    final keep = info?['keep_days'], max = info?['max_days'];
    if (!mounted) return;
    setState(() {
      _keep = keep is int ? keep : null;
      _max = max is int ? max : 30;
      _checking = false;
      _have = have;
      _rel = rel;
      _stable = stable;
      _offline = offline;
    });
  }

  Future<void> _run(String op) async {
    final say = ScaffoldMessenger.of(context);
    setState(() {
      _working = op;
      _error = null;
    });
    String? error;
    try {
      await switch (op) {
        'remove' => widget.helper.remove(),
        'stable' => widget.helper.goBack(),
        _ => widget.helper.install(),
      };
    } catch (e) {
      error = _words(e);
    }
    final done = switch (op) {
      'remove' => 'Signal history removed.',
      'stable' => 'Signal history is back on the stable version.',
      _ => 'Signal history installed.',
    };
    if (error == null || !mounted) {
      say.showSnackBar(SnackBar(content: Text(error ?? done)));
    }
    if (!mounted) return;
    setState(() {
      _working = null;
      _error = error;
    });
    await _check();
  }

  Future<void> _remove() async {
    final ok = await ksConfirm(
      context,
      title: 'Remove signal history?',
      body: 'History older than the last router restart will be lost.',
      action: 'Remove',
      danger: true,
    );
    if (ok && mounted) await _run('remove');
  }

  Future<void> _goBack(String to) async {
    final ok = await ksConfirm(
      context,
      title: 'Go back to $to?',
      body:
          'This replaces the beta with the stable version. Settings or '
          'history saved by the beta may be lost.',
      action: 'Go back',
    );
    if (ok && mounted) await _run('stable');
  }

  Future<void> _setKeep(int days) async {
    final cur = _keep;
    if (days == cur || _saving) return;
    if (cur != null && days < cur) {
      final ok = await ksConfirm(
        context,
        title: 'Keep only $days days?',
        body: 'Readings older than $days days are deleted now.',
        action: 'Keep $days days',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? error;
    try {
      await widget.helper.setKeep(days);
    } catch (e) {
      error = _words(e);
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
      if (error == null) _keep = days;
    });
  }

  String _space(int days) {
    final mb = (days * 150).clamp(1024, 4096) / 1024;
    final text = mb.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
    return 'Up to $text MB on the router';
  }

  List<Widget> _retention(KeystoneColors ks) {
    final keep = _keep;
    if (keep == null) return const [];
    final max = _max ?? 30;
    final days = {
      for (final d in const [7, 14, 30])
        if (d <= max) d,
      keep,
    }.toList()..sort();
    return [
      IgnorePointer(
        ignoring: _saving,
        child: KsSegmented<int>(
          label: 'Keep history for',
          value: keep,
          options: [for (final d in days) (d, '$d days')],
          onChanged: _setKeep,
        ),
      ),
      const SizedBox(height: 8),
      Text(_space(keep), style: KeystoneType.secondary(ks.mu)),
      const SizedBox(height: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Signal history', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 8),
        Text(
          'Adds a small background service to the router that keeps '
          '${_keep == null ? '7 days of ' : ''}'
          'signal, line ping and data history. About 4 KB. You can remove '
          'it here any time.',
          style: KeystoneType.body(ks.tx2),
        ),
        const SizedBox(height: 16),
        ..._state(ks),
      ],
    );
  }

  Widget _progress(KeystoneColors ks, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 10),
        Text(text, style: KeystoneType.secondary(ks.mu)),
      ],
    ),
  );

  Widget _retry() =>
      FilledButton(onPressed: _check, child: const Text('Try again'));

  List<Widget> _state(KeystoneColors ks) {
    if (_working != null) {
      return [
        _progress(
          ks,
          _working == 'remove'
              ? 'Removing from the router…'
              : 'Installing on the router. This can take a minute.',
        ),
      ];
    }
    if (_checking) return [_progress(ks, 'Checking the router…')];
    if (_routerError != null) {
      return [
        KsBanner(_routerError!, bad: true),
        const SizedBox(height: 16),
        _retry(),
      ];
    }
    final have = _have, rel = _rel, stable = _stable;
    return [
      if (have != null)
        Text(
          'Version $have${isPreRelease(have) ? ' (beta)' : ''}',
          style: KeystoneType.secondary(ks.mu),
        ),
      if (_error != null) KsBanner(_error!, bad: true),
      const SizedBox(height: 16),
      if (_offline) ...[
        Text("Couldn't reach GitHub", style: KeystoneType.body(ks.tx2)),
        const SizedBox(height: 12),
        _retry(),
      ] else if (have == null) ...[
        if (rel == null) ...[
          Text(
            "Signal history isn't published yet.",
            style: KeystoneType.body(ks.tx2),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: rel == null ? null : () => _run('install'),
          child: const Text('Install'),
        ),
      ] else if (rel != null && isNewerVersion(rel.version, have))
        FilledButton(
          onPressed: () => _run('install'),
          child: Text('Update to ${rel.version}'),
        ),
      if (stable != null) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => _goBack(stable.version),
          child: Text('Go back to stable ${stable.version}'),
        ),
      ],
      if (have != null) ..._retention(ks),
      if (have != null)
        TextButton(
          onPressed: _remove,
          child: Text('Remove', style: KeystoneType.body(ks.bad)),
        ),
    ];
  }
}

class HistoryRow extends StatefulWidget {
  const HistoryRow({super.key, required this.app, this.sources, this.helper});
  final AppState app;
  final List<HistorySource>? sources;
  final HelperInstaller? helper;

  @override
  State<HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<HistoryRow> {
  bool _busy = false;

  Future<void> _open() async {
    final app = widget.app;
    final sources =
        widget.sources ?? [FiveGModemHistory(app), HelperHistory(app)];
    final helper = widget.helper ?? HelperInstaller(app);
    setState(() => _busy = true);
    final now = DateTime.now();
    final first = loadHistory(
      sources,
      now.subtract(const Duration(hours: 24)),
      now,
    );
    var any = true;
    try {
      any = await first != null;
    } catch (e) {
      any = !_denied(e);
    }
    if (!mounted) return;
    if (!any) {
      setState(() => _busy = false);
      return showHelperSheet(context, helper);
    }
    var days = 7;
    try {
      final keep = (await helper.info())?['keep_days'];
      if (keep is int && keep > days) days = keep;
    } catch (_) {}
    if (!mounted) return;
    var reuse = true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HistoryScreen(
          load: (from, to) {
            if (reuse) {
              reuse = false;
              return first;
            }
            return loadHistory(sources, from, to);
          },
          towers: PreferredTowers(app),
          helper: helper,
          maxDays: days,
        ),
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => KsRow(
    title: 'History',
    subtitle: 'Signal, line ping and data over time',
    trailing: _busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : null,
    chevron: !_busy,
    onTap: _busy ? null : _open,
  );
}
