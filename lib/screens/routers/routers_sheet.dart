import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/routers/routers_view.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/utils/url_parser.dart';

Future<T?> _sheet<T>(BuildContext context, Widget child) {
  final ks = context.ks;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: ks.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => SafeArea(top: false, child: child),
  );
}

Future<void> showRoutersSheet(
  BuildContext context, {
  bool fromSignIn = false,
}) => _sheet(context, _RoutersSheet(fromSignIn: fromSignIn));

class _RoutersSheet extends ConsumerStatefulWidget {
  const _RoutersSheet({required this.fromSignIn});
  final bool fromSignIn;

  @override
  ConsumerState<_RoutersSheet> createState() => _RoutersSheetState();
}

class _RoutersSheetState extends ConsumerState<_RoutersSheet> {
  String? _switching;
  String? _error;
  String? _note;

  void _connected() {
    final nav = Navigator.of(context, rootNavigator: true);
    if (widget.fromSignIn) {
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (_) => false,
      );
    } else {
      nav.popUntil((r) => r.isFirst);
      ref.read(appStateProvider).requestTab(0);
    }
  }

  Future<void> _select(String id, {bool force = false}) async {
    final app = ref.read(appStateProvider);
    if (!force &&
        id == app.selectedRouter?.id &&
        app.hasActiveSession &&
        !widget.fromSignIn) {
      return _connected();
    }
    setState(() {
      _switching = id;
      _error = null;
    });
    await app.selectRouter(id, context: context, force: force);
    if (!mounted) return;
    if (app.hasActiveSession) return _connected();
    setState(() {
      _switching = null;
      _error =
          app.errorMessage ??
          "Couldn't connect. Check that this phone is on that router's "
              'network and the password is right.';
    });
  }

  Future<void> _rename(model.Router r) async {
    final ks = context.ks;
    final text = TextEditingController(text: r.name ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text('Rename router', style: KeystoneType.sheetTitle(ks.tx)),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(
            hintText: routerDisplayName(r.copyWith(name: '')),
            helperText: 'Leave empty to use the model name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, text.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => text.dispose());
    if (saved == null) return;
    await ref
        .read(appStateProvider)
        .updateRouterName(r.id, saved.isEmpty ? null : saved);
    if (mounted) setState(() {});
  }

  Future<void> _remove(model.Router r) async {
    final ks = context.ks;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text(
          'Remove ${routerDisplayName(r)}?',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        content: Text(
          'Keystone forgets its address and password. The router itself '
          "isn't changed.",
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
    final app = ref.read(appStateProvider);
    final wasCurrent = app.selectedRouter?.id == r.id;
    await app.removeRouter(r.id);
    if (!mounted) return;
    if (wasCurrent && !widget.fromSignIn) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushNamedAndRemoveUntil('/login', (_) => false);
      return;
    }
    setState(() {});
  }

  (String? error, String host, bool https) _parse(String input) {
    final p = UrlParser.parse(input);
    if (!p.isValid) {
      return (p.error ?? "That address doesn't look right.", '', false);
    }
    return (null, p.hostWithPort, p.useHttps);
  }

  Future<void> _edit(model.Router r) => _sheet(
    context,
    RouterForm(
      title: 'Change ${routerDisplayName(r)}',
      saveLabel: 'Save',
      initial: RouterFormValues(
        name: r.name ?? '',
        address: '${r.useHttps ? 'https://' : ''}${r.ipAddress}',
        user: r.username,
        password: r.password,
      ),
      onSave: (v) async {
        final (error, host, https) = _parse(v.address);
        if (error != null) return error;
        final app = ref.read(appStateProvider);
        final id = RouterService.generateId(host, v.user, https);
        if (id != r.id && app.routers.any((x) => x.id == id)) {
          return 'You already have a router with that address and username.';
        }
        final current = app.selectedRouter?.id == r.id;
        final moved =
            host != r.ipAddress ||
            https != r.useHttps ||
            v.user != r.username ||
            v.password != r.password;
        await app.updateRouter(
          r.copyWith(
            id: id,
            ipAddress: host,
            username: v.user,
            password: v.password,
            useHttps: https,
            name: v.name.isEmpty ? null : v.name,
            clearName: v.name.isEmpty,
          ),
          oldId: r.id,
        );
        if (mounted) {
          Navigator.of(context).pop();
          setState(() {});
          if (current && moved) unawaited(_select(id, force: true));
        }
        return null;
      },
    ),
  );

  Future<void> _add() => _sheet(
    context,
    RouterForm(
      title: 'Add a router',
      saveLabel: 'Connect',
      onSave: (v) async {
        final (error, host, https) = _parse(v.address);
        if (error != null) return error;
        final app = ref.read(appStateProvider);
        if (app.routers.any(
          (x) => x.id == RouterService.generateId(host, v.user, https),
        )) {
          return 'That router is already in your list.';
        }
        final ok = await app.login(
          host,
          v.user,
          v.password,
          https,
          fromRouter: false,
          routerName: v.name.isEmpty ? null : v.name,
          context: context,
        );
        if (!ok) {
          return app.errorMessage ??
              "Couldn't sign in. Check the address and password.";
        }
        if (mounted) _connected();
        return null;
      },
    ),
  );

  Future<void> _export() async {
    final app = ref.read(appStateProvider);
    try {
      final r = await app.exportRouterProfiles();
      if (mounted && r != null) {
        setState(
          () => _note =
              'Saved as ${r.filePath.split('/').last}. '
              'It holds passwords, so keep it private.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _note = "Couldn't save the backup: $e");
    }
  }

  Future<void> _import() async {
    final app = ref.read(appStateProvider);
    final r = await app.importRouterProfilesFromFile();
    if (!mounted || r.errorMessage == 'No file selected.') return;
    await app.loadRouters();
    if (!mounted) return;
    setState(
      () => _note = r.success
          ? 'Added ${r.importedCount}, updated ${r.updatedCount}.'
          : r.errorMessage ?? "Couldn't read that backup.",
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final current = app.selectedRouter?.id;
    final routers = app.routers;
    model.Router byId(String id) => routers.firstWhere((r) => r.id == id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: RoutersView(
            routers: [
              for (final r in routers)
                RouterEntry(
                  id: r.id,
                  name: routerDisplayName(r),
                  line:
                      '${r.useHttps ? 'https://' : ''}${r.ipAddress} · '
                      '${r.username}',
                  selected: r.id == current && !widget.fromSignIn,
                ),
            ],
            switchingId: _switching,
            error: _error,
            onSelect: _select,
            onAdd: _add,
            onAction: (id, a) => switch (a) {
              RouterAction.rename => _rename(byId(id)),
              RouterAction.edit => _edit(byId(id)),
              RouterAction.remove => _remove(byId(id)),
            },
            onExport: app.reviewerModeEnabled || routers.isEmpty
                ? null
                : _export,
            onImport: app.reviewerModeEnabled ? null : _import,
          ),
        ),
        if (_note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(
              _note!,
              textAlign: TextAlign.center,
              style: KeystoneType.caption(ks.mu),
            ),
          ),
      ],
    );
  }
}
