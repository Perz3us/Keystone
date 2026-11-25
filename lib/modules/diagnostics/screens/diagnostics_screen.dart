// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../../network_diagnostic/controllers/network_diagnostic_controller.dart';
import '../../network_diagnostic/models/diagnostic_status.dart';
import '../../network_diagnostic/models/network_diagnostic_report.dart';
import '../controllers/diagnostics_controller.dart';
import '../controllers/dns_benchmark_controller.dart';
import '../models/dns_benchmark_models.dart';
import '../models/ping_result.dart';
import '../models/traceroute_result.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final check = ref.watch(networkDiagnosticControllerProvider);
    final checker = ref.read(networkDiagnosticControllerProvider.notifier);
    final d = ref.read(diagnosticsControllerProvider.notifier);
    void push(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return KsPage(
      title: 'Troubleshoot',
      subtitle: 'Find out why the internet is slow or down',
      children: [
        CheckView(
          running: check.isAnalyzing,
          progress: check.currentProgress,
          step: check.currentStepTitle,
          report: check.report,
          error: check.errorMessage,
          onRun: checker.runDiagnostics,
          onCancel: checker.cancel,
        ),
        const KsSection('Tools'),
        KsRow(
          title: 'Ping',
          subtitle: 'See if an address answers, and how fast',
          onTap: () => ksSheet<void>(context, (_) => const _PingSheet()),
        ),
        KsRow(
          title: 'Trace the route',
          subtitle: 'Every stop on the way to an address',
          onTap: () => ksSheet<void>(context, (_) => const _TraceSheet()),
        ),
        KsRow(
          title: 'Look up a name',
          subtitle: 'What address a website name points to',
          onTap: () => ksSheet<void>(context, (_) => const _LookupSheet()),
        ),
        KsRow(
          title: 'Fastest DNS',
          subtitle: 'Compare name lookup services',
          onTap: () => push(const DnsSpeedScreen()),
        ),
        KsRow(
          title: 'Routes and connections',
          subtitle: 'Where traffic goes, and who the router can see',
          onTap: () => push(const NetworkTablesScreen()),
        ),
        KsRow(
          title: 'Clear the name cache',
          subtitle: 'When a website moved and still opens the old place',
          onTap: () async {
            if (!await ksConfirm(
              context,
              title: 'Clear the name cache?',
              body:
                  'The router forgets the names it remembered and looks '
                  'them up again. Nothing else changes.',
              action: 'Clear',
            )) {
              return;
            }
            final r = await d.flushDns();
            if (context.mounted) {
              ksSay(
                context,
                r == null
                    ? "That didn't work."
                    : r.isSuccess
                    ? 'Cleared.'
                    : "That didn't work: ${r.message}",
              );
            }
          },
        ),
        KsRow(
          title: 'Copy a report',
          subtitle:
              "For whoever helps you. It includes the router's log, so read "
              'it before you send it.',
          onTap: () async {
            final r = await d.generateReport();
            if (r == null) {
              if (context.mounted) ksSay(context, "Couldn't make a report.");
              return;
            }
            await Clipboard.setData(
              ClipboardData(text: r.generateMarkdown(redact: true)),
            );
            if (context.mounted) ksSay(context, 'Report copied.');
          },
        ),
      ],
    );
  }
}

String statusWord(DiagnosticStatus s) => switch (s) {
  DiagnosticStatus.healthy => 'Fine',
  DiagnosticStatus.degraded => 'Slow',
  DiagnosticStatus.failureConfirmed => 'Broken',
  DiagnosticStatus.suspected => 'Maybe a problem',
  DiagnosticStatus.inconclusive => 'Not sure',
  DiagnosticStatus.notTested => 'Not checked',
  DiagnosticStatus.unsupported => "Can't check here",
  DiagnosticStatus.notApplicable => 'Not needed',
};

Color statusColor(KeystoneColors ks, DiagnosticStatus s) => switch (s) {
  DiagnosticStatus.healthy => ks.ok,
  DiagnosticStatus.failureConfirmed => ks.bad,
  DiagnosticStatus.degraded || DiagnosticStatus.suspected => ks.warn,
  _ => ks.line,
};

