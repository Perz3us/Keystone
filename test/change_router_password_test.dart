// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/services/auth_service.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/widgets/change_router_password_dialog.dart';
import 'package:yet_another_luci_app/widgets/password_strength_meter.dart';

class ControllableMockApiService extends MockApiService {
  SetPasswordRpcResponse setPasswordResponse =
      const SetPasswordRpcResponse.success();
  AuthResult? nextAuthResult;
  Map<String, AuthResult> authResultsByPassword = {};
  bool boardInfoSucceeds = true;
  int destroySessionCallCount = 0;

  @override
  Future<SetPasswordRpcResponse> setRouterPassword(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    String username = 'root',
    required String newPassword,
  }) async {
    return setPasswordResponse;
  }

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (authResultsByPassword.containsKey(password)) {
      return authResultsByPassword[password]!;
    }
    if (nextAuthResult != null) {
      return nextAuthResult!;
    }
    return AuthResult.success('token_for_$password');
  }

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
    if (object == 'session' && method == 'destroy') {
      destroySessionCallCount++;
      return [0, 'success'];
    }
    if (object == 'system' && method == 'board') {
      if (!boardInfoSucceeds) return [6, 'Access denied'];
      return [
        0,
        {'hostname': 'TestRouter', 'model': 'OpenWrt'},
      ];
    }
    return super.call(
      ipAddress,
      sysauth,
      useHttps,
      object: object,
      method: method,
      params: params,
      context: context,
    );
  }
}

class ControllableRealApiService extends RealApiService {
  Completer<AuthResult>? authCompleter;

