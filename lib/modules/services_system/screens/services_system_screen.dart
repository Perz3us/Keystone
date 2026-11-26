// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/services_system/restart_preset.dart';
import 'package:yet_another_luci_app/modules/services_system/screens/restart_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/utils/internet_link.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/ddns_info.dart';
import '../models/services_system_info.dart';
import 'services_forms.dart';

const _days = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String cronWords(String expr) {
  final p = expr.trim().split(RegExp(r'\s+'));
  if (p.length != 5) return expr;
  final [m, h, dom, mon, dow] = p;
  final mi = int.tryParse(m), hi = int.tryParse(h);
  String at() =>
      'at ${hi.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
  if (m.startsWith('*/') &&
      h == '*' &&
      dom == '*' &&
      mon == '*' &&
      dow == '*') {
    return 'Every ${m.substring(2)} minutes';
  }
  if (m == '*' && h == '*' && dom == '*' && mon == '*' && dow == '*') {
    return 'Every minute';
  }
  if (mi != null && h == '*' && dom == '*' && mon == '*' && dow == '*') {
    return mi == 0 ? 'Every hour' : 'Every hour at :${m.padLeft(2, '0')}';
  }
  if (mi == null || hi == null || mon != '*') return expr;
  if (dom == '*' && dow == '*') return 'Every day ${at()}';
  if (dom == '*' && dow == '1-5') return 'Weekdays ${at()}';
  final di = int.tryParse(dow);
  if (dom == '*' && di != null && di >= 0 && di <= 7) {
    return 'Every ${_days[di]} ${at()}';
  }
  if (dow == '*' && dom == '1') return 'First of the month ${at()}';
  return expr;
}

String serviceLine(InitScript s) => [
  s.isRunning ? 'Running' : 'Stopped',
  s.isEnabled ? 'starts with the router' : "doesn't start by itself",
].join(' · ');

class ServicesSystemScreen extends ConsumerWidget {
  const ServicesSystemScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appStateProvider);
    final o = ServicesSystemOverview.fromDashboardData(app.dashboardData);
    final ddns = DdnsOverview.fromDashboardData(app.dashboardData);
    final running = o.initScripts.where((s) => s.isRunning).length;
    final jobs = o.cronJobs.where((j) => !j.isCommented).length;
    void open(Widget page) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));

    return KsPage(
      title: 'Services',
      subtitle: 'What runs on the router, and when',
      onRefresh: () => app.fetchDashboardData(force: true),
      children: [
        KsRow(
          title: 'Router services',
          subtitle: '$running running of ${o.initScripts.length}',
          onTap: () => open(const ServiceListScreen()),
        ),
        KsRow(
          title: 'Scheduled tasks',
          subtitle: o.cronJobs.isEmpty
              ? 'None'
              : [
                  '$jobs on',
                  if (o.cronJobs.length > jobs)
                    '${o.cronJobs.length - jobs} off',
                ].join(' · '),
          onTap: () => open(const CronScreen()),
        ),
        KsRow(
          title: 'Dynamic DNS',
          subtitle: !ddns.isInstalled
              ? 'Not installed. Keeps a web address pointing at your router.'
              : !ddns.isGlobalEnabled
              ? 'Off'
              : '${ddns.instances.where((i) => i.enabled).length} on',
          onTap: () => open(const DdnsScreen()),
        ),
      ],
    );
  }
}

class ServiceListScreen extends ConsumerStatefulWidget {
  const ServiceListScreen({super.key});

  @override
  ConsumerState<ServiceListScreen> createState() => _ServiceListScreenState();
}

class _ServiceListScreenState extends ConsumerState<ServiceListScreen> {
  String _q = '';
  final _pending = <String>{};

