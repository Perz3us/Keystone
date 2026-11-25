import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class ShortcutChoice {
  const ShortcutChoice(this.id, this.label, this.icon);
  final String id;
  final String label;
  final IconData icon;
}

const _key = 'home_shortcuts';
const maxShortcuts = 4;

Future<List<String>?> loadShortcutIds() async =>
    (await SharedPreferences.getInstance()).getStringList(_key);

Future<void> saveShortcutIds(List<String> ids) async =>
    (await SharedPreferences.getInstance()).setStringList(_key, ids);

List<T> pickShortcuts<T extends ShortcutChoice>(
  List<T> all,
  List<String>? saved,
) {
  if (saved == null) return all.take(maxShortcuts).toList();
  return [
    for (final id in saved) ...all.where((c) => c.id == id),
  ].take(maxShortcuts).toList();
}

class ShortcutsView extends StatefulWidget {
  const ShortcutsView({
    super.key,
    required this.all,
    required this.chosen,
    required this.onDone,
  });

  final List<ShortcutChoice> all;
  final List<String> chosen;
  final ValueChanged<List<String>> onDone;

  @override
  State<ShortcutsView> createState() => _ShortcutsViewState();
}

class _ShortcutsViewState extends State<ShortcutsView> {
  late final List<ShortcutChoice> _order = [
    for (final id in widget.chosen) ...widget.all.where((c) => c.id == id),
    ...widget.all.where((c) => !widget.chosen.contains(c.id)),
  ];
  late final Set<String> _on = {...widget.chosen};

  void _toggle(ShortcutChoice c) => setState(() {
    if (_on.contains(c.id)) {
      _on.remove(c.id);
    } else if (_on.length < maxShortcuts) {
      _on.add(c.id);
    }
  });

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
        title: Text('Home', style: KeystoneType.body(ks.mu)),
        actions: [
          TextButton(
            onPressed: () => widget.onDone([
              for (final c in _order)
                if (_on.contains(c.id)) c.id,
            ]),
            child: Text(
              'Done',
              style: KeystoneType.body(
                ks.ac,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Shortcuts', style: KeystoneType.title(ks.tx)),
                  const SizedBox(height: 4),
                  Text(
                    'Pick up to $maxShortcuts for home. Drag to reorder.',
                    style: KeystoneType.secondary(ks.mu),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                buildDefaultDragHandles: false,
                onReorderItem: (from, to) =>
                    setState(() => _order.insert(to, _order.removeAt(from))),
                children: [
                  for (final (i, c) in _order.indexed)
                    Material(
                      key: ValueKey(c.id),
                      color: ks.bg,
                      child: InkWell(
                        onTap: () => _toggle(c),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: ks.line)),
                          ),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    color: ks.mu,
                                    semanticLabel: 'Drag ${c.label}',
                                  ),
                                ),
                              ),
                              Icon(c.icon, size: 20, color: ks.tx2),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  c.label,
                                  style: KeystoneType.body(ks.tx),
                                ),
                              ),
                              Checkbox(
                                value: _on.contains(c.id),
                                activeColor: ks.ac,
                                onChanged:
                                    _on.contains(c.id) ||
                                        _on.length < maxShortcuts
                                    ? (_) => _toggle(c)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
