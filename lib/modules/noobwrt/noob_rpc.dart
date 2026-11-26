// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:yet_another_luci_app/state/app_state.dart';

class NoobRpcError implements Exception {
  final String message;
  const NoobRpcError(this.message);

  static const refused = NoobRpcError(
    'the router refused. Sign out and back in; if it keeps happening, '
    "this login isn't allowed to change it.",
  );
  @override
  String toString() => message;
}

const _ubusErrors = {
  1: 'Invalid command',
  2: 'Invalid argument',
  3: 'Method not found',
  4: 'Not found',
  5: 'No data',
  6: 'Permission denied',
  7: 'Timed out',
  8: 'Not supported',
};

Future<Map<String, dynamic>> noobCall(
  AppState app,
  String object,
  String method, [
  Map<String, dynamic>? params,
]) async {
  final api = app.apiService;
  final router = app.selectedRouter;
  if (api == null || router == null || (app.sysauth ?? '').isEmpty) {
    throw const NoobRpcError('Not logged in to a router');
  }
  final Object? res;
  try {
    res = await api.call(
      router.ipAddress,
      app.sysauth!,
      router.useHttps,
      object: object,
      method: method,
      params: params,
    );
  } on Exception catch (e) {
    final text = '$e'.toLowerCase();
    if (text.contains('access denied')) {
      throw NoobRpcError.refused;
    }
    if (text.contains('object not found')) throw NoobRpcError(_ubusErrors[4]!);
    if (text.contains('method not found')) throw NoobRpcError(_ubusErrors[3]!);
    rethrow;
  }
  if (res is List && res.isNotEmpty) {
    final code = res[0];
    if (code is int && code != 0) {
      throw NoobRpcError(_ubusErrors[code] ?? 'Error $code');
    }
    final data = res.length > 1 ? res[1] : null;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }
  throw const NoobRpcError('No reply from the router');
}

Future<String> noobReadFile(AppState app, String path) async {
  final r = await noobCall(app, 'file', 'read', {'path': path});
  return r['data']?.toString() ?? '';
}

Future<Map<String, dynamic>> noobReadJson(AppState app, String path) async {
  final data = jsonDecode(await noobReadFile(app, path));
  return data is Map ? Map<String, dynamic>.from(data) : const {};
}

Future<List<String>> noobListDir(AppState app, String path) async {
  final r = await noobCall(app, 'file', 'list', {'path': path});
  final entries = r['entries'];
  if (entries is! List) return const [];
  return [
    for (final e in entries)
      if (e is Map && e['name'] != null) e['name'].toString(),
  ];
}

String? noobValue(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return (s.isEmpty || s == '-') ? null : s;
}

Future<List<Map<String, dynamic>>> noobUciSections(
  AppState app,
  String config,
) async {
  final r = await noobCall(app, 'uci', 'get', {'config': config});
  final values = r['values'];
  if (values is! Map) return const [];
  final list = [
    for (final v in values.values)
      if (v is Map) Map<String, dynamic>.from(v),
  ];
  list.sort((a, b) => ((a['.index'] ?? 0) as num).compareTo(b['.index'] ?? 0));
  return list;
}

Future<void> noobUciSet(
  AppState app,
  String config,
  String section,
  Map<String, String> values,
) async {
  await noobCall(app, 'uci', 'set', {
    'config': config,
    'section': section,
    'values': values,
  });
  await noobUciCommit(app, config);
}

Future<void> noobUciCommit(AppState app, String config) async {
  try {
    await noobCall(app, 'uci', 'commit', {'config': config});
  } on NoobRpcError catch (e) {
    if (!identical(e, NoobRpcError.refused)) rethrow;
    await noobCall(app, 'uci', 'apply', {'rollback': false});
  }
}

Future<Map<String, dynamic>> noobServices(AppState app) =>
    noobCall(app, 'rc', 'list');

Future<void> noobService(AppState app, String name, String action) =>
    noobCall(app, 'rc', 'init', {'name': name, 'action': action});
