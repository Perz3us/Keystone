// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../../core/luci_module.dart';
import '../noob_rpc.dart';
import 'passwall_view.dart';

class PasswallKind {
  final String config;
  final String title;
  final String moduleId;
  const PasswallKind._(this.config, this.title, this.moduleId);

  static const v2 = PasswallKind._(
    'passwall2',
    'Passwall2',
    'noobwrt_passwall2',
  );
  static const v1 = PasswallKind._('passwall', 'Passwall', 'noobwrt_passwall');
  static const all = [v2, v1];
}

class PasswallModule extends LuciModule {
  PasswallModule([this.kind = PasswallKind.v2]);
  final PasswallKind kind;

  @override
  String get id => kind.moduleId;

  @override
  Set<String> get requiredConfigs => {kind.config};

  @override
  String get name => kind.title;

  @override
  String get description => 'Proxy on or off, nodes, add from a link';

  @override
  IconData get icon => Icons.vpn_lock_outlined;

  @override
  IconData get selectedIcon => Icons.vpn_lock;

  @override
  LuciModuleCategory get category => LuciModuleCategory.services;

  @override
  int get priority => 14;

  @override
  Widget buildScreen(BuildContext context, {Map<String, dynamic>? params}) =>
      PasswallScreen(kind: kind);
}

class PasswallInfo {
  final Map<String, dynamic> global;
  final List<Map<String, dynamic>> nodes;
  final bool? running;
  const PasswallInfo(this.global, this.nodes, this.running);

  bool get enabled => global['enabled'] == '1';

  String get nodeKey =>
      global.containsKey('tcp_node') && !global.containsKey('node')
      ? 'tcp_node'
      : 'node';

  Map<String, String> useNode(String id) {
    final udp = noobValue(global['udp_node']);
    return {
      nodeKey: id,
      if (nodeKey == 'tcp_node' && udp != null && udp != 'tcp' && udp != 'nil')
        'udp_node': id,
    };
  }

  Map<String, dynamic>? get currentNode =>
      nodes.where((n) => n['.name'] == global[nodeKey]).firstOrNull;

  static String nodeName(Map<String, dynamic> n) =>
      noobValue(n['remarks']) ?? n['.name'].toString();
}

Future<PasswallInfo> readPasswall(
  AppState app, [
  PasswallKind kind = PasswallKind.v2,
]) async {
  final sections = await noobUciSections(app, kind.config);
  final running = await noobCall(app, 'file', 'exec', {
    'command': '/usr/bin/pgrep',
    'params': ['-f', '[/]tmp/etc/${kind.config}/bin/'],
  }).then<bool?>((r) => noobValue(r['stdout']) != null).catchError((_) => null);
  return PasswallInfo(
    sections.firstWhere((s) => s['.type'] == 'global', orElse: () => const {}),
    sections.where((s) => s['.type'] == 'nodes').toList(),
    running,
  );
}

class PasswallVpnCard extends ConsumerStatefulWidget {
  const PasswallVpnCard({super.key, this.kind = PasswallKind.v2});
  final PasswallKind kind;

  @override
  ConsumerState<PasswallVpnCard> createState() => _PasswallVpnCardState();
}

class _PasswallVpnCardState extends ConsumerState<PasswallVpnCard> {
  PasswallInfo? _p;

  @override
  void initState() {
    super.initState();
    readPasswall(ref.read(appStateProvider), widget.kind).then((p) {
      if (mounted && p.global.isNotEmpty) setState(() => _p = p);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) return const SizedBox.shrink();
    final node = p.currentNode;
    final live = p.enabled && p.running == true;
    return KsRow(
      title: '${widget.kind.title} proxy',
      subtitle: [
        !p.enabled ? 'Off' : (live ? 'Running' : 'On, not running'),
        if (node != null) PasswallInfo.nodeName(node),
      ].join(' · '),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PasswallScreen(kind: widget.kind)),
      ),
    );
  }
}

class PasswallScreen extends ConsumerStatefulWidget {
  const PasswallScreen({super.key, this.kind = PasswallKind.v2});
  final PasswallKind kind;

  @override
  ConsumerState<PasswallScreen> createState() => _PasswallScreenState();
}