const _plain = <String, (String, String)>{
  'router_management_api': (
    'Keystone can reach the router',
    'Signed in and answering.',
  ),
  'wan_interface_state': ("The router's internet connection", 'Connected.'),
  'default_route_verification': (
    'A way out to the internet',
    'The router knows where to send traffic.',
  ),
  'gateway_reachability': ("Your provider's equipment", 'It answers.'),
  'dns_resolution': ('Website names', 'Names turn into addresses.'),
  'ipv4_external_reachability': ('Reaching the internet', 'Websites load.'),
  'ipv6_external_reachability': ('Reaching the internet over IPv6', 'Works.'),
  'client_forwarding_policy': (
    'Devices can get out',
    'The firewall lets them through.',
  ),
  'path_mtu_check': ('Packet size', "Big downloads aren't being broken up."),
};

(String, String) plainCheck(String id, DiagnosticStatus s, String engineLine) {
  final p = _plain[id];
  if (p == null) return (id, engineLine);
  final line = switch (s) {
    DiagnosticStatus.healthy => p.$2,
    DiagnosticStatus.notApplicable when id == 'ipv6_external_reachability' =>
      "This network doesn't use IPv6.",
    DiagnosticStatus.suspected when id == 'gateway_reachability' =>
      "It didn't answer a ping. Many providers block that, so the internet "
          'can still be fine.',
    _ => engineLine,
  };
  return (p.$1, line);
}

class CheckView extends StatelessWidget {
  const CheckView({
    super.key,
    required this.running,
    this.progress = 0,
    this.step,
    this.report,
    this.error,
    this.onRun,
    this.onCancel,
  });

  final bool running;
  final double progress;
  final String? step;
  final NetworkDiagnosticReport? report;
  final String? error;
  final VoidCallback? onRun;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    if (running) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress.clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: ks.line,
              color: ks.ac,
            ),
          ),
          const SizedBox(height: 10),
          Text(step ?? 'Checking…', style: KeystoneType.secondary(ks.tx2)),
          TextButton(onPressed: onCancel, child: const Text('Stop')),
        ],
      );
    }
    final r = report;
    if (r == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keystone checks the cable or SIM, the router, names and the '
            'internet, and tells you what is wrong. It takes about half a '
            'minute and changes nothing.',
            style: KeystoneType.body(ks.tx2),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!, style: KeystoneType.secondary(ks.bad)),
          ],
          const SizedBox(height: 14),
          FilledButton(onPressed: onRun, child: const Text('Check everything')),
        ],
      );
    }
    final problems = r.findings.where((f) => f.status.isProblem).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 10),
              child: KsDot(statusColor(ks, r.overallStatus), size: 10),
            ),
            Expanded(
              child: Text(
                r.overallStatus == DiagnosticStatus.healthy
                    ? "Everything's working."
                    : r.overallSummary,
                style: KeystoneType.bodyStrong(ks.tx),
              ),
            ),
          ],
        ),
        for (final f in problems) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ks.node,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: ks.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.title, style: KeystoneType.bodyStrong(ks.tx)),
                const SizedBox(height: 4),
                Text(f.description, style: KeystoneType.secondary(ks.tx2)),
                for (final (i, s) in f.recommendedSteps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${i + 1}. $s',
                      style: KeystoneType.secondary(ks.tx),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const KsSection('What was checked'),
        for (final t in r.testResults)
          for (final (title, line) in [
            plainCheck(t.id, t.status, t.explanation),
          ])
            KsRow(
              leading: KsDot(statusColor(ks, t.status)),
              title: title,
              subtitle: line,
              trailing: Text(
                statusWord(t.status),
                style: KeystoneType.caption(ks.mu),
              ),
            ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRun, child: const Text('Check again')),
      ],
    );
  }
}

class _ToolSheet extends StatefulWidget {
  const _ToolSheet({
    required this.title,
    required this.hint,
    required this.action,
    required this.busy,
    required this.onRun,
    required this.result,
  });

  final String title;
  final String hint;
  final String action;
  final bool busy;
  final ValueChanged<String> onRun;
  final Widget? result;

  @override
  State<_ToolSheet> createState() => _ToolSheetState();
}