  @override
  Future<AuthResult> authenticate(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  }) async {
    if (authCompleter != null) {
      return authCompleter!.future;
    }
    return const AuthResult(status: AuthStatus.success, token: 'renewed_token');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Capability Detection', () {
    test(
      'hasSetPasswordRpc returns true only when ubusMethods[luci] contains setPassword',
      () {
        final capsWithMethod = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'luci', 'system'},
          ubusMethods: {
            'luci': ['setPassword', 'getLEDs'],
          },
          probedAt: DateTime.now(),
        );
        expect(capsWithMethod.hasSetPasswordRpc, isTrue);

        final capsWithoutMethod = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'luci', 'system'},
          ubusMethods: {
            'luci': ['getLEDs'],
          },
          probedAt: DateTime.now(),
        );
        expect(capsWithoutMethod.hasSetPasswordRpc, isFalse);

        final capsNoLuci = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: {'system'},
          ubusMethods: {},
          probedAt: DateTime.now(),
        );
        expect(capsNoLuci.hasSetPasswordRpc, isFalse);
      },
    );

    test('RouterCapabilities.mock exposes hasSetPasswordRpc', () {
      final mockCaps = RouterCapabilities.mock();
      expect(mockCaps.hasSetPasswordRpc, isTrue);
    });
  });

  group('Auth Epoch & Stale Renewal Barrier', () {
    test(
      'Auth epoch barrier suppresses in-flight renewals with old credentials',
      () async {
        final apiService = ControllableRealApiService();
        final authService = RealAuthService(
          apiService,
          canReach: (_, _) async => true,
        );

        final secureStorage = SecureStorageService();
        await secureStorage.saveCredentials(
          ipAddress: '192.168.1.1',
          username: 'root',
          password: 'old_password',
          useHttps: false,
        );

        expect(authService.authEpoch, equals(0));

        final authCompleter = Completer<AuthResult>();
        apiService.authCompleter = authCompleter;

        final renewalFuture = apiService.onSessionRenew?.call(
          '192.168.1.1',
          false,
        );

        await Future<void>.delayed(Duration.zero);

        final epoch = authService.startPasswordTransition();
        expect(epoch, equals(1));
        expect(authService.authEpoch, equals(1));

        authCompleter.complete(
          const AuthResult(status: AuthStatus.success, token: 'stale_token'),
        );

        final renewalToken = await renewalFuture;

        expect(renewalToken, isNull);
        expect(authService.sysauth, isNot(equals('stale_token')));

        authService.completePasswordTransition(
          newToken: 'new_verified_token',
          newPassword: 'new_secure_password',
          ipAddress: '192.168.1.1',
          useHttps: false,
        );
        expect(authService.authEpoch, equals(2));
        expect(authService.sysauth, equals('new_verified_token'));
      },
    );

    test(
      'Cancelling password transition advances epoch and disengages barrier',
      () {
        final apiService = ControllableRealApiService();
        final authService = RealAuthService(
          apiService,
          canReach: (_, _) async => true,
        );

        authService.startPasswordTransition();
        expect(authService.authEpoch, equals(1));

        authService.cancelPasswordTransition();
        expect(authService.authEpoch, equals(2));
      },
    );
  });

  group('10-State Password Transition State Machine', () {
    late AppState appState;
    late ControllableMockApiService mockApi;

    setUp(() async {
      mockApi = ControllableMockApiService();
      appState = AppState.instance;
      await appState.setReviewerMode(true);
      appState.setApiServiceForTesting(mockApi);
    });

    test('Validation prechecks reject invalid input before RPC', () async {
      final resultMismatch = await appState.changeRouterPassword(
        currentPassword: 'wrong_current_password',
        newPassword: 'new_password_123',
      );
      expect(resultMismatch.isSuccess, isFalse);
      expect(resultMismatch.status, equals(ChangePasswordStatus.failed));
      expect(resultMismatch.errorMessage, contains('does not match'));

      final routerWithPass = appState.selectedRouter!.copyWith(
        password: 'CurrentPass123',
      );
      appState.routerService?.updateRouterInMemory(routerWithPass);

      final resultSame = await appState.changeRouterPassword(
        currentPassword: 'CurrentPass123',
        newPassword: 'CurrentPass123',
      );
      expect(resultSame.isSuccess, isFalse);
      expect(resultSame.status, equals(ChangePasswordStatus.failed));
      expect(resultSame.errorMessage, contains('must be different'));

      final resultEmpty = await appState.changeRouterPassword(
        currentPassword: 'CurrentPass123',
        newPassword: '',
      );
      expect(resultEmpty.isSuccess, isFalse);
      expect(resultEmpty.status, equals(ChangePasswordStatus.failed));
      expect(resultEmpty.errorMessage, contains('cannot be empty'));
    });

    test('Happy Path: Complete 10-state transition succeeds', () async {
      final currentPass = appState.selectedRouter?.password ?? '';
      const newPass = 'ValidNewPass123!';

      final progressStates = <ChangePasswordStatus>[];

      final result = await appState.changeRouterPassword(
        currentPassword: currentPass,
        newPassword: newPass,
        onProgress: (status) => progressStates.add(status),
      );

      expect(result.isSuccess, isTrue);
      expect(result.status, equals(ChangePasswordStatus.success));

      expect(
        progressStates,
        containsAllInOrder([
          ChangePasswordStatus.requesting,
          ChangePasswordStatus.reauthenticating,
          ChangePasswordStatus.verifying,
          ChangePasswordStatus.savingStorage,
        ]),
      );

      expect(mockApi.destroySessionCallCount, greaterThanOrEqualTo(1));

      expect(appState.selectedRouter?.password, equals(newPass));
    });

    test('Router RPC Rejection: Preserves credentials and aborts', () async {
      final currentPass = appState.selectedRouter?.password ?? '';
      const newPass = 'NewPasswordRejected123';

      mockApi.setPasswordResponse = const SetPasswordRpcResponse.rejected(
        'Access denied',
      );

      final result = await appState.changeRouterPassword(
        currentPassword: currentPass,
        newPassword: newPass,
      );

      expect(result.isSuccess, isFalse);
      expect(result.status, equals(ChangePasswordStatus.failed));
      expect(result.errorMessage, contains('Access denied'));

      expect(appState.selectedRouter?.password, equals(currentPass));
      expect(mockApi.destroySessionCallCount, equals(0));
    });

    test(
      'Rejection Router-Side: New auth fails, old auth succeeds restores old session',
      () async {
        final currentPass = appState.selectedRouter?.password ?? '';
        const newPass = 'FailedRouterApply123';

        mockApi.setPasswordResponse = const SetPasswordRpcResponse.success();
        mockApi.authResultsByPassword[newPass] = AuthResult.invalidCredentials(
          'Wrong password',
        );
        mockApi.authResultsByPassword[currentPass] = const AuthResult(
          status: AuthStatus.success,
          token: 'restored_old_token',
        );

        final result = await appState.changeRouterPassword(
          currentPassword: currentPass,
          newPassword: newPass,
        );

        expect(result.isSuccess, isFalse);
        expect(result.status, equals(ChangePasswordStatus.failed));
        expect(
          result.errorMessage,
          contains('Password change was not applied by router'),
        );

        expect(appState.selectedRouter?.password, equals(currentPass));
      },
    );

    test(
      'Ambiguous Failure: Both auth attempts fail enters ambiguous state with zero credential leakage',
      () async {
        const currentPass = 'SecretCurrentPass123';
        const newPass = 'AmbiguousNetworkDrop123';

        final initialRouter = appState.selectedRouter!.copyWith(
          password: currentPass,
        );
        appState.routerService?.updateRouterInMemory(initialRouter);

        mockApi.setPasswordResponse = const SetPasswordRpcResponse.networkError(
          'Socket closed',
        );
        mockApi.authResultsByPassword[newPass] = AuthResult.unreachable(
          'Connection timeout',
        );
        mockApi.authResultsByPassword[currentPass] = AuthResult.unreachable(
          'Connection timeout',
        );

        final result = await appState.changeRouterPassword(
          currentPassword: currentPass,
          newPassword: newPass,
        );

        expect(result.isSuccess, isFalse);
        expect(result.status, equals(ChangePasswordStatus.ambiguous));
        expect(result.errorMessage, isNotNull);

        expect(result.errorMessage, isNot(contains(newPass)));
        expect(result.errorMessage, isNot(contains(currentPass)));

        expect(appState.selectedRouter?.password, equals(currentPass));
      },
    );

    test(
      'retrySaveRouterPassword updates credentials and returns true',
      () async {
        final router = appState.selectedRouter!.copyWith(
          password: 'RetriedNewPassword123',
        );
        final ok = await appState.retrySaveRouterPassword(router);
        expect(ok, isTrue);
        expect(
          appState.selectedRouter?.password,
          equals('RetriedNewPassword123'),
        );
      },
    );
  });

  group('PasswordStrengthMeter', () {
    testWidgets('PasswordStrengthMeter calculates strength and renders bars', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PasswordStrengthMeter(password: 'short')),
        ),
      );
      expect(find.byType(PasswordStrengthMeter), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasswordStrengthMeter(password: 'MyStr0ng!P@ssword'),
          ),
        ),
      );
      expect(find.text('Very strong'), findsOneWidget);
    });
  });

  testWidgets('the change waits for matching, long-enough passwords', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChangeRouterPasswordDialog()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Router password'), findsOneWidget);
    final fields = find.byType(TextField);
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, 'Change'));
    expect(button().onPressed, isNull);

    await tester.enterText(fields.at(0), 'OldPass123');
    await tester.enterText(fields.at(1), 'NewPassword123!');
    await tester.enterText(fields.at(2), 'Different123!');
    await tester.pump();
    expect(find.text("The two new passwords don't match."), findsOneWidget);
    expect(button().onPressed, isNull);

    await tester.enterText(fields.at(1), 'abc');
    await tester.enterText(fields.at(2), 'abc');
    await tester.pump();
    expect(find.text('Use a short password anyway'), findsOneWidget);
    expect(button().onPressed, isNull);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.enterText(fields.at(1), 'OldPass123');
    await tester.enterText(fields.at(2), 'OldPass123');
    await tester.pump();
    expect(find.text("That's the password you have now."), findsOneWidget);
    expect(button().onPressed, isNull);
  });
}
