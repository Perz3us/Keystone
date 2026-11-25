// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/adguard_models.dart';

class AdGuardTopListsBottomSheet extends StatefulWidget {
  final AdGuardStats? stats;
  final int initialTabIndex;

  const AdGuardTopListsBottomSheet({
    super.key,
    required this.stats,
    this.initialTabIndex = 0,
  });

  static Future<void> show(
    BuildContext context, {
    required AdGuardStats? stats,
    int initialTabIndex = 0,
  }) {
    return ksSheet<void>(
      context,
      (_) => AdGuardTopListsBottomSheet(
        stats: stats,
        initialTabIndex: initialTabIndex,
      ),
    );
  }

  @override
  State<AdGuardTopListsBottomSheet> createState() =>
      _AdGuardTopListsBottomSheetState();
}

class _AdGuardTopListsBottomSheetState extends State<AdGuardTopListsBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final lists = [
      widget.stats?.topBlockedDomains ?? const <AdGuardTopItem>[],
      widget.stats?.topQueriedDomains ?? const <AdGuardTopItem>[],
      widget.stats?.topClients ?? const <AdGuardTopItem>[],
    ];
    final tab = _tabController.index;
    final items = lists[tab];
    final shown = _searchQuery.isEmpty
        ? items
        : items
              .where((e) => e.identifier.toLowerCase().contains(_searchQuery))
              .toList();
    final most = items.fold<int>(1, (m, e) => e.count > m ? e.count : m);
    final bar = tab == 0 ? ks.bad : ks.ac;

    return SizedBox(
      key: const Key('agh_top_lists_bottom_sheet'),
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Top activity',
                  style: KeystoneType.sheetTitle(ks.tx),
                ),
              ),
              IconButton(
                key: const Key('agh_top_lists_sheet_close_button'),
                tooltip: 'Close',
                icon: Icon(Icons.close_rounded, color: ks.mu),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          KsChips<int>(
            options: [
              (0, 'Blocked · ${lists[0].length}'),
              (1, 'Looked up · ${lists[1].length}'),
              (2, 'Devices · ${lists[2].length}'),
            ],
            selected: tab,
            onSelected: (i) => setState(() => _tabController.index = i),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('agh_top_lists_sheet_search_field'),
            controller: _searchController,
            style: KeystoneType.body(ks.tx),
            decoration: ksInput(context, hint: 'Find a site or device')
                .copyWith(
                  prefixIcon: Icon(Icons.search_rounded, color: ks.mu),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear',
                          icon: Icon(Icons.clear_rounded, color: ks.mu),
                          onPressed: _searchController.clear,
                        ),
                ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty
                          ? 'Nothing yet.'
                          : 'Nothing matches.',
                      style: KeystoneType.body(ks.mu),
                    ),
                  )
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final e = shown[i];
                      return InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: e.identifier));
                          ksSay(context, 'Copied ${e.identifier}.');
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.identifier,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: KeystoneType.body(ks.tx),
                                    ),
                                  ),
                                  Text(
                                    '${e.count}',
                                    style: KeystoneType.address(ks.mu),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: (e.count / most).clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: ks.line,
                                  valueColor: AlwaysStoppedAnimation(bar),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
