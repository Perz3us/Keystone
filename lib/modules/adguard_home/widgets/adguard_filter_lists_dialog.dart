// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';

class AdGuardFilterListsDialog extends StatefulWidget {
  final AdGuardController controller;

  const AdGuardFilterListsDialog({super.key, required this.controller});

  static Future<void> show(
    BuildContext context, {
    required AdGuardController controller,
  }) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => AdGuardFilterListsDialog(controller: controller),
    ),
  );

  @override
  State<AdGuardFilterListsDialog> createState() =>
      _AdGuardFilterListsDialogState();
}

String _rules(int n) {
  try {
    return '${NumberFormat.decimalPattern().format(n)} rules';
  } catch (_) {
    return '$n rules';
  }
}

String _updated(String? iso) {
  if (iso == null || iso.isEmpty) return 'never updated';
  final d = DateTime.tryParse(iso)?.toLocal();
  return d == null
      ? 'updated $iso'
      : 'updated ${DateFormat('d MMM, HH:mm').format(d)}';
}

class _AdGuardFilterListsDialogState extends State<AdGuardFilterListsDialog> {
  bool _allow = false;
  String _query = '';

  AdGuardController get _c => widget.controller;

  Future<void> _after(Future<bool> action, String done) async {
    final ok = await action;
    if (!mounted) return;
    if (ok) ksSay(context, done);
    setState(() {});
  }

  Future<void> _form(Widget page) async {
    await ksFormRoute<bool>(context, page);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final s = _c.currentState;
    final block = s.filtering?.filterLists ?? const <AdGuardFilterList>[];
    final allow = s.filtering?.whitelistFilters ?? const <AdGuardFilterList>[];
    final shown = (_allow ? allow : block)
        .where(
          (l) =>
              _query.isEmpty ||
              l.name.toLowerCase().contains(_query) ||
              l.url.toLowerCase().contains(_query),
        )
        .toList();
    final busy = s.isMutatingFilterLists;

    return KsPage(
      key: const Key('agh_filter_lists_dialog'),
      title: 'Block lists',
      back: 'Ad blocking',
      subtitle: 'Lists of sites AdGuard Home blocks, or always lets through',
      children: [
        Row(
          children: [
            KsChip(
              'Block · ${block.length}',
              key: const Key('agh_filter_lists_tab_blocklists'),
              selected: !_allow,
              onTap: () => setState(() => _allow = false),
            ),
            const SizedBox(width: 8),
            KsChip(
              'Allow · ${allow.length}',
              key: const Key('agh_filter_lists_tab_allowlists'),
              selected: _allow,
              onTap: () => setState(() => _allow = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        KsSearchField(
          key: const Key('agh_filter_lists_search_field'),
          hint: 'Find a list',
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        if (s.filterListActionError != null)
          KsBanner(
            s.filterListActionError!,
            bad: true,
            key: const Key('agh_filter_list_error_banner'),
          ),
        if (busy) const LinearProgressIndicator(),
        const SizedBox(height: 8),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _query.isNotEmpty
                  ? 'Nothing matches.'
                  : (_allow ? 'No allow lists yet.' : 'No block lists yet.'),
              style: KeystoneType.body(ks.mu),
            ),
          ),
        for (final l in shown)
          KsRow(
            key: Key('agh_filter_list_tile_${l.id}'),
            title: l.name,
            subtitle: '${_rules(l.rulesCount)}, ${_updated(l.lastUpdated)}',
            onTap: () => _form(_EditFilterListDialog(controller: _c, list: l)),
            trailing: Switch(
              key: Key('agh_filter_list_toggle_${l.id}'),
              value: l.enabled,
              onChanged: busy
                  ? null
                  : (v) async {
                      await _c.toggleFilterList(list: l, enabled: v);
                      if (mounted) setState(() {});
                    },
            ),
          ),
        const SizedBox(height: 8),
        KsRow(
          key: const Key('agh_add_filter_list_button'),
          title: _allow ? 'Add an allow list' : 'Add a block list',
          onTap: () => _form(
            _AddFilterListDialog(controller: _c, initialWhitelist: _allow),
          ),
        ),
        KsRow(
          key: const Key('agh_filter_lists_update_button'),
          title: 'Check every list for updates',
          chevron: false,
          onTap: busy
              ? null
              : () => _after(
                  _c.refreshFilterLists(),
                  'The lists are up to date.',
                ),
        ),
      ],
    );
  }
}

class _FilterPreset {
  final String name;
  final String url;
  const _FilterPreset(this.name, this.url);
}

const List<_FilterPreset> _curatedPresets = [
  _FilterPreset(
    'AdGuard DNS filter',
    'https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt',
  ),
  _FilterPreset('AdAway Default Blocklist', 'https://adaway.org/hosts.txt'),
  _FilterPreset('OISD Basic', 'https://small.oisd.nl'),
  _FilterPreset(
    'Steven Black Unified',
    'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts',
  ),
  _FilterPreset(
    "Peter Lowe's List",
    'https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext',
  ),
];

String? _needName(String? v) =>
    v == null || v.trim().isEmpty ? 'Give it a name.' : null;

String? _needUrl(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return 'Paste the list\'s web address.';
  final u = Uri.tryParse(t);
  if (u == null || !(u.isScheme('http') || u.isScheme('https'))) {
    return 'It should start with http:// or https://';
  }
  return null;
}

class _AddFilterListDialog extends StatefulWidget {
  final AdGuardController controller;
  final bool initialWhitelist;

  const _AddFilterListDialog({
    required this.controller,
    required this.initialWhitelist,
  });

  @override
  State<_AddFilterListDialog> createState() => _AddFilterListDialogState();
}

class _AddFilterListDialogState extends State<_AddFilterListDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();
  late bool _whitelist = widget.initialWhitelist;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.addFilterList(
      name: _name.text.trim(),
      url: _url.text.trim(),
      whitelist: _whitelist,
    );
    if (!mounted) return;
    if (ok) {
      ksSay(context, '${_name.text.trim()} is added.');
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error =
            widget.controller.currentState.filterListActionError ??
            'AdGuard Home didn\'t add it. Check the address.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KsFormPage(
      key: const Key('agh_add_filter_list_dialog'),
      title: _whitelist ? 'Add an allow list' : 'Add a block list',
      action: 'Add',
      actionKey: const Key('agh_add_filter_submit_button'),
      busy: _busy,
      onAction: _submit,
      formKey: _formKey,
      children: [
        if (_error != null) KsBanner(_error!, bad: true),
        if (!_whitelist) ...[
          const KsSection('Popular lists'),
          for (final p in _curatedPresets)
            KsRow(
              key: Key('agh_filter_list_preset_${p.name}'),
              title: p.name,
              chevron: false,
              onTap: () => setState(() {
                _name.text = p.name;
                _url.text = p.url;
                _error = null;
              }),
            ),
          const KsSection('Or your own'),
        ],
        KsField(
          key: const Key('agh_add_filter_name_input'),
          label: 'Name',
          controller: _name,
          validator: _needName,
        ),
        KsField(
          key: const Key('agh_add_filter_url_input'),
          label: 'Web address of the list',
          controller: _url,
          hint: 'https://',
          keyboardType: TextInputType.url,
          validator: _needUrl,
        ),
        const SizedBox(height: 8),
        KsSwitchRow(
          title: 'Allow list',
          subtitle: 'Sites on it are always let through',
          value: _whitelist,
          onChanged: (v) => setState(() => _whitelist = v),
        ),
      ],
    );
  }
}

class _EditFilterListDialog extends StatefulWidget {
  final AdGuardController controller;
  final AdGuardFilterList list;

