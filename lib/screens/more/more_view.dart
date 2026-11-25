import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class MoreItem {
  const MoreItem(
    this.icon,
    this.title,
    this.subtitle,
    this.onTap, {
    this.highlight = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;
}

class MoreView extends StatelessWidget {
  const MoreView({
    super.key,
    required this.routerName,
    required this.sections,
    this.onRouterMenu,
    this.signOutLabel = 'Sign out',
    this.onSignOut,
  });

  final String routerName;
  final List<(String, List<MoreItem>)> sections;
  final VoidCallback? onRouterMenu;

  final String signOutLabel;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onRouterMenu,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      routerName,
                      overflow: TextOverflow.ellipsis,
                      style: KeystoneType.bodyStrong(
                        ks.tx,
                      ).copyWith(fontSize: 18),
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, size: 20, color: ks.mu),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('More', style: KeystoneType.title(ks.tx)),
          const SizedBox(height: 4),
          Text(
            'Only what this router has installed.',
            style: KeystoneType.secondary(ks.mu),
          ),
          for (final (title, items) in sections)
            if (items.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 4),
                child: Text(title, style: KeystoneType.secondary(ks.mu)),
              ),
              for (final i in items) _row(ks, i),
            ],
          if (onSignOut != null) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: onSignOut,
              style: TextButton.styleFrom(
                backgroundColor: ks.node,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                signOutLabel,
                style: KeystoneType.body(
                  ks.bad,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(KeystoneColors ks, MoreItem i) => InkWell(
    onTap: i.onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        children: [
          Icon(i.icon, size: 22, color: ks.tx2),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.title, style: KeystoneType.body(ks.tx)),
                Text(
                  i.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: KeystoneType.caption(i.highlight ? ks.ac : ks.mu),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: ks.mu),
        ],
      ),
    ),
  );
}
