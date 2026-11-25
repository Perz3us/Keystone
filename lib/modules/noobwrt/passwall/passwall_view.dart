import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class PasswallNode {
  const PasswallNode({
    required this.id,
    required this.name,
    required this.line,
    this.rules = false,
  });
  final String id;
  final String name;

  final String line;

  final bool rules;
}

enum PasswallNodeAction { use, remove }

List<String> shareLinks(String text) => [
  for (final l in text.split(RegExp(r'[\r\n\s]+')))
    if (RegExp(r'^[a-z0-9+.-]+://\S+$', caseSensitive: false).hasMatch(l)) l,
];

class PasswallView extends StatelessWidget {
  const PasswallView({
    super.key,
    required this.title,
    required this.on,
    required this.running,
    required this.nodes,
    required this.currentId,
    required this.routerTraffic,
    required this.lanTraffic,
    required this.onToggle,
    required this.onNode,
    required this.onAdd,
    required this.onRouterTraffic,
    required this.onLanTraffic,
    this.busy = false,
  });

  final String title;
  final bool on;

  final bool? running;
  final List<PasswallNode> nodes;
  final String? currentId;
  final bool routerTraffic;
  final bool lanTraffic;
  final ValueChanged<bool> onToggle;
  final void Function(String id, PasswallNodeAction a) onNode;
  final VoidCallback onAdd;
  final ValueChanged<bool> onRouterTraffic;
  final ValueChanged<bool> onLanTraffic;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final current = nodes.where((n) => n.id == currentId).firstOrNull;
    final (word, color) = !on
        ? ('Off', ks.mu)
        : running == false
        ? ('On, but not running', ks.warnTx)
        : ('On', ks.ok);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text(title, style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            color: on ? ks.acSoft : ks.node,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: on ? ks.ac : ks.line),
          ),
          child: Row(
            children: [
              Icon(
                on ? Icons.shield_rounded : Icons.shield_outlined,
                color: on ? ks.ac : ks.mu,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(word, style: KeystoneType.bodyStrong(color)),
                    Text(
                      current == null
                          ? 'No node chosen'
                          : 'Using ${current.name}',
                      style: KeystoneType.caption(ks.mu),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Switch(value: on, onChanged: onToggle),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('What goes through it', style: KeystoneType.secondary(ks.mu)),
        _switch(
          ks,
          'Devices on your network',
          'Phones, laptops and the rest',
          lanTraffic,
          onLanTraffic,
        ),
        _switch(
          ks,
          'The router itself',
          'Updates and anything the router fetches',
          routerTraffic,
          onRouterTraffic,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Nodes · ${nodes.length}',
                style: KeystoneType.secondary(ks.mu),
              ),
            ),
            TextButton.icon(
              onPressed: busy ? null : onAdd,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              icon: Icon(Icons.add_rounded, size: 18, color: ks.ac),
              label: Text('Add', style: KeystoneType.secondary(ks.ac)),
            ),
          ],
        ),
        if (nodes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No nodes yet. Add one from a share link.',
              style: KeystoneType.body(ks.mu),
            ),
          ),
        for (final n in nodes) _node(ks, n, n.id == currentId),
      ],
    );
  }

  Widget _switch(
    KeystoneColors ks,
    String title,
    String sub,
    bool value,
    ValueChanged<bool> onChanged,
  ) => Container(
    constraints: const BoxConstraints(minHeight: 60),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: ks.line)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: KeystoneType.body(ks.tx)),
              Text(sub, style: KeystoneType.caption(ks.mu)),
            ],
          ),
        ),
        Switch(value: value, onChanged: busy ? null : onChanged),
      ],
    ),
  );

  Widget _node(KeystoneColors ks, PasswallNode n, bool current) => InkWell(
    onTap: busy || current ? null : () => onNode(n.id, PasswallNodeAction.use),
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        children: [
          Icon(
            current
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            color: current ? ks.ac : ks.mu,
            size: 20,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n.name, style: KeystoneType.body(ks.tx)),
                Text(
                  n.rules ? 'Rules: picks a node per site' : n.line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeystoneType.caption(ks.mu),
                ),
              ],
            ),
          ),
          PopupMenuButton<PasswallNodeAction>(
            tooltip: 'Options for ${n.name}',
            enabled: !busy,
            icon: Icon(Icons.more_vert_rounded, color: ks.mu),
            color: ks.sheet,
            onSelected: (a) => onNode(n.id, a),
            itemBuilder: (_) => [
              if (!current)
                PopupMenuItem(
                  value: PasswallNodeAction.use,
                  child: Text('Use this node', style: KeystoneType.body(ks.tx)),
                ),
              PopupMenuItem(
                value: PasswallNodeAction.remove,
                enabled: !current,
                child: Text(
                  current ? "Remove (it's in use)" : 'Remove',
                  style: KeystoneType.body(current ? ks.mu : ks.bad),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class AddNodesSheet extends StatefulWidget {
  const AddNodesSheet({super.key, required this.onAdd});
  final Future<String?> Function(List<String> links) onAdd;

  @override
  State<AddNodesSheet> createState() => _AddNodesSheetState();
}

class _AddNodesSheetState extends State<AddNodesSheet> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final links = shareLinks(_text.text);
    if (links.isEmpty) {
      setState(
        () => _error =
            'Paste a share link that starts with something like vless:// '
            'or ss://.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onAdd(links);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final n = shareLinks(_text.text).length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text('Add nodes', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 4),
          Text(
            'Paste share links, one per line: vless, vmess, trojan, ss, '
            'hysteria2 and the rest Passwall knows.',
            style: KeystoneType.secondary(ks.mu),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 8,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            style: KeystoneType.secondary(ks.tx),
            decoration: InputDecoration(
              hintText: 'vless://…',
              filled: true,
              fillColor: ks.node,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ks.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ks.line),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final d = await Clipboard.getData(Clipboard.kTextPlain);
                if (d?.text == null) return;
                _text.text = d!.text!;
                setState(() {});
              },
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              icon: Icon(Icons.content_paste_rounded, size: 18, color: ks.ac),
              label: Text('Paste', style: KeystoneType.secondary(ks.ac)),
            ),
          ),
          if (_error != null)
            Text(_error!, style: KeystoneType.secondary(ks.bad)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _add,
            style: FilledButton.styleFrom(
              backgroundColor: ks.tx,
              foregroundColor: ks.bg,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ks.bg,
                    ),
                  )
                : Text(
                    n <= 1 ? 'Add node' : 'Add $n nodes',
                    style: KeystoneType.bodyStrong(ks.bg),
                  ),
          ),
        ],
      ),
    );
  }
}
