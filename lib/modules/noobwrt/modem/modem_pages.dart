// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_widgets.dart';

class ModemPageRow extends StatelessWidget {
  const ModemPageRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.live,
    required this.children,
  });

  final String title;
  final String subtitle;
  final Listenable live;
  final List<Widget> Function(BuildContext context) children;

  @override
  Widget build(BuildContext context) => KsRow(
    title: title,
    subtitle: subtitle,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: live,
          builder: (context, _) =>
              KsPage(title: title, children: children(context)),
        ),
      ),
    ),
  );
}

List<Widget> valueRows(
  String title,
  IconData icon,
  List<(String, String?)> rows,
) {
  final shown = [
    for (final (label, value) in rows)
      if (value != null && value.trim().isNotEmpty) NoobRow(label, value),
  ];
  return shown.isEmpty
      ? const []
      : [NoobSection(title: title, icon: icon, children: shown)];
}

String? connectedFor(String? seconds) {
  final s = int.tryParse(seconds ?? '');
  if (s == null || s < 0) return null;
  final d = Duration(seconds: s);
  if (d.inMinutes < 1) return 'just connected';
  if (d.inHours < 1) return 'connected ${d.inMinutes} min';
  if (d.inDays < 1) {
    return 'connected ${d.inHours} h ${d.inMinutes % 60} min';
  }
  return 'connected ${d.inDays} d ${d.inHours % 24} h';
}
