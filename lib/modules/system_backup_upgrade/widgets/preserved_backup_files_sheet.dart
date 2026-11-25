// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';

class PreservedBackupFilesSheet extends StatefulWidget {
  final AppState appState;
  final String initialFileList;
  final String initialConfContent;

  const PreservedBackupFilesSheet({
    super.key,
    required this.appState,
    required this.initialFileList,
    required this.initialConfContent,
  });

  static Future<void> show(
    BuildContext context, {
    required AppState appState,
    required String initialFileList,
    required String initialConfContent,
  }) async {
    await ksFormRoute<void>(
      context,
      PreservedBackupFilesSheet(
        appState: appState,
        initialFileList: initialFileList,
        initialConfContent: initialConfContent,
      ),
    );
  }

  @override
  State<PreservedBackupFilesSheet> createState() =>
      _PreservedBackupFilesSheetState();
}

class _PreservedBackupFilesSheetState extends State<PreservedBackupFilesSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController _searchController;
  late TextEditingController _newPathController;
  late TextEditingController _confTextController;

  late String _fileListRaw;
  late String _confContentRaw;
  late String _initialConfContentRaw;

  List<String> _preservedPaths = [];
  List<String> _customConfPaths = [];
  List<String> _initialCustomConfPaths = [];

  bool _isRefreshing = false;
  bool _isSaving = false;
  bool _isRawMode = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController = TextEditingController();
    _newPathController = TextEditingController();

    _fileListRaw = widget.initialFileList;
    _confContentRaw = widget.initialConfContent;
    _initialConfContentRaw = widget.initialConfContent;
    _confTextController = TextEditingController(text: _confContentRaw);

    _parseData(updateInitial: true);

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _confTextController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _newPathController.dispose();
    _confTextController.dispose();
    super.dispose();
  }

  void _parseData({bool updateInitial = false}) {
    _preservedPaths = _fileListRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();

    _customConfPaths = _confContentRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('#'))
        .toList();

    if (updateInitial) {
      _initialConfContentRaw = _confContentRaw;
      _initialCustomConfPaths = List<String>.from(_customConfPaths);
    }
  }

  bool get _hasUnsavedChanges {
    if (_isSaving) return false;
    if (_isRawMode) {
      return _confTextController.text.trim() != _initialConfContentRaw.trim();
    } else {
      final currentJoined = _customConfPaths.join('\n');
      final initialJoined = _initialCustomConfPaths.join('\n');
      return currentJoined != initialJoined;
    }
  }

  Future<bool> _confirmDiscardIfDirty() async {
    if (!_hasUnsavedChanges) return true;
    return ksConfirm(
      context,
      title: 'Leave without saving?',
      body: 'Your changes to the extra files are lost.',
      action: 'Leave',
      danger: true,
    );
  }

  Future<void> _refreshFromRouter() async {
    if (_hasUnsavedChanges) {
      final canProceed = await _confirmDiscardIfDirty();
      if (!canProceed) return;
    }

    setState(() => _isRefreshing = true);
    await OsPlatformIntegration.triggerHaptic(OsHapticType.light);

    try {
      String? freshList = await widget.appState.executeRouterCommandOutput(
        'sh',
        ['-c', 'sysupgrade -l'],
      );
      freshList ??= await widget.appState.executeRouterCommandOutput(
        'sysupgrade',
        ['-l'],
      );
      freshList ??= await widget.appState.executeRouterCommandOutput(
        '/sbin/sysupgrade',
        ['-l'],
      );

      String? freshConf = await widget.appState.executeRouterCommandOutput(
        'cat',
        ['/etc/sysupgrade.conf'],
      );
      freshConf ??= '';

      if (mounted) {
        setState(() {
          _fileListRaw = freshList ?? _fileListRaw;
          _confContentRaw = freshConf ?? _confContentRaw;
          _confTextController.text = _confContentRaw;
          _parseData(updateInitial: true);
          _isRefreshing = false;
        });
        ksSay(context, 'Refreshed preserved backup files from router.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);
        ksSay(context, 'Failed to refresh backup file list.');
      }
    }
  }

  Future<void> _saveCustomConfToRouter() async {
    setState(() => _isSaving = true);
    await OsPlatformIntegration.triggerHaptic(OsHapticType.medium);

    String newContent = '';
    if (_isRawMode) {
      newContent = _confTextController.text.trim();
    } else {
      final lines = <String>[];
      lines.add('## Keep custom files across sysupgrade updates');
      lines.addAll(_customConfPaths);
      newContent = lines.join('\n');
    }

    try {
      final escContent = newContent.replaceAll("'", "'\\''");
      final cmd = "cat << 'EOF' > /etc/sysupgrade.conf\n$escContent\nEOF";
      final success = await widget.appState.executeRouterCommand('sh', [
        '-c',
        cmd,
      ]);

      if (success) {
        _confContentRaw = newContent;
        _confTextController.text = newContent;
        _parseData(updateInitial: true);

        final String? freshList = await widget.appState
            .executeRouterCommandOutput('sh', ['-c', 'sysupgrade -l']);
        if (freshList != null && freshList.trim().isNotEmpty) {
          _fileListRaw = freshList;
          _parseData(updateInitial: true);
        }

        if (mounted) {
          setState(() => _isSaving = false);
          ksSay(context, 'Saved /etc/sysupgrade.conf to router!');
        }
      } else {
        if (mounted) {
          setState(() => _isSaving = false);
          ksSay(context, 'Failed to save /etc/sysupgrade.conf to router.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ksSay(context, 'Error saving configuration');
      }
    }
  }

  void _addCustomPath() {
    final rawPath = _newPathController.text.trim();
    if (rawPath.isEmpty) return;

    if (!rawPath.startsWith('/')) {
      ksSay(
        context,
        'File path must start with "/" (e.g. /etc/cloudflared/config.yml)',
      );
      return;
    }

    if (_customConfPaths.contains(rawPath)) {
      ksSay(context, 'Path is already included in /etc/sysupgrade.conf');
      return;
    }

    setState(() {
      _customConfPaths.add(rawPath);
      _newPathController.clear();
      _confContentRaw = _customConfPaths.join('\n');
      _confTextController.text = _confContentRaw;
    });
    ksSay(context, 'Added path to list. Remember to tap "Save to Router".');
  }

  void _removeCustomPath(String path) {
    setState(() {
      _customConfPaths.remove(path);
      _confContentRaw = _customConfPaths.join('\n');
      _confTextController.text = _confContentRaw;
    });
    ksSay(context, 'Removed "$path". Tap "Save to Router" to apply.');
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final custom = _tabController.index == 1;
    final shown = _preservedPaths
        .where(
          (p) => _searchQuery.isEmpty || p.toLowerCase().contains(_searchQuery),
        )
        .toList();
    final dirty = _hasUnsavedChanges;

    return PopScope(
      canPop: !dirty && !_isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscardIfDirty() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: ks.bg,
        appBar: AppBar(
          backgroundColor: ks.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: ks.tx,
          actions: [
            IconButton(
              tooltip: 'Read it again from the router',
              icon: Icon(Icons.refresh_rounded, color: ks.mu),
              onPressed: _isRefreshing ? null : _refreshFromRouter,
            ),
            if (custom)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed: dirty && !_isSaving
                      ? _saveCustomConfToRouter
                      : null,
                  child: Text(_isSaving ? 'Saving…' : 'Save'),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              const KsTitle(
                'What a backup keeps',
                subtitle:
                    'These files survive a firmware upgrade and go into a backup',
              ),
              if (_isRefreshing) const LinearProgressIndicator(),
              KsChips<int>(
                options: [
                  (0, 'Kept · ${_preservedPaths.length}'),
                  (1, 'Your extra files · ${_customConfPaths.length}'),
                ],
                selected: _tabController.index,
                onSelected: (i) => setState(() => _tabController.index = i),
              ),
              const SizedBox(height: 12),
              if (!custom) ...[
                KsSearchField(
                  hint: 'Find a file',
                  onChanged: (v) => _searchController.text = v,
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: shown.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(
                              ClipboardData(text: shown.join('\n')),
                            );
                            ksSay(context, 'Copied ${shown.length} paths.');
                          },
                    child: const Text('Copy the list'),
                  ),
                ),
                if (shown.isEmpty)
                  Text('Nothing matches.', style: KeystoneType.body(ks.mu)),
                for (final p in shown.take(400))
                  KsRow(
                    title: p,
                    subtitle: _customConfPaths.contains(p)
                        ? 'Added by you'
                        : null,
                    chevron: false,
                  ),
              ] else ...[
                Text(
                  'Add files the router would otherwise forget, like a '
                  'program\'s own settings. They are kept in '
                  '/etc/sysupgrade.conf.',
                  style: KeystoneType.secondary(ks.mu),
                ),
                const SizedBox(height: 12),
                KsSwitchRow(
                  title: 'Edit as text',
                  value: _isRawMode,
                  onChanged: (v) => setState(() {
                    _isRawMode = v;
                    if (!v) {
                      _customConfPaths = _confTextController.text
                          .split('\n')
                          .map((l) => l.trim())
                          .where((l) => l.isNotEmpty && !l.startsWith('#'))
                          .toList();
                    }
                  }),
                ),
                if (_isRawMode)
                  KsField(
                    label: 'One path per line',
                    controller: _confTextController,
                    maxLines: 10,
                  )
                else ...[
                  if (_customConfPaths.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('None yet.', style: KeystoneType.body(ks.mu)),
                    ),
                  for (final p in _customConfPaths)
                    KsRow(
                      title: p,
                      chevron: false,
                      trailing: IconButton(
                        tooltip: 'Take off the list',
                        icon: Icon(Icons.close_rounded, color: ks.mu),
                        onPressed: () => _removeCustomPath(p),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: KsField(
                          label: 'Add a file or folder',
                          controller: _newPathController,
                          hint: '/etc/cloudflared/config.yml',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 28, left: 8),
                        child: TextButton(
                          onPressed: _addCustomPath,
                          child: const Text('Add'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (dirty)
                  Text(
                    'Not saved yet. Tap Save to keep these on the router.',
                    style: KeystoneType.caption(ks.warnTx),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
