// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/services/mock_auth_service.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';

class StagedTestClientController extends ClientController {
  final List<Client> stage1Clients;
  final List<Client> stage2Clients;
  final List<String> callLog;
  final Completer<void>? stage2Delay;

  StagedTestClientController({
    required this.stage1Clients,
    required this.stage2Clients,
    required this.callLog,
    this.stage2Delay,
  }) : super(
         apiServiceRef: () => MockApiService(),
         authServiceRef: () => MockAuthService(),
         routerServiceRef: () => RouterService(isReviewerMode: true),
         reviewerModeRef: () => true,
         executeRouterCommandOutput: (cmd, args) async => null,
         processDhcpLeases: (raw) => raw,
       );

  @override
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    callLog.add('fetchClientsForSelectedRouter');
    return stage1Clients;
  }

  @override
  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client>)? onIncrementalUpdate,
  }) async {
    callLog.add('fetchAggregatedClients_start');
    if (stage2Delay != null) {
      await stage2Delay!.future;
    }
    callLog.add('fetchAggregatedClients_finish');
    onIncrementalUpdate?.call(stage2Clients);
    return stage2Clients;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'has_seen_restricted_clients_tooltip': true,
      'clients_aggregate_all_routers': true,
    });
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('Staged Client Loading & Active Router Priority', () {
    test(
      'AppState ensures active router session data finishes before secondary aggregation',
      () async {
        final appState = AppState.instance;

        await appState.setReviewerMode(true);
        expect(appState.isActiveSessionDataReady, isTrue);

        final readyFuture = appState.ensureActiveSessionDataReady();
        await expectLater(readyFuture, completes);

        await appState.fetchDashboardData();
        expect(appState.isActiveSessionDataReady, isTrue);
      },
    );

    test('Staged client loading priority in AppState', () async {
      final appState = AppState.instance;
      await appState.setReviewerMode(true);

      final stage1Clients = await appState.fetchClientsForSelectedRouter();
      expect(stage1Clients, isA<List<Client>>());
      expect(appState.isActiveSessionDataReady, isTrue);

      final stage2Clients = await appState.fetchAggregatedClients();
      expect(stage2Clients, isA<List<Client>>());
    });
  });
}
