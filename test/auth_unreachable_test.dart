import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/auth_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/utils/router_support.dart';

class _Api extends MockApiService {
  _Api(this.result);
  final AuthResult result;
  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async => result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  test('nothing answering like LuCI is unreachable, not a wrong password', () {
    final auth = RealAuthService(
      _Api(AuthResult.unreachable()),
      canReach: (_, _) async => true,
    );
    expect(
      auth.login('192.168.1.1', 'root', 'pw', false),
      throwsA(isA<RouterUnreachableException>()),
    );
  });

  test('a rejected password still just fails', () async {
    final auth = RealAuthService(
      _Api(AuthResult.invalidCredentials()),
      canReach: (_, _) async => true,
    );
    await auth.login('192.168.1.1', 'root', 'pw', false);
    expect(auth.isAuthenticated, isFalse);
  });
}
