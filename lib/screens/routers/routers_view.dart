import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class RouterEntry {
  const RouterEntry({
    required this.id,
    required this.name,
    required this.line,
    this.selected = false,
  });
  final String id;
  final String name;

  final String line;
  final bool selected;
}

enum RouterAction { rename, edit, remove }

class RoutersView extends StatelessWidget {
  const RoutersView({
    super.key,
    required this.routers,
    required this.onSelect,
    required this.onAction,
    required this.onAdd,
    this.switchingId,
    this.error,
    this.onExport,
    this.onImport,
  });

  final List<RouterEntry> routers;
  final ValueChanged<String> onSelect;
  final void Function(String id, RouterAction action) onAction;
  final VoidCallback onAdd;

  final String? switchingId;
  final String? error;
  final VoidCallback? onExport;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      children: [
        Text('Routers', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text('Tap one to switch to it.', style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 12),
        for (final r in routers) _row(context, ks, r),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: KeystoneType.secondary(ks.bad)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: switchingId == null ? onAdd : null,
          style: FilledButton.styleFrom(
            backgroundColor: ks.tint,
            foregroundColor: ks.tx,
            minimumSize: const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add_rounded, size: 20),
          label: Text('Add a router', style: KeystoneType.bodyStrong(ks.tx)),
        ),
        if (onExport != null || onImport != null) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (onExport != null)
                TextButton(
                  onPressed: onExport,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(
                    'Back up this list',
                    style: KeystoneType.secondary(ks.ac),
                  ),
                ),
              if (onImport != null)
                TextButton(
                  onPressed: onImport,
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  child: Text(
                    'Restore from a backup',
                    style: KeystoneType.secondary(ks.ac),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, KeystoneColors ks, RouterEntry r) {
    final busy = switchingId == r.id;
    return InkWell(
      onTap: switchingId == null ? () => onSelect(r.id) : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: r.selected ? ks.acSoft : ks.node,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: r.selected ? ks.ac : ks.line),
        ),
        child: Row(
          children: [
            Icon(Icons.router_outlined, color: r.selected ? ks.ac : ks.tx2),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: KeystoneType.body(ks.tx)),
                  Text(
                    busy ? 'Connecting…' : r.line,
                    style: KeystoneType.caption(busy ? ks.ac : ks.mu),
                  ),
                ],
              ),
            ),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (r.selected)
              Semantics(
                label: 'Current router',
                child: Icon(Icons.check_rounded, color: ks.ac),
              ),
            PopupMenuButton<RouterAction>(
              tooltip: 'Options for ${r.name}',
              enabled: switchingId == null,
              icon: Icon(Icons.more_vert_rounded, color: ks.mu),
              color: ks.sheet,
              onSelected: (a) => onAction(r.id, a),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: RouterAction.rename,
                  child: Text('Rename', style: KeystoneType.body(ks.tx)),
                ),
                PopupMenuItem(
                  value: RouterAction.edit,
                  child: Text(
                    'Change address or password',
                    style: KeystoneType.body(ks.tx),
                  ),
                ),
                PopupMenuItem(
                  value: RouterAction.remove,
                  child: Text('Remove', style: KeystoneType.body(ks.bad)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RouterFormValues {
  const RouterFormValues({
    required this.name,
    required this.address,
    required this.user,
    required this.password,
  });
  final String name;
  final String address;
  final String user;
  final String password;
}

class RouterForm extends StatefulWidget {
  const RouterForm({
    super.key,
    required this.title,
    required this.saveLabel,
    required this.onSave,
    this.initial,
  });

  final String title;
  final String saveLabel;
  final RouterFormValues? initial;
  final Future<String?> Function(RouterFormValues) onSave;

  @override
  State<RouterForm> createState() => _RouterFormState();
}

class _RouterFormState extends State<RouterForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(
    text: widget.initial?.address ?? '',
  );
  late final _user = TextEditingController(
    text: widget.initial?.user ?? 'root',
  );
  late final _password = TextEditingController(
    text: widget.initial?.password ?? '',
  );
  bool _hide = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _address, _user, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_address.text.trim().isEmpty) {
      setState(() => _error = "Enter the router's address, like 192.168.1.1.");
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSave(
      RouterFormValues(
        name: _name.text.trim(),
        address: _address.text.trim(),
        user: _user.text.trim().isEmpty ? 'root' : _user.text.trim(),
        password: _password.text,
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    InputDecoration deco(String label, {String? hint, Widget? suffix}) =>
        InputDecoration(
          labelText: label,
          hintText: hint,
          suffixIcon: suffix,
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
        );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: [
          Text(widget.title, style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: deco(
              'Address',
              hint: '192.168.1.1 or https://router.lan',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _user,
            autocorrect: false,
            decoration: deco('Username'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            autocorrect: false,
            decoration: deco(
              'Password',
              suffix: IconButton(
                tooltip: _hide ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _hide = !_hide),
                icon: Icon(
                  _hide
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _name,
            decoration: deco('Name (optional)', hint: 'Living room'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: KeystoneType.secondary(ks.bad)),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: ks.tx,
              foregroundColor: ks.bg,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: ks.bg,
                    ),
                  )
                : Text(widget.saveLabel, style: KeystoneType.bodyStrong(ks.bg)),
          ),
        ],
      ),
    );
  }
}
