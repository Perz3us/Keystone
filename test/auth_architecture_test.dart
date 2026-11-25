// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/auth_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});

  group('Unified Auth Architecture', () {
    test('AuthResult factory constructors set correct properties', () {
      final successResult = AuthResult.success(
        'test_token_123',
        actualUseHttps: true,
      );
      expect(successResult.status, AuthStatus.success);
      expect(successResult.isSuccess, isTrue);
      expect(successResult.token, 'test_token_123');
      expect(successResult.actualUseHttps, isTrue);

      final invalidResult = AuthResult.invalidCredentials();
      expect(invalidResult.status, AuthStatus.invalidCredentials);
      expect(invalidResult.isSuccess, isFalse);
      expect(
        invalidResult.errorMessage,
        contains('Invalid username or password'),
      );

      final unreachableResult = AuthResult.unreachable();
      expect(unreachableResult.status, AuthStatus.unreachable);
      expect(unreachableResult.isSuccess, isFalse);

      final unknownResult = AuthResult.unknownError('Network error');
      expect(unknownResult.status, AuthStatus.unknownError);
      expect(unknownResult.isSuccess, isFalse);
      expect(unknownResult.errorMessage, 'Network error');
    });

    test('RealAuthService delegates to IApiService.authenticate', () async {
      final mockApi = MockApiService();
      final authService = RealAuthService(
        mockApi,
        canReach: (_, _) async => true,
      );

      expect(authService.isAuthenticated, isFalse);

      await authService.login('192.168.1.1', 'root', 'password', false);

      expect(authService.isAuthenticated, isTrue);
      expect(authService.sysauth, 'mock_sysauth_token_12345');
      expect(authService.ipAddress, '192.168.1.1');
      expect(authService.useHttps, isFalse);
    });

    test('RealAuthService tryAutoLogin delegates to login flow', () async {
      final mockApi = MockApiService();
      final authService = RealAuthService(
        mockApi,
        canReach: (_, _) async => true,
      );

      final success = await authService.tryAutoLogin(
        '192.168.1.1',
        'root',
        'password',
        false,
      );

      expect(success, isTrue);
      expect(authService.isAuthenticated, isTrue);
      expect(authService.sysauth, 'mock_sysauth_token_12345');
    });

    test('AppState.setError normalizes empty or blank strings to null', () {
      final appState = AppState.instance;

      appState.setError('Something went wrong');
      expect(appState.errorMessage, equals('Something went wrong'));

      appState.setError('');
      expect(appState.errorMessage, isNull);

      appState.setError('   ');
      expect(appState.errorMessage, isNull);

      appState.setError(null);
      expect(appState.errorMessage, isNull);
    });

    test(
      'AppState.hasActiveSession reflects authentication and reviewer mode',
      () async {
        final appState = AppState.instance;
        expect(appState.hasActiveSession, isFalse);

        await appState.setReviewerMode(true);
        expect(appState.reviewerModeEnabled, isTrue);
        expect(appState.hasActiveSession, isTrue);

        await appState.setReviewerMode(false);
        expect(appState.reviewerModeEnabled, isFalse);
        expect(appState.hasActiveSession, isFalse);
      },
    );

    test(
      'RealAuthService.logout clears sysauth while preserving saved profiles',
      () async {
        final mockApi = MockApiService();
        final authService = RealAuthService(
          mockApi,
          canReach: (_, _) async => true,
        );

        await authService.login('192.168.1.1', 'root', 'password', false);
        expect(authService.isAuthenticated, isTrue);

        await authService.logout();
        expect(authService.isAuthenticated, isFalse);
        expect(authService.sysauth, isNull);
      },
    );

    test('RealAuthService registers onSessionRenew on RealApiService', () {
      final realApi = RealApiService();
      expect(realApi.onSessionRenew, isNull);

      final authService = RealAuthService(
        realApi,
        canReach: (_, _) async => true,
      );
      expect(authService, isNotNull);
      expect(realApi.onSessionRenew, isNotNull);
    });

    test(
      'RealApiService transparently renews session on access denied',
      () async {
        final realApi = RealApiService();
        int renewalCalls = 0;

        realApi.onSessionRenew = (ip, useHttps) async {
          renewalCalls++;
          return 'renewed_token_xyz';
        };

        final renewed = await realApi.onSessionRenew!('192.168.1.1', false);
        expect(renewed, 'renewed_token_xyz');
        expect(renewalCalls, 1);
      },
    );
  });
}