  Future<void> _act(InitScript s, String action) async {
    final app = ref.read(appStateProvider);
    if (action == 'stop' || action == 'disable') {
      final ok = await ksConfirm(
        context,
        title: action == 'stop' ? 'Stop ${s.name}?' : 'Keep ${s.name} off?',
        body: action == 'stop'
            ? 'Anything that needs it stops working until it starts again.'
            : "It won't start the next time the router starts.",
        action: action == 'stop' ? 'Stop' : 'Keep off',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    setState(() => _pending.add(s.name));
    final good = await app.manageServiceAction(
      s.name,
      action,
      context: context,
    );
    if (good) await app.fetchDashboardData(force: true);
    if (!mounted) return;
    setState(() => _pending.remove(s.name));
    if (!good) ksSay(context, "The router didn't do that.");
  }

  void _sheet(InitScript s) => ksSheet<void>(context, (c) {
    final ks = c.ks;
    void go(String a) {
      Navigator.pop(c);
      _act(s, a);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(s.name, style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text(serviceLine(s), style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 12),
        if (s.isRunning) ...[
          KsRow(title: 'Restart', chevron: false, onTap: () => go('restart')),
          KsRow(
            title: 'Stop',
            danger: true,
            chevron: false,
            onTap: () => go('stop'),
          ),
        ] else
          KsRow(title: 'Start', chevron: false, onTap: () => go('start')),
        KsRow(
          title: s.isEnabled
              ? "Don't start with the router"
              : 'Start with the router',
          chevron: false,
          onTap: () => go(s.isEnabled ? 'disable' : 'enable'),
        ),
      ],
    );
  });

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appStateProvider);
    final all = ServicesSystemOverview.fromDashboardData(
      app.dashboardData,
    ).initScripts;
    final shown =
        all
            .where((s) => s.name.toLowerCase().contains(_q.toLowerCase()))
            .toList()
          ..sort((a, b) {
            if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
            return a.name.compareTo(b.name);
          });
    return KsPage(
      title: 'Router services',
      back: 'Services',
      subtitle: 'Programs that run in the background',
      onRefresh: () => app.fetchDashboardData(force: true),
      children: [
        KsSearchField(
          hint: 'Find a service',
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 8),
        for (final s in shown)
          KsRow(
            leading: KsDot(s.isRunning ? context.ks.ok : context.ks.line),
            title: s.name,
            subtitle: serviceLine(s),
            chevron: false,
            onTap: () => _sheet(s),
            trailing: _pending.contains(s.name)
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        if (shown.isEmpty)
          Text('Nothing matches.', style: KeystoneType.body(context.ks.mu)),
      ],
    );
  }
}

class CronScreen extends ConsumerStatefulWidget {
  const CronScreen({super.key});

  @override
  ConsumerState<CronScreen> createState() => _CronScreenState();
}

class _CronScreenState extends ConsumerState<CronScreen> {
  bool _busy = false;

  List<CronJob> _jobs() => ServicesSystemOverview.fromDashboardData(
    ref.read(appStateProvider).dashboardData,
  ).cronJobs;

