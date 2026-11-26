// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart';
import 'package:yet_another_luci_app/modules/noobwrt/datacap/data_plan_client.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _Api extends Fake implements IApiService {
  _Api(this.reply);
  final Object reply;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    BuildContext? context,
  }) async {
    final r = reply;
    if (r is Exception) throw r;
    return r;
  }
}

class _App extends Fake implements AppState {
  _App(this.apiService);

  @override
  final IApiService apiService;

  @override
  String get sysauth => 'token';

  @override
  Router get selectedRouter => Router(
    id: '1',
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );
}

Future<String> _error(int code) async {
  try {
    await noobCall(_App(_Api([code])), 'file', 'read', {'path': '/x'});
  } on NoobRpcError catch (e) {
    return e.message;
  }
  return 'no error';
}

void main() {
  test('ubus status codes map to their real names', () async {
    expect(await _error(1), 'Invalid command');
    expect(await _error(2), 'Invalid argument');
    expect(await _error(3), 'Method not found');
    expect(await _error(4), 'Not found');
    expect(await _error(5), 'No data');
    expect(await _error(6), 'Permission denied');
    expect(await _error(7), 'Timed out');
    expect(await _error(8), 'Not supported');
    expect(await _error(42), 'Error 42');
  });

  test('a zero status returns the data', () async {
    final r = await noobCall(
      _App(
        _Api([
          0,
          {'a': 1},
        ]),
      ),
      'file',
      'read',
    );
    expect(r, {'a': 1});
  });

  test('a package that is not installed reads as missing', () async {
    Future<Object> fail(String message) async {
      try {
        await noobCall(
          _App(_Api(Exception('RPC error: $message'))),
          'keystone.alerts',
          'info',
        );
      } catch (e) {
        return e;
      }
      return 'no error';
    }

    final missing = await fail('Object not found');
    expect(missing, isA<NoobRpcError>());
    expect((missing as NoobRpcError).message, 'Not found');
    expect(keystoneMissing(missing), isTrue);
    expect(
      ((await fail('Method not found')) as NoobRpcError).message,
      'Method not found',
    );
    final slow = await fail('Timeout');
    expect(slow, same(NoobRpcError.slow));
    expect(keystoneMissing(slow), isFalse);
  });
}
