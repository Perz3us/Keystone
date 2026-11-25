import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/log_viewer/controllers/log_viewer_controller.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_entry.dart';
import 'package:yet_another_luci_app/modules/log_viewer/models/log_fetch_result.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  bool _kernel = false;

  static String? _problem(LogFetchResult? r) => switch (r) {
    null || LogFetchSuccess() => null,
    LogFetchPermissionError() => "This sign-in isn't allowed to read logs.",
    LogFetchBinaryMissing() =>
      "The router doesn't have the tool that reads "
          'this log.',
    LogFetchTimeout() =>
      "The router didn't answer in time. Pull down to try "
          'again.',
    LogFetchRpcError(:final message) =>
      "Couldn't read the log${message == null ? '' : ': $message'}",
  };

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(appStateProvider).selectedRouter?.id ?? '';
    final s = ref.watch(logViewerControllerProvider(id));
    final c = ref.read(logViewerControllerProvider(id).notifier);
    final r = _kernel ? s.kernelResult : s.syslogResult;
    final loading = _kernel ? s.isLoadingKernel : s.isLoadingSyslog;
    final entries = r is LogFetchSuccess ? r.entries : const <LogEntry>[];
    return KsPage(
      title: 'Logs',
      actions: [
        PopupMenuButton<int>(
          tooltip: 'How much to show',
          icon: Icon(Icons.more_horiz_rounded, color: context.ks.mu),
          color: context.ks.sheet,
          onSelected: c.setLinesToFetch,
          itemBuilder: (_) => [
            for (final n in [200, 500, 1000])
              CheckedPopupMenuItem(
                value: n,
                checked: s.linesToFetch == n,
                child: Text('Last $n lines'),
              ),
          ],
        ),
        IconButton(
          tooltip: 'Copy',
          icon: Icon(Icons.copy_rounded, color: context.ks.mu),
          onPressed: entries.isEmpty
              ? null
              : () {
                  Clipboard.setData(
                    ClipboardData(text: entries.map((e) => e.raw).join('\n')),
                  );
                  ksSay(context, 'Copied ${entries.length} lines.');
                },
        ),
      ],
      body: LogsView(
        kernel: _kernel,
        entries: entries,
        loading: loading && r == null,
        problem: _problem(r),
        onKernel: (k) => setState(() => _kernel = k),
        onRefresh: () => _kernel ? c.loadKernelLog() : c.loadSyslog(),
      ),
    );
  }
}

class LogsView extends StatefulWidget {
  const LogsView({
    super.key,
    required this.kernel,
    required this.entries,
    required this.onKernel,
    this.loading = false,
    this.problem,
    this.onRefresh,
  });

  final bool kernel;
  final List<LogEntry> entries;
  final ValueChanged<bool> onKernel;
  final bool loading;
  final String? problem;
  final Future<void> Function()? onRefresh;

  @override
  State<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends State<LogsView> {
  String _query = '';
  bool _problems = false;

  static bool _isProblem(LogLevel l) => l.index <= LogLevel.warning.index;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final q = _query.trim().toLowerCase();
    final shown = widget.entries.reversed
        .where((e) => !_problems || _isProblem(e.level))
        .where((e) => q.isEmpty || e.raw.toLowerCase().contains(q))
        .toList();
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        const KsTitle('Logs'),
        KsChips<bool>(
          options: const [(false, 'Router'), (true, 'Kernel')],
          selected: widget.kernel,
          onSelected: (k) {
            if (k != widget.kernel) widget.onKernel(k);
          },
        ),
        const SizedBox(height: 12),
        KsSearchField(
          hint: 'Search the log',
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        KsChips<bool>(
          options: const [(false, 'Everything'), (true, 'Problems')],
          selected: _problems,
          onSelected: (p) => setState(() => _problems = p),
        ),
        const SizedBox(height: 8),
        if (widget.loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.problem != null)
          KsNote(widget.problem!)
        else if (shown.isEmpty)
          KsNote(
            widget.entries.isEmpty ? 'The log is empty.' : 'Nothing matches.',
          )
        else
          for (final e in shown)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ks.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: KsDot(
                      e.level.index <= LogLevel.error.index
                          ? ks.bad
                          : e.level == LogLevel.warning
                          ? ks.warn
                          : ks.line,
                      size: 7,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.message.isEmpty ? e.raw : e.message,
                          style: KeystoneType.secondary(ks.tx),
                        ),
                        Text(
                          [e.tag, e.timestamp].whereType<String>().join(' · '),
                          style: KeystoneType.caption(ks.mu),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
    return widget.onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
  }
}
