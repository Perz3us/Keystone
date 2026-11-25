// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class NoobSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const NoobSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KsSection(
          title,
          trailing: trailing == null
              ? null
              : DefaultTextStyle(
                  style: KeystoneType.secondary(ks.mu),
                  child: trailing!,
                ),
        ),
        ...children,
      ],
    );
  }
}

class NoobRow extends StatelessWidget {
  final String label;
  final String? value;
  final Color? color;

  const NoobRow(this.label, this.value, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: KeystoneType.body(ks.tx)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SelectableText(
              value ?? '–',
              textAlign: TextAlign.end,
              style: KeystoneType.secondary(color ?? ks.tx2),
            ),
          ),
        ],
      ),
    );
  }
}

class NoobProblem extends StatelessWidget {
  final String title;
  final String detail;
  final String? error;
  final VoidCallback onRetry;

  const NoobProblem({
    super.key,
    required this.title,
    required this.detail,
    required this.onRetry,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        KsTitle(title),
        Text(detail, style: KeystoneType.body(ks.tx2)),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: KeystoneType.caption(ks.mu)),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ),
      ],
    );
  }
}

class NoobPage extends StatelessWidget {
  const NoobPage({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.children,
    this.body,
    this.onRefresh,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget>? children;

  final Widget? body;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) => body != null
      ? KsPage(title: title, actions: actions, body: body)
      : KsPage(
          title: title,
          subtitle: subtitle,
          actions: actions,
          onRefresh: onRefresh,
          children: children ?? const [],
        );
}

String noobAgo(int unixSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return '${t.year}-${_two(t.month)}-${_two(t.day)}';
}

String noobClock(int unixSeconds) {
  final t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

String noobBytes(num b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}