  const _EditFilterListDialog({required this.controller, required this.list});

  @override
  State<_EditFilterListDialog> createState() => _EditFilterListDialogState();
}

class _EditFilterListDialogState extends State<_EditFilterListDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.list.name);
  late final _url = TextEditingController(text: widget.list.url);
  late bool _enabled = widget.list.enabled;
  bool _busy = false;
  String? _error;

  String get _key =>
      widget.list.url.isNotEmpty ? widget.list.url : widget.list.name;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.controller.editFilterList(
      url: _key,
      name: _name.text.trim(),
      newUrl: _url.text.trim(),
      enabled: _enabled,
      whitelist: widget.list.whitelist,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error =
            widget.controller.currentState.filterListActionError ??
            'AdGuard Home didn\'t save that.';
      });
    }
  }

  Future<void> _remove() async {
    final go = await ksConfirm(
      context,
      title: 'Remove ${widget.list.name}?',
      body: 'AdGuard Home stops using this list.',
      action: 'Remove',
      danger: true,
    );
    if (!go || !mounted) return;
    setState(() => _busy = true);
    final ok = await widget.controller.removeFilterList(
      url: _key,
      whitelist: widget.list.whitelist,
    );
    if (!mounted) return;
    if (ok) {
      ksSay(context, '${widget.list.name} is removed.');
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = 'AdGuard Home didn\'t remove it.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KsFormPage(
      key: const Key('agh_edit_filter_list_dialog'),
      title: widget.list.name,
      subtitle:
          '${_rules(widget.list.rulesCount)}, '
          '${_updated(widget.list.lastUpdated)}',
      action: 'Save',
      actionKey: const Key('agh_edit_filter_submit_button'),
      busy: _busy,
      onAction: _submit,
      formKey: _formKey,
      children: [
        if (_error != null) KsBanner(_error!, bad: true),
        KsField(
          key: const Key('agh_edit_filter_name_input'),
          label: 'Name',
          controller: _name,
          validator: _needName,
        ),
        KsField(
          key: const Key('agh_edit_filter_url_input'),
          label: 'Web address of the list',
          controller: _url,
          keyboardType: TextInputType.url,
          validator: _needUrl,
        ),
        const SizedBox(height: 8),
        KsSwitchRow(
          title: 'Use this list',
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 16),
        KsRow(
          key: const Key('agh_filter_list_delete_button'),
          title: 'Remove this list',
          danger: true,
          chevron: false,
          onTap: _busy ? null : _remove,
        ),
      ],
    );
  }
}
