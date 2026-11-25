// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/system_backup_upgrade/screens/system_backup_upgrade_screen.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _RecordingApiService extends MockApiService {
  final List<Map<String, dynamic>> recordedCalls = [];
  final bool shouldSimulateRebootDrop;

  _RecordingApiService({this.shouldSimulateRebootDrop = false});

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
    recordedCalls.add({'object': object, 'method': method, 'params': params});

    if (shouldSimulateRebootDrop &&
        object == 'file' &&
        method == 'exec' &&
        params?['command'] == '/sbin/firstboot') {
      throw Exception(
        'SocketException: Connection reset by peer during firstboot',
      );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group(
    'Factory Reset LuCI Parity - AppState Command Normalization & Execution',
    () {
      late AppState appState;
      late _RecordingApiService recordingApi;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        appState = AppState.instance;
        recordingApi = _RecordingApiService();
        appState.setApiServiceForTesting(recordingApi);
        appState.setAuthServiceForTesting(MockAuthService());
        appState.setSelectedRouterForTesting(
          model.Router(
            id: 'test-router',
            ipAddress: '192.168.1.1',
            name: 'Test Router',
            username: 'root',
            password: 'password',
            useHttps: false,
          ),
        );
      });

      test(
        'firstboot is normalized to /sbin/firstboot with [-r, -y] args matching rpcd ACL',
        () async {
          final success = await appState.executeRouterCommand('firstboot', [
            '-y',
          ]);
          expect(success, isTrue);

          final call = recordingApi.recordedCalls.firstWhere(
            (c) => c['object'] == 'file' && c['method'] == 'exec',
          );
          expect(call['params']['command'], equals('/sbin/firstboot'));
          expect(call['params']['params'], equals(['-r', '-y']));
        },
      );

      test(
        '/sbin/firstboot is normalized to /sbin/firstboot with [-r, -y] args',
        () async {
          final success = await appState.executeRouterCommand(
            '/sbin/firstboot',
            [],
          );
          expect(success, isTrue);

          final call = recordingApi.recordedCalls.firstWhere(
            (c) => c['object'] == 'file' && c['method'] == 'exec',
          );
          expect(call['params']['command'], equals('/sbin/firstboot'));
          expect(call['params']['params'], equals(['-r', '-y']));
        },
      );

      test(
        'reboot is normalized to /sbin/reboot with [] args matching rpcd ACL',
        () async {
          final success = await appState.executeRouterCommand('reboot', [
            'now',
          ]);
          expect(success, isTrue);

          final call = recordingApi.recordedCalls.firstWhere(
            (c) => c['object'] == 'file' && c['method'] == 'exec',
          );
          expect(call['params']['command'], equals('/sbin/reboot'));
          expect(call['params']['params'], equals(<String>[]));
        },
      );

      test(
        'firstboot succeeds even if router terminates socket connection during reboot',
        () async {
          recordingApi = _RecordingApiService(shouldSimulateRebootDrop: true);
          appState.setApiServiceForTesting(recordingApi);

          final success = await appState.executeRouterCommand('firstboot', [
            '-r',
            '-y',
          ]);
          expect(success, isTrue);
        },
      );
    },
  );

  group('Factory Reset LuCI Parity - UI & Confirmation Flow', () {
    late AppState appState;
    late _RecordingApiService recordingApi;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      appState = AppState.instance;
      recordingApi = _RecordingApiService();
      appState.setApiServiceForTesting(recordingApi);
      appState.setAuthServiceForTesting(MockAuthService());
      appState.setSelectedRouterForTesting(
        model.Router(
          id: 'test-router',
          ipAddress: '192.168.1.1',
          name: 'Test Router',
          username: 'root',
          password: 'password',
          useHttps: false,
        ),
      );
    });

    testWidgets(
      'Displays Reset to Defaults card, confirmation dialog and initiates firstboot -r -y',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStateProvider.overrideWith((ref) => appState)],
            child: MaterialApp(
              theme: KeystoneTheme.buildLightTheme(),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: SystemBackupUpgradeScreen()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final performResetFinder = find.text('Reset to factory settings');
        await tester.scrollUntilVisible(
          performResetFinder,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        expect(performResetFinder, findsOneWidget);

        await tester.tap(performResetFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Reset to factory settings?'), findsOneWidget);

        final confirmBtnFinder = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Reset'),
        );
        expect(confirmBtnFinder, findsOneWidget);

        await tester.tap(confirmBtnFinder);
        await tester.pump();

        final firstbootCall = recordingApi.recordedCalls.any(
          (c) =>
              c['object'] == 'file' &&
              c['method'] == 'exec' &&
              c['params']['command'] == '/sbin/firstboot' &&
              c['params']['params'].contains('-r') &&
              c['params']['params'].contains('-y'),
        );
        expect(firstbootCall, isTrue);

        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Resetting the router…'), findsOneWidget);

        final dismissBtnFinder = find.widgetWithText(
          FilledButton,
          'Close and wait at home',
        );
        expect(dismissBtnFinder, findsOneWidget);
        await tester.tap(dismissBtnFinder);
        await tester.pumpAndSettle();
      },
    );
  });
}