class _ToolSheetState extends State<_ToolSheet> {
  final _c = TextEditingController(text: '1.1.1.1');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    void run() {
      final v = _c.text.trim();
      if (v.isNotEmpty && !widget.busy) widget.onRun(v);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autocorrect: false,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => run(),
          style: KeystoneType.body(ks.tx),
          decoration: ksInput(context, hint: widget.hint),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.busy ? null : run,
          child: Text(widget.busy ? 'Working…' : widget.action),
        ),
        if (widget.result != null) ...[
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            child: SingleChildScrollView(child: widget.result),
          ),
        ],
      ],
    );
  }
}

String _ms(double? v) => v == null ? '–' : '${v.round()} ms';

String pingLine(PingResult p) {
  if (p.packetsReceived == 0) {
    return p.errorMessage?.isNotEmpty == true
        ? "${p.target} didn't answer: ${p.errorMessage}"
        : "${p.target} didn't answer.";
  }
  return '${p.packetsReceived} of ${p.packetsTransmitted} answered · '
      '${_ms(p.avgRttMs)} on average'
      '${p.maxRttMs == null ? '' : ', slowest ${_ms(p.maxRttMs)}'}';
}

class _PingSheet extends ConsumerWidget {
  const _PingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(diagnosticsControllerProvider);
    final p = s.lastPingResult;
    return _ToolSheet(
      title: 'Ping',
      hint: 'An address or website',
      action: 'Ping',
      busy: s.isPinging,
      onRun: (v) => ref
          .read(diagnosticsControllerProvider.notifier)
          .ping(v, count: 5, isIpv6: v.contains(':')),
      result: p == null
          ? null
          : Text(pingLine(p), style: KeystoneType.body(context.ks.tx)),
    );
  }
}

class _TraceSheet extends ConsumerWidget {
  const _TraceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ks = context.ks;
    final s = ref.watch(diagnosticsControllerProvider);
    final r = s.lastTracerouteResult;
    return _ToolSheet(
      title: 'Trace the route',
      hint: 'An address or website',
      action: 'Trace',
      busy: s.isTracing,
      onRun: (v) => ref
          .read(diagnosticsControllerProvider.notifier)
          .traceroute(v, isIpv6: v.contains(':')),
      result: r == null
          ? null
          : r.hops.isEmpty
          ? Text(
              "Couldn't trace it${r.errorMessage == null ? '' : ': ${r.errorMessage}'}",
              style: KeystoneType.body(ks.mu),
            )
          : Column(children: [for (final h in r.hops) _hop(ks, h)]),
    );
  }

  Widget _hop(KeystoneColors ks, TracerouteHop h) => KsRow(
    leading: SizedBox(
      width: 22,
      child: Text('${h.hopNumber}', style: KeystoneType.caption(ks.mu)),
    ),
    title: h.isTimeout ? 'No answer' : h.displayAddress,
    subtitle: h.host != null && h.host != h.ip ? h.host : null,
    trailing: Text(
      h.rttMs.isEmpty ? '' : _ms(h.rttMs.reduce((a, b) => a < b ? a : b)),
      style: KeystoneType.caption(ks.mu),
    ),
  );
}

class _LookupSheet extends ConsumerWidget {
  const _LookupSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ks = context.ks;
    final s = ref.watch(diagnosticsControllerProvider);
    final r = s.lastDnsResult;
    return _ToolSheet(
      title: 'Look up a name',
      hint: 'A website, like example.com',
      action: 'Look up',
      busy: s.isLookingUpDns,
      onRun: (v) =>
          ref.read(diagnosticsControllerProvider.notifier).dnsLookup(v),
      result: r == null
          ? null
          : r.allAddresses.isEmpty
          ? Text(
              "${r.query} doesn't point anywhere"
              "${r.errorMessage == null ? '.' : ': ${r.errorMessage}'}",
              style: KeystoneType.body(ks.mu),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final a in r.allAddresses) KsRow(title: a, chevron: false),
                if (r.cnames.isNotEmpty)
                  KsRow(title: 'Also called', subtitle: r.cnames.join(', ')),
                if (r.server != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Answered by ${r.server}',
                      style: KeystoneType.caption(ks.mu),
                    ),
                  ),
              ],
            ),
    );
  }
}