  Future<void> _write(List<CronJob> jobs) async {
    setState(() => _busy = true);
    final app = ref.read(appStateProvider);
    final good = await app.saveCronJobs([
      for (final j in jobs) j.rawLine,
    ], context: context);
    if (good) await app.fetchDashboardData(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!good) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  Future<void> _edit([int? index]) async {
    final jobs = _jobs();
    final old = index == null ? null : jobs[index];
    final job = await ksSheet<CronJob>(
      context,
      (c) => _CronForm(existing: old),
    );
    if (job == null || !mounted) return;
    await _write([
      for (final (i, j) in jobs.indexed) i == index ? job : j,
      if (index == null) job,
    ]);
  }

  Future<void> _restart() async {
    final app = ref.read(appStateProvider);
    var guarded = false;
    try {
      await noobCall(app, 'file', 'stat', {'path': restartGuard});
      guarded = true;
    } catch (_) {}
    if (!mounted) return;
    final jobs = _jobs();
    final current = jobs.where((j) => isRestartPreset(j.rawLine)).firstOrNull;
    await ksSheet<void>(
      context,
      (c) => RestartForm(
        guarded: guarded,
        current: current?.rawLine,
        onSave: (line) async {
          await _write([
            for (final j in jobs)
              if (!isRestartPreset(j.rawLine)) j,
            if (line != null) CronJob.fromCronLine(line),
          ]);
          if (c.mounted) Navigator.of(c).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final jobs = ServicesSystemOverview.fromDashboardData(
      app.dashboardData,
    ).cronJobs;
    final restart = jobs
        .map((j) => j.isCommented ? null : readRestartPreset(j.rawLine))
        .nonNulls
        .firstOrNull;
    return KsPage(
      title: 'Scheduled tasks',
      back: 'Services',
      subtitle: 'Commands the router runs on a timer',
      onRefresh: () => app.fetchDashboardData(force: true),
      children: [
        if (jobs.isEmpty)
          Text(
            'None yet. For example, restart the Wi-Fi every night at '
            '${const TimeOfDay(hour: 4, minute: 0).format(context)}.',
            style: KeystoneType.body(ks.mu),
          ),
        for (final (i, j) in jobs.indexed)
          if (!isRestartPreset(j.rawLine))
            KsRow(
              title: cronWords(j.expression),
              subtitle: j.command,
              subtitleLines: 2,
              chevron: false,
              onTap: _busy ? null : () => _edit(i),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: !j.isCommented,
                    onChanged: _busy
                        ? null
                        : (on) => _write([
                            for (final (k, x) in jobs.indexed)
                              k == i ? x.copyWith(isCommented: !on) : x,
                          ]),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: Icon(Icons.close_rounded, color: ks.mu),
                    onPressed: _busy
                        ? null
                        : () async {
                            final ok = await ksConfirm(
                              context,
                              title: 'Remove this task?',
                              body: j.command,
                              action: 'Remove',
                              danger: true,
                            );
                            if (ok && mounted) {
                              await _write([
                                for (final (k, x) in jobs.indexed)
                                  if (k != i) x,
                              ]);
                            }
                          },
                  ),
                ],
              ),
            ),
        KsRow(
          title: 'Restart every night',
          subtitle: restart == null
              ? 'Off'
              : '${restart.target == RestartTarget.modem ? 'Modem' : 'Router'} at '
                    '${TimeOfDay(hour: restart.hour, minute: restart.minute).format(context)}',
          leading: Icon(Icons.restart_alt_rounded, color: ks.mu),
          onTap: _busy ? null : _restart,
        ),
        KsRow(
          title: 'Add a task',
          leading: Icon(Icons.add_rounded, color: ks.mu),
          onTap: _busy ? null : () => _edit(),
        ),
      ],
    );
  }
}

class _CronForm extends StatefulWidget {
  const _CronForm({this.existing});
  final CronJob? existing;

  @override
  State<_CronForm> createState() => _CronFormState();
}

class _CronFormState extends State<_CronForm> {
  late final _expr = TextEditingController(
    text: widget.existing?.expression ?? '0 4 * * *',
  );
  late final _cmd = TextEditingController(text: widget.existing?.command ?? '');
  String? _err;

