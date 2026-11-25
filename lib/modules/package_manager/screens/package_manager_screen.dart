// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/state/controllers/package_controller.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../models/package_info.dart';

enum SoftwareTab { installed, available, updates }

bool isCorePackage(String name) => PackageController.isCriticalPackage(name);

bool isSystemPart(String name) {
  final n = name.toLowerCase();
  return isCorePackage(n) ||
      n.startsWith('lib') ||
      n.startsWith('kmod-') ||
      n.endsWith('-firmware') ||
      n.contains('-firmware-');
}

String? sizeWords(String? raw) {
  final b = int.tryParse(raw?.trim() ?? '');
  if (b == null || b <= 0) return null;
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String shortAbout(String d) {
  final dot = d.indexOf(RegExp(r'\.(\s|$)'));
  final first = dot > 0 ? d.substring(0, dot) : d;
  return first.length <= 90 ? first : '${first.substring(0, 87).trimRight()}…';
}

List<OpenWrtPackage> softwareList(
  PackageManagerOverview o,
  SoftwareTab tab,
  String query, {
  bool everything = false,
}) {
  final q = query.trim().toLowerCase();
  final source = switch (tab) {
    SoftwareTab.installed => o.installedPackages,
    SoftwareTab.available => o.availablePackages.where((p) => !p.isInstalled),
    SoftwareTab.updates => o.upgradablePackages,
  };
  return [
    for (final p in source)
      if ((everything || tab == SoftwareTab.updates || !isSystemPart(p.name)) &&
          (q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.description.toLowerCase().contains(q)))
        p,
  ];
}

class PackageManagerScreen extends ConsumerStatefulWidget {
  const PackageManagerScreen({super.key});

  @override
  ConsumerState<PackageManagerScreen> createState() =>
      _PackageManagerScreenState();
}

class _PackageManagerScreenState extends ConsumerState<PackageManagerScreen> {
  PackageManagerOverview? _o;
  bool _loading = true;
  String? _error;
  SoftwareTab _tab = SoftwareTab.installed;
  String _q = '';
  bool _everything = false;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = ref.read(appStateProvider);
    final res = await app.fetchPackageManagerOverview();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) {
        _o = res.data;
        _error = null;
        if (_o!.activeManager != app.capabilities?.packageEngine) {
          app.updatePackageEngine(_o!.activeManager);
        }
      } else {
        _error = res.isPermissionDenied
            ? "This sign-in isn't allowed to manage software."
            : "Keystone couldn't read the software list.";
      }
    });
  }

  Future<void> _run(
    String key,
    Future<RpcResult<String>> Function() work,
  ) async {
    setState(() => _busy.add(key));
    RpcResult<String> res;
    try {
      res = await work();
    } catch (e) {
      res = RpcResult.failed(e.toString());
    }
    if (!mounted) return;
    setState(() => _busy.remove(key));
    if (res.isSuccess) {
      await _load();
      return;
    }
    final out = (res.data ?? res.errorMessage ?? '').trim();
    await ksSheet<void>(context, (c) {
      final ks = c.ks;
      final readOnly = out.toLowerCase().contains('read-only file system');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("That didn't work", style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 8),
          if (readOnly)
            const KsBanner(
              "The router's storage is full, so nothing can be added. "
              'Remove something you no longer use first.',
              bad: true,
            ),
          if (out.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(out, style: KeystoneType.address(ks.tx2)),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: out));
              Navigator.pop(c);
            },
            child: const Text('Copy what the router said'),
          ),
        ],
      );
    });
  }

  String _free() {
    final b = _o?.freeDiskSpace;
    return b == null ? '' : '${sizeWords('$b') ?? '0 B'} free on the router';
  }

  Future<void> _install(OpenWrtPackage p) async {
    final size = sizeWords(p.size ?? p.repositorySize);
    final ok = await ksConfirm(
      context,
      title: 'Install ${p.name}?',
      body: [
        if (p.description.isNotEmpty) p.description,
        [
          if (size != null) 'About $size',
          if (_free().isNotEmpty) _free(),
        ].join(', '),
      ].where((l) => l.isNotEmpty).join('\n\n'),
      action: 'Install',
    );
    if (ok && mounted) {
      await _run(
        p.name,
        () => ref.read(appStateProvider).installPackage(p.name),
      );
    }
  }

  Future<void> _remove(OpenWrtPackage p) async {
    final ok = await ksConfirm(
      context,
      title: 'Uninstall ${p.name}?',
      body:
          'Anything that needs it stops working. You can install it again '
          'later.',
      action: 'Uninstall',
      danger: true,
    );
    if (ok && mounted) {
      await _run(
        p.name,
        () => ref.read(appStateProvider).removePackage(p.name),
      );
    }
  }

  Future<void> _update(OpenWrtPackage p) =>
      _run(p.name, () => ref.read(appStateProvider).upgradePackage(p.name));

  Future<void> _custom() async {
    final ctrl = TextEditingController();
    final target = await ksSheet<String>(context, (c) {
      final ks = c.ks;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Install by name or link',
            style: KeystoneType.sheetTitle(ks.tx),
          ),
          const SizedBox(height: 12),
          KsField(
            label: 'Package',
            controller: ctrl,
            hint: 'luci-app-wireguard or https://…',
          ),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) Navigator.pop(c, t);
            },
            child: const Text('Install'),
          ),
        ],
      );
    });
    ctrl.dispose();
    if (target != null && mounted) {
      await _run(
        target,
        () => ref.read(appStateProvider).installCustomPackage(target),
      );
    }
  }

  void _details(OpenWrtPackage p) => ksSheet<void>(context, (c) {
    final ks = c.ks;
    Widget line(String k, String? v) => v == null || v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(k, style: KeystoneType.secondary(ks.mu)),
                ),
                Expanded(child: Text(v, style: KeystoneType.body(ks.tx2))),
              ],
            ),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(p.name, style: KeystoneType.sheetTitle(ks.tx)),
        if (p.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(p.description, style: KeystoneType.body(ks.tx2)),
        ],
        const SizedBox(height: 12),
        line('Version', p.version),
        line('New version', p.newVersion),
        line('Size', sizeWords(p.installedSize ?? p.size)),
        line('Needs', p.dependencies),
        line('Licence', p.license),
      ],
    );
  });

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final o = _o;
    final updates = o?.upgradablePackages.length ?? 0;
    final list = o == null
        ? const <OpenWrtPackage>[]
        : softwareList(o, _tab, _q, everything: _everything);

    return KsPage(
      title: 'Software',
      subtitle: o == null ? 'Add-ons on the router' : _free(),
      onRefresh: _load,
      actions: [
        PopupMenuButton<int>(
          tooltip: 'More',
          color: ks.sheet,
          onSelected: (v) => v == 0
              ? _run(
                  'lists',
                  () => ref.read(appStateProvider).updatePackageLists(),
                )
              : _custom(),
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 0,
              child: Text(
                'Check for new software',
                style: KeystoneType.body(ks.tx),
              ),
            ),
            PopupMenuItem(
              value: 1,
              child: Text(
                'Install by name or link',
                style: KeystoneType.body(ks.tx),
              ),
            ),
          ],
        ),
      ],
      children: [
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          KsNote(_error!, action: 'Try again', onAction: _load)
        else ...[
          if (_busy.contains('lists'))
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(),
            ),
          KsChips<SoftwareTab>(
            options: [
              (SoftwareTab.installed, 'Installed'),
              (SoftwareTab.available, 'Get more'),
              (
                SoftwareTab.updates,
                updates == 0 ? 'Updates' : 'Updates · $updates',
              ),
            ],
            selected: _tab,
            onSelected: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 12),
          KsSearchField(
            hint: 'Find software',
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(switch (_tab) {
                SoftwareTab.updates => 'Everything is up to date.',
                _ when _q.isNotEmpty => 'Nothing matches.',
                SoftwareTab.available =>
                  'Nothing new. Try "Check for new software" in the menu.',
                SoftwareTab.installed => 'Nothing extra installed.',
              }, style: KeystoneType.body(ks.mu)),
            ),
          for (final p in list.take(300))
            KsRow(
              title: p.name,
              subtitle: [
                p.hasUpdate && p.newVersion != null
                    ? '${p.version} → ${p.newVersion}'
                    : p.version,
                if (p.description.isNotEmpty) shortAbout(p.description),
              ].join(' · '),
              chevron: false,
              onTap: () => _details(p),
              trailing: _busy.contains(p.name)
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : switch (_tab) {
                      SoftwareTab.available => TextButton(
                        onPressed: () => _install(p),
                        child: const Text('Install'),
                      ),
                      SoftwareTab.updates => TextButton(
                        onPressed: () => _update(p),
                        child: const Text('Update'),
                      ),
                      SoftwareTab.installed =>
                        isCorePackage(p.name)
                            ? null
                            : PopupMenuButton<int>(
                                tooltip: 'More',
                                color: ks.sheet,
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: ks.mu,
                                ),
                                onSelected: (v) =>
                                    v == 0 ? _update(p) : _remove(p),
                                itemBuilder: (_) => [
                                  if (p.hasUpdate)
                                    PopupMenuItem(
                                      value: 0,
                                      child: Text(
                                        'Update',
                                        style: KeystoneType.body(ks.tx),
                                      ),
                                    ),
                                  PopupMenuItem(
                                    value: 1,
                                    child: Text(
                                      'Uninstall',
                                      style: KeystoneType.body(ks.bad),
                                    ),
                                  ),
                                ],
                              ),
                    },
            ),
          if (list.length > 300)
            Text(
              'Showing 300 of ${list.length}. Search to narrow it down.',
              style: KeystoneType.caption(ks.mu),
            ),
          if (_tab != SoftwareTab.updates)
            KsSwitchRow(
              title: 'Show system parts',
              subtitle: 'Libraries, drivers and the core of the router',
              value: _everything,
              onChanged: (v) => setState(() => _everything = v),
            ),
        ],
      ],
    );
  }
}