class DnsSpeedScreen extends ConsumerWidget {
  const DnsSpeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ks = context.ks;
    final s = ref.watch(dnsBenchmarkControllerProvider);
    final c = ref.read(dnsBenchmarkControllerProvider.notifier);
    final results =
        [
          ?s.routerResult,
          ...s.publicResults.where((r) => !r.provider.isRouterDns),
        ]..sort(
          (a, b) => (a.medianLatencyMs ?? double.infinity).compareTo(
            b.medianLatencyMs ?? double.infinity,
          ),
        );
    return KsPage(
      title: 'Fastest DNS',
      subtitle: 'Lower is faster. Your router\'s own service is marked.',
      children: [
        KsChips<DnsVantagePoint>(
          options: const [
            (DnsVantagePoint.clientDevice, 'From this phone'),
            (DnsVantagePoint.router, 'From the router'),
          ],
          selected: s.vantagePoint,
          onSelected: s.isRunning ? (_) {} : c.setVantagePoint,
        ),
        const SizedBox(height: 14),
        s.isRunning
            ? OutlinedButton(
                onPressed: c.cancelBenchmark,
                child: const Text('Stop'),
              )
            : FilledButton(
                onPressed: () => c.startBenchmark(),
                child: Text(results.isEmpty ? 'Test' : 'Test again'),
              ),
        if (s.errorMessage != null) KsNote(s.errorMessage!),
        if (results.isNotEmpty) const KsSection('Results'),
        for (final r in results)
          KsRow(
            title: r.provider.isRouterDns
                ? 'Your router · ${r.provider.name}'
                : r.provider.name,
            subtitle: r.provider.primaryServer,
            leading: KsDot(
              r.provider.id == s.fastestProvider?.provider.id ? ks.ok : ks.line,
            ),
            trailing: Text(switch (r.status) {
              DnsBenchmarkStatus.testing => 'Testing…',
              DnsBenchmarkStatus.untested => '',
              _ when r.medianLatencyMs != null => _ms(r.medianLatencyMs),
              _ => 'No answer',
            }, style: KeystoneType.secondary(ks.tx2)),
          ),
      ],
    );
  }
}

class NetworkTablesScreen extends ConsumerStatefulWidget {
  const NetworkTablesScreen({super.key});

  @override
  ConsumerState<NetworkTablesScreen> createState() =>
      _NetworkTablesScreenState();
}

class _NetworkTablesScreenState extends ConsumerState<NetworkTablesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(diagnosticsControllerProvider.notifier).loadNetworkTables(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final s = ref.watch(diagnosticsControllerProvider);
    final ct = s.conntrack;
    return KsPage(
      title: 'Routes and connections',
      onRefresh: () =>
          ref.read(diagnosticsControllerProvider.notifier).loadNetworkTables(),
      children: [
        if (s.isLoadingNetworkTables && s.routes.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (ct != null && ct.max > 0) ...[
          const KsSection('Connections'),
          Text(
            '${ct.count} of ${ct.max} the router can keep track of',
            style: KeystoneType.secondary(ks.tx2),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (ct.count / ct.max).clamp(0, 1).toDouble(),
              minHeight: 6,
              backgroundColor: ks.line,
              color: ct.utilizationPercent >= 90 ? ks.bad : ks.ac,
            ),
          ),
        ],
        if (s.routes.isNotEmpty) const KsSection('Routes'),
        for (final r in s.routes)
          KsRow(
            title: r.isDefault ? 'Internet' : r.destination,
            subtitle: [
              if (r.gateway != null) 'through ${r.gateway}',
              if (r.interface != null) 'on ${r.interface}',
            ].join(' '),
          ),
        if (s.neighbors.isNotEmpty) const KsSection('Seen nearby'),
        for (final n in s.neighbors)
          KsRow(
            title: n.ip,
            subtitle: [?n.mac, ?n.interface].join(' · '),
            trailing: Text(
              n.state.toLowerCase(),
              style: KeystoneType.caption(ks.mu),
            ),
          ),
        if (!s.isLoadingNetworkTables && s.routes.isEmpty && ct == null)
          const KsNote("The router didn't share its tables."),
      ],
    );
  }
}