  @override
  void dispose() {
    _expr.dispose();
    _cmd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final presets = kCronPresets.where((p) => p.expression.isNotEmpty);
    final preset = presets
        .where((p) => p.expression == _expr.text.trim())
        .firstOrNull;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? 'Add a task' : 'Change the task',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in presets)
              ChoiceChip(
                label: Text(cronWords(p.expression)),
                selected: preset == p,
                onSelected: (_) => setState(() {
                  _expr.text = p.expression;
                  _err = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        KsField(
          label: 'When (cron)',
          controller: _expr,
          help: preset == null ? cronWords(_expr.text) : null,
          onChanged: (_) => setState(() => _err = null),
        ),
        KsField(
          label: 'Command',
          controller: _cmd,
          hint: 'wifi reload',
          onChanged: (_) => setState(() {}),
        ),
        if (_err != null) KsBanner(_err!, bad: true),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _cmd.text.trim().isEmpty
              ? null
              : () {
                  final e = CronValidator.validateExpression(_expr.text);
                  if (e != null) {
                    setState(() => _err = e);
                    return;
                  }
                  final expr = _expr.text
                      .trim()
                      .split(RegExp(r'\s+'))
                      .join(' ');
                  final cmd = _cmd.text.trim();
                  final off = widget.existing?.isCommented ?? false;
                  Navigator.pop(
                    context,
                    CronJob.fromCronLine('${off ? '# ' : ''}$expr $cmd'),
                  );
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class DdnsScreen extends ConsumerStatefulWidget {
  const DdnsScreen({super.key});

  @override
  ConsumerState<DdnsScreen> createState() => _DdnsScreenState();
}

class _DdnsScreenState extends ConsumerState<DdnsScreen> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() work) async {
    setState(() => _busy = true);
    bool good;
    try {
      good = await work();
    } catch (_) {
      good = false;
    }
    final app = ref.read(appStateProvider);
    if (good) await app.fetchDashboardData(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!good) {
      ksSay(context, "The router didn't take that. Nothing was changed.");
    }
  }

  void _edit([DdnsInstance? i]) => ksFormRoute<void>(
    context,
    DdnsEditDialog(
      existingInstance: i,
      links: dumpInterfaces(
        ref.read(appStateProvider).dashboardData?['interfaceDump'],
      ),
      onSave: (d) async {
        final app = ref.read(appStateProvider);
        final ok = await app.saveDdnsInstance(d);
        if (ok) await app.fetchDashboardData(force: true);
        return ok;
      },
      onTest: (d) => ref.read(appStateProvider).testDdnsConfiguration(d),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final d = DdnsOverview.fromDashboardData(app.dashboardData);
    return KsPage(
      title: 'Dynamic DNS',
      back: 'Services',
      subtitle: 'A web address that follows your changing internet address',
      onRefresh: () => app.fetchDashboardData(force: true),
      children: [
        if (!d.isInstalled) ...[
          Text(
            'Mobile and home internet addresses change now and then. Dynamic '
            'DNS tells a name service (like DuckDNS or No-IP) each new one, '
            'so a name such as myhome.duckdns.org always reaches you.',
            style: KeystoneType.body(ks.tx2),
          ),
          const SizedBox(height: 8),
          Text(
            'It needs a small add-on (ddns-scripts).',
            style: KeystoneType.secondary(ks.mu),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(() async {
                    final r = await app.managePackageResult(
                      packageName: 'ddns-scripts',
                      action: 'install',
                    );
                    return r.isSuccess;
                  }),
            child: Text(_busy ? 'Installing…' : 'Install it'),
          ),
        ] else ...[
          KsSwitchRow(
            title: 'Dynamic DNS',
            subtitle: d.isGlobalEnabled ? 'On' : 'Off',
            value: d.isGlobalEnabled,
            busy: _busy,
            onChanged: (v) => _run(() => app.toggleGlobalDdns(v)),
          ),
          const KsSection('Names'),
          if (d.instances.isEmpty)
            Text('None yet.', style: KeystoneType.body(ks.mu)),
          for (final i in d.instances)
            KsRow(
              title: i.domain.isEmpty ? i.name : i.domain,
              subtitle: [
                i.serviceName.isEmpty ? i.name : i.serviceName,
                i.enabled ? (i.statusStr ?? 'On') : 'Off',
                if (i.lastUpdate case final t? when t.isNotEmpty) 'updated $t',
              ].join(' · '),
              onTap: _busy ? null : () => _edit(i),
              chevron: false,
              trailing: IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.close_rounded, color: ks.mu),
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await ksConfirm(
                          context,
                          title:
                              'Remove ${i.domain.isEmpty ? i.name : i.domain}?',
                          body:
                              "The name stops following this router's address.",
                          action: 'Remove',
                          danger: true,
                        );
                        if (ok && mounted) {
                          await _run(() => app.deleteDdnsInstance(i.name));
                        }
                      },
              ),
            ),
          KsRow(
            title: 'Add a name',
            leading: Icon(Icons.add_rounded, color: ks.mu),
            onTap: _busy ? null : () => _edit(),
          ),
        ],
      ],
    );
  }
}