class _PasswallScreenState extends ConsumerState<PasswallScreen> {
  PasswallInfo? _p;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  AppState get _app => ref.read(appStateProvider);
  String get _config => widget.kind.config;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await readPasswall(_app, widget.kind);
      if (!mounted) return;
      setState(() {
        _p = p;
        _error = p.global.isEmpty ? 'No $_config settings' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _say(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _apply(Map<String, String> values) async {
    final section = _p?.global['.name']?.toString();
    if (section == null) return;
    setState(() => _busy = true);
    try {
      await noobUciSet(_app, _config, section, values);
      await noobService(_app, _config, 'restart');
    } catch (e) {
      if (mounted) _say("The router didn't take that: $e");
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _remove(String id) async {
    final ks = context.ks;
    final node = _p?.nodes.where((n) => n['.name'] == id).firstOrNull;
    if (node == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text(
          'Remove ${PasswallInfo.nodeName(node)}?',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        content: Text(
          'Its address and keys are deleted from the router. Add it again '
          'from its share link if you need it.',
          style: KeystoneType.body(ks.tx2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Remove', style: TextStyle(color: ks.bad)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await noobCall(_app, 'uci', 'delete', {'config': _config, 'section': id});
      await noobUciCommit(_app, _config);
    } catch (e) {
      if (mounted) _say("The router didn't remove it: $e");
    }
    await _load();
    if (mounted) setState(() => _busy = false);
  }

  Future<String?> _addLinks(List<String> links) async {
    final before = _p?.nodes.length ?? 0;
    try {
      await noobCall(_app, 'file', 'write', {
        'path': '/tmp/links.conf',
        'data': links.join('\n'),
      });
      await noobCall(_app, 'file', 'exec', {
        'command': '/bin/sh',
        'params': [
          '-c',
          'exec 0<&- 1>&- 2>&-; '
              'lua /usr/share/$_config/subscribe.lua add default &',
        ],
      });
    } catch (e) {
      return "Couldn't hand the links to the router: $e";
    }
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      PasswallInfo p;
      try {
        p = await readPasswall(_app, widget.kind);
      } catch (_) {
        continue;
      }
      if (p.nodes.length > before) {
        if (mounted) {
          setState(() => _p = p);
          Navigator.of(context).pop();
          final n = p.nodes.length - before;
          _say('Added $n node${n == 1 ? '' : 's'}.');
        }
        return null;
      }
    }
    return "${widget.kind.title} didn't add anything. Check the link is "
        'complete and one it supports.';
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Back', style: KeystoneType.body(ks.mu)),
      ),
      body: _body(ks),
    );
  }

  Widget _body(KeystoneColors ks) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final p = _p;
    if (_error != null || p == null || p.global.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text(widget.kind.title, style: KeystoneType.title(ks.tx)),
          const SizedBox(height: 12),
          Text(
            "${widget.kind.title} isn't set up on this router yet. Open it "
            'once under Services in LuCI to create its settings.',
            style: KeystoneType.body(ks.mu),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: KeystoneType.caption(ks.mu)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            child: const Text('Try again'),
          ),
        ],
      );
    }
    final g = p.global;
    return RefreshIndicator(
      onRefresh: _load,
      child: PasswallView(
        title: widget.kind.title,
        on: p.enabled,
        running: p.running,
        busy: _busy,
        currentId: g[p.nodeKey]?.toString(),
        routerTraffic: g['localhost_proxy'] == '1',
        lanTraffic: g['client_proxy'] != '0',
        nodes: [
          for (final n in p.nodes)
            PasswallNode(
              id: n['.name'].toString(),
              name: PasswallInfo.nodeName(n),
              rules: noobValue(n['protocol']) == '_shunt',
              line: [
                noobValue(n['protocol']) ?? noobValue(n['type']),
                [
                  noobValue(n['address']),
                  noobValue(n['port']),
                ].whereType<String>().join(':'),
              ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            ),
        ],
        onToggle: (v) => _apply({'enabled': v ? '1' : '0'}),
        onRouterTraffic: (v) => _apply({'localhost_proxy': v ? '1' : '0'}),
        onLanTraffic: (v) => _apply({'client_proxy': v ? '1' : '0'}),
        onNode: (id, a) => switch (a) {
          PasswallNodeAction.use => _apply(p.useNode(id)),
          PasswallNodeAction.remove => _remove(id),
        },
        onAdd: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: ks.sheet,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          builder: (_) =>
              SafeArea(top: false, child: AddNodesSheet(onAdd: _addLinks)),
        ),
      ),
    );
  }
}
