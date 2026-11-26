// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_installer.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _App extends Fake implements AppState {}

class _LiveIo implements RouterIo {
  _LiveIo(this.host);
  final String host;
  String _session = '';
  final log = <String>[];

  Future<dynamic> _call(String obj, String method, Map<String, dynamic> p) async {
    final t = Stopwatch()..start();
    final res = await http.post(
      Uri.parse('http://$host/ubus'),
      body: jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'call',
        'params': [_session, obj, method, p],
      }),
    );
    final r = (jsonDecode(res.body) as Map)['result'] as List;
    if (obj != 'session') log.add('$obj.$method ${t.elapsedMilliseconds}ms');
    return r.length > 1 ? r[1] : null;
  }

  Future<void> login() async {
    _session = '00000000000000000000000000000000';
    final r = await _call('session', 'login', {
      'username': 'root',
      'password': '',
    });
    _session = r['ubus_rpc_session'] as String;
  }

  @override
  Future<(int, String)> exec(String cmd, List<String> args) async {
    final r = await _call('file', 'exec', {'command': cmd, 'params': args});
    return (
      (r['code'] as int?) ?? 0,
      '${r['stdout'] ?? ''}${r['stderr'] ?? ''}'.trim(),
    );
  }

  @override
  Future<void> write(String path, List<int> bytes) => _call('file', 'write', {
    'path': path,
    'data': base64Encode(bytes),
    'base64': true,
  });

  @override
  Future<String?> read(String path) async =>
      (await _call('file', 'read', {'path': path}))?['data']?.toString();
}

void main() {
  final host = Platform.environment['ROUTER'] ?? '192.168.1.1';

  test('install and reinstall on a real router', () async {
    SharedPreferences.setMockInitialValues({});
    final io = _LiveIo(host);
    await io.login();
    HelperInstaller make(String p, [List<HelperInstaller>? needs]) =>
        HelperInstaller(
          _App(),
          package: p,
          io: io,
          needs: needs,
          version: () async => (await io.read('/usr/share/$p/version'))?.trim(),
        );
    final alerts = make('keystone-alerts', [make('keystone-history')]);

    final t = Stopwatch()..start();
    await alerts.install();
    print('install (up to date): ${t.elapsedMilliseconds}ms ${io.log}');

    io.log.clear();
    t.reset();
    await make('keystone-alerts', const []).goBack();
    print('reinstall: ${t.elapsedMilliseconds}ms ${io.log}');
    print('version: ${await make('keystone-alerts', const []).installed()}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
