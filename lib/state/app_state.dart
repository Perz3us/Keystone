// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/throughput_service.dart';
import 'package:yet_another_luci_app/state/controllers/throughput_controller.dart';
import 'package:yet_another_luci_app/state/controllers/dashboard_controller.dart';
import 'package:yet_another_luci_app/state/controllers/package_controller.dart';
import 'package:yet_another_luci_app/state/controllers/network_actions_controller.dart';
import 'package:yet_another_luci_app/state/controllers/client_controller.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/models/rpc_result.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/client_speed_limit.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_profile.dart';
import 'package:yet_another_luci_app/modules/parental_controls/models/parental_controls_store.dart';
import 'package:yet_another_luci_app/modules/parental_controls/controllers/parental_controls_controller.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/dashboard_preferences.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/ssh_service_interface.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/operation_queue.dart';
import 'package:yet_another_luci_app/services/service_factory.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/utils/logger.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/modules/package_manager/models/package_info.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/models/network_topology.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/modules/services_system/models/ddns_info.dart';
import 'package:yet_another_luci_app/modules/sqm/models/sqm_queue.dart';
import 'package:yet_another_luci_app/modules/wireless_management/models/wireless_info.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/modules/diagnostics/models/flush_dns_result.dart';
import 'package:yet_another_luci_app/utils/self_device_guard.dart';
import 'package:yet_another_luci_app/modules/firewall_security/services/firewall_policy_translator.dart';
import 'package:yet_another_luci_app/services/client_policy_schedule_service.dart';
import 'package:yet_another_luci_app/services/mock_api_service.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/services/device_discovery.dart';

enum RouterConnectionStatus { connected, reconnecting, disconnected }

class _RouterCommand {
  final String command;
  final List<String> args;

  const _RouterCommand(this.command, this.args);
}

class AppState extends ChangeNotifier {
  static AppState? _instance;

  late final SecureStorageService _secureStorageService;
  IApiService? _apiService;
  IAuthService? _authService;
  ISshService? _sshService;
  RouterService? _routerService;

  ISshService? get sshService => _sshService;

  @visibleForTesting
  void setSshServiceForTesting(ISshService service) => _sshService = service;

  @visibleForTesting
  void setApiServiceForTesting(IApiService service) => _apiService = service;

  @visibleForTesting
  void setAuthServiceForTesting(IAuthService service) => _authService = service;

  @visibleForTesting
  void setDashboardDataForTesting(Map<String, dynamic>? data) {
    _dashboardController?.setDashboardDataForTesting(data);
    notifyListeners();
  }

  @visibleForTesting
  void setIsDashboardLoadingForTesting(bool loading) {
    _dashboardController?.setIsDashboardLoadingForTesting(loading);
    notifyListeners();
  }

  @visibleForTesting
  void setCapabilitiesForTesting(RouterCapabilities? capabilities) {
    _dashboardController?.setCapabilitiesForTesting(capabilities);
    notifyListeners();
  }

  @visibleForTesting
  void setDashboardPreferencesForTesting(DashboardPreferences prefs) {
    _sessionController?.setDashboardPreferencesForTesting(prefs);
    notifyListeners();
  }

  @visibleForTesting
  void setConnectionStatusForTesting(RouterConnectionStatus status) {
    _connectionStatus = status;
    notifyListeners();
  }

  @visibleForTesting
  void notifyRouterBackOnlineForTesting({required bool success}) {
    _notifyRouterBackOnline(success: success);
  }

  int? _freeDiskSpaceOverrideForTesting;
  bool _hasFreeDiskSpaceOverride = false;

  @visibleForTesting
  void setFreeDiskSpaceForTesting(int? bytes) {
    _hasFreeDiskSpaceOverride = true;
    _freeDiskSpaceOverrideForTesting = bytes;
  }

  @visibleForTesting
  void clearFreeDiskSpaceForTesting() {
    _hasFreeDiskSpaceOverride = false;
    _freeDiskSpaceOverrideForTesting = null;
  }

  ThroughputService? _throughputService;
  ThroughputController? _throughputController;
  SessionController? _sessionController;
  PackageController? _packageController;
  NetworkActionsController? _networkActionsController;
  AccessControlTimerLifecycleManager? _accessControlTimerLifecycleManager;
  ClientController? _clientController;
  DashboardController? _dashboardController;
  final HttpClientManager _httpClientManager = HttpClientManager();

  RouterCapabilities? get capabilities => _dashboardController?.capabilities;
  bool get isMissingRpcPackages {
    final caps = capabilities;
    return caps != null &&
        !caps.probeFailed &&
        caps.ubusObjects.isNotEmpty &&
        (!caps.isRpcComplete) &&
        !reviewerModeEnabled;
  }

  bool get reviewerModeEnabled =>
      _sessionController?.reviewerModeEnabled ?? false;

  bool _isLoading = false;
  String? _errorMessage;

  RouterConnectionStatus _connectionStatus = RouterConnectionStatus.connected;
  RouterConnectionStatus get connectionStatus => _connectionStatus;

  Timer? _throughputTimer;
  final int _throughputIntervalSeconds = 2;
  int get throughputIntervalSeconds =>
      _throughputController?.throughputIntervalSeconds ??
      _throughputIntervalSeconds;
  Timer? _pollingTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts = 40;

  bool _isRebooting = false;
  bool get isRebooting => _isRebooting;

  bool get isAccessControlPendingConfirmation =>
      _networkActionsController?.isAccessControlPendingConfirmation ?? false;
  int get accessControlCountdownSeconds =>
      _networkActionsController?.accessControlCountdownSeconds ?? 25;

  ThemeMode get themeMode => _sessionController?.themeMode ?? ThemeMode.system;
  AppThemePalette get themePalette =>
      _sessionController?.themePalette ?? AppThemePalette.amber;
  bool get useDynamicTheme => _sessionController?.useDynamicTheme ?? false;

  ColorScheme? get preloadedLightDynamic =>
      _sessionController?.preloadedLightDynamic;
  ColorScheme? get preloadedDarkDynamic =>
      _sessionController?.preloadedDarkDynamic;

  Locale? get locale => _sessionController?.locale;

  bool get clientsAggregateAllRouters =>
      _sessionController?.clientsAggregateAllRouters ?? true;

  DashboardPreferences get dashboardPreferences =>
      _sessionController?.dashboardPreferences ?? DashboardPreferences();

  model.Router? _selectedRouterForTesting;

  @visibleForTesting
  void setSelectedRouterForTesting(model.Router? router) {
    _selectedRouterForTesting = router;
    notifyListeners();
  }

  List<model.Router> get routers => _sessionController?.routers ?? [];
  model.Router? get selectedRouter =>
      _selectedRouterForTesting ?? _sessionController?.selectedRouter;
  String? get currentRouterIp => _sessionController?.currentRouterIp;
  RouterService? get routerService => _routerService;

  VoidCallback? onRouterBackOnline;
  final List<void Function(bool success)> _routerBackOnlineListeners = [];

  void addRouterBackOnlineListener(void Function(bool success) listener) {
    if (!_routerBackOnlineListeners.contains(listener)) {
      _routerBackOnlineListeners.add(listener);
    }
  }

  void removeRouterBackOnlineListener(void Function(bool success) listener) {
    _routerBackOnlineListeners.remove(listener);
  }

  void _notifyRouterBackOnline({required bool success}) {
    onRouterBackOnline?.call();
    for (final listener in List<void Function(bool success)>.from(
      _routerBackOnlineListeners,
    )) {
      try {
        listener(success);
      } catch (_) {}
    }
  }

  int? requestedTab;
  ClientCategoryFilter? requestedClientCategoryFilter;

  final Set<String> _customGuestSections = {};
  final Set<String> _excludedGuestSections = {};

  Set<String> get customGuestSections => Set.unmodifiable(_customGuestSections);
  Set<String> get excludedGuestSections =>
      Set.unmodifiable(_excludedGuestSections);

  bool isCustomGuestSection(String sectionName) =>
      _customGuestSections.contains(sectionName);
  bool isExcludedGuestSection(String sectionName) =>
      _excludedGuestSections.contains(sectionName);

  void markAsGuestSection(String sectionName) {
    _excludedGuestSections.remove(sectionName);
    _customGuestSections.add(sectionName);
    notifyListeners();
  }

  void markAsStandardSection(String sectionName) {
    _customGuestSections.remove(sectionName);
    _excludedGuestSections.add(sectionName);
    notifyListeners();
  }

  void resetGuestSectionOverride(String sectionName) {
    _customGuestSections.remove(sectionName);
    _excludedGuestSections.remove(sectionName);
    notifyListeners();
  }

  void requestTab(int index, {ClientCategoryFilter? clientCategoryFilter}) {
    requestedTab = index;
    requestedClientCategoryFilter = clientCategoryFilter;
    notifyListeners();
  }

  final Completer<void> _initCompleter = Completer<void>();
  bool get isInitialized => _initCompleter.isCompleted;
  Future<void> get initializationFuture =>
      _initCompleter.isCompleted ? Future<void>.value() : _initCompleter.future;

  AppState._() {
    _initialize();
    DeviceKindStore.instance.addListener(notifyListeners);
    DeviceDiscovery.instance.addListener(notifyListeners);
  }

  static AppState get instance {
    return _instance ??= AppState._();
  }

  static Future<void> preHydrate({SharedPreferences? prefs}) async {
    final app = AppState.instance;
    await app._sessionController?.preHydratePreferences(prefs: prefs);
  }

  Future<void> _initialize() async {
    try {
      ServiceContainer.configure(reviewerMode: false);
      _secureStorageService = ServiceContainer.instance.factory
          .createSecureStorageService();
      _initializeServices();

      final storedReviewerMode = await _secureStorageService.readValue(
        AppConfig.reviewerModeKey,
      );
      if (storedReviewerMode == 'true') {
        await _sessionController?.setReviewerMode(true);
      }

      await Future.wait([
        _sessionController?.loadThemeMode(notify: false) ?? Future.value(),
        _sessionController?.loadDynamicTheme(notify: false) ?? Future.value(),
        _sessionController?.loadLocale(notify: false) ?? Future.value(),
        loadRouters(notify: false),
        _sessionController?.loadClientsViewMode() ?? Future.value(),
      ]);

      await _sessionController?.migrateGlobalDashboardPreferencesIfNeeded();
      await loadDashboardPreferences();
      await _loadPendingAccessControlState();

      notifyListeners();
    } catch (e, stack) {
      Logger.exception('AppState initialization failed', e, stack);
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  void _initializeServices() {
    final reviewerMode = _sessionController?.reviewerModeEnabled ?? false;
    ServiceContainer.configure(reviewerMode: reviewerMode);

    final factory = ServiceContainer.instance.factory;
    _authService = factory.createAuthService();
    _apiService = factory.createApiService();
    _sshService = factory.createSshService();
    _routerService = factory.createRouterService();
    _throughputService = factory.createThroughputService();
    _throughputController = ThroughputController(
      throughputService: _throughputService!,
    );
    _dashboardController = DashboardController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      sshServiceRef: () => _sshService,
      routerServiceRef: () => _routerService,
      secureStorageServiceRef: () => _secureStorageService,
      throughputControllerRef: () => _throughputController,
      dashboardPreferencesRef: () => dashboardPreferences,
      reviewerModeRef: () => reviewerModeEnabled,
      tryAutoLogin: tryAutoLogin,
      fetchPublicIps: fetchPublicIps,
      setPublicIps: (v4, v6) {
        _sessionController?.setPublicIps(v4, v6);
      },
      connectionStatusRef: () {
        switch (_connectionStatus) {
          case RouterConnectionStatus.connected:
            return DashboardConnectionStatus.connected;
          case RouterConnectionStatus.reconnecting:
            return DashboardConnectionStatus.reconnecting;
          case RouterConnectionStatus.disconnected:
            return DashboardConnectionStatus.disconnected;
        }
      },
      setConnectionStatus: (status) {
        final prev = _connectionStatus;
        switch (status) {
          case DashboardConnectionStatus.connected:
            _connectionStatus = RouterConnectionStatus.connected;
            break;
          case DashboardConnectionStatus.reconnecting:
            _connectionStatus = RouterConnectionStatus.reconnecting;
            break;
          case DashboardConnectionStatus.disconnected:
            _connectionStatus = RouterConnectionStatus.disconnected;
            break;
        }
        if (prev != _connectionStatus) {
          notifyListeners();
        }
      },
      startThroughputTimer: _startThroughputTimer,
      processDhcpLeases: _processDhcpLeases,
      notifyListeners: notifyListeners,
    );
    _sessionController ??= SessionController(
      initialReviewerMode: reviewerMode,
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      secureStorageServiceRef: () => _secureStorageService,
      httpClientManagerRef: () => _httpClientManager,
      dashboardControllerRef: () => _dashboardController,
      cancelThroughputTimer: _cancelThroughputTimer,
      startThroughputTimer: _startThroughputTimer,
      fetchDashboardData: fetchDashboardData,
      initializeServices: _initializeServices,
      setLoadingState: (loading) => _isLoading = loading,
      setErrorState: setError,
      notifyListeners: notifyListeners,
      onSessionReset: () {
        _markSessionDataLoading();
        _customGuestSections.clear();
        _excludedGuestSections.clear();
        ParentalControlsController.instance.reset();
        _clientController?.resetState();
        _networkActionsController?.resetState();
        _throughputController?.cancelAndClear();
        invalidateStaticLeasesCache();
      },
    );
    _packageController = PackageController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      capabilitiesRef: () => capabilities,
      reviewerModeRef: () => reviewerModeEnabled,
      refreshDashboard: fetchDashboardData,
      redetectCapabilities: redetectCapabilities,
    );
    _networkActionsController = NetworkActionsController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      reviewerModeRef: () => reviewerModeEnabled,
      dashboardDataRef: () => dashboardData,
      refreshDashboard: fetchDashboardData,
      redetectCapabilities: redetectCapabilities,
      notifyListeners: notifyListeners,
    );
    _accessControlTimerLifecycleManager = AccessControlTimerLifecycleManager(
      controller: _networkActionsController!,
    );
    _clientController = ClientController(
      apiServiceRef: () => _apiService,
      authServiceRef: () => _authService,
      routerServiceRef: () => _routerService,
      reviewerModeRef: () => reviewerModeEnabled,
      dashboardDataRef: () => dashboardData,
      executeRouterCommandOutput: executeRouterCommandOutput,
      processDhcpLeases: _processDhcpLeases,
      onClientsUpdated: notifyListeners,
    );
  }

  bool _hasShownReviewerNotice = false;
  bool get hasShownReviewerNotice => _hasShownReviewerNotice;

  void markReviewerNoticeShown() {
    _hasShownReviewerNotice = true;
  }

  void resetReviewerNoticeFlag() {
    _hasShownReviewerNotice = false;
  }

  Future<void> setReviewerMode(bool enabled, {BuildContext? context}) async {
    if (enabled) {
      _hasShownReviewerNotice = false;
    }
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController?.setReviewerMode(enabled, context: context);
    if (enabled) {
      _markSessionDataReady();
    } else {
      _markSessionDataLoading();
    }
  }

  Future<String?> secureRead(String key) async {
    return _secureStorageService.readValue(key);
  }

  Future<void> secureWrite(String key, String value) async {
    await _secureStorageService.writeValue(key, value);
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _sessionController!.setThemeMode(mode);

  Future<void> setThemePalette(AppThemePalette palette) =>
      _sessionController!.setThemePalette(palette);

  Future<void> setDynamicTheme(bool enable) =>
      _sessionController!.setDynamicTheme(enable);

  Future<void> setLocale(Locale? locale) =>
      _sessionController!.setLocale(locale);

  Future<void> setClientsAggregateAllRouters(bool aggregate) =>
      _sessionController!.setClientsAggregateAllRouters(aggregate);

  Future<void> loadDashboardPreferences() =>
      _sessionController!.loadDashboardPreferences();

  Future<void> saveDashboardPreferences(DashboardPreferences prefs) =>
      _sessionController!.saveDashboardPreferences(prefs);

  String? get sysauth => _sessionController?.sysauth;
  bool get isAuthenticated => sysauth != null && sysauth!.isNotEmpty;
  bool get hasActiveSession => isAuthenticated || reviewerModeEnabled;
  IApiService? get apiService => _apiService;
  RouterScopedOperationQueue get operationQueue =>
      RouterScopedOperationQueue.instance;

  Future<bool> uciApply({
    String? ipAddress,
    String? sysauth,
    bool? useHttps,
    bool rollback = true,
    int timeout = 30,
  }) async {
    final router = selectedRouter;
    final targetIp = ipAddress ?? router?.ipAddress;
    final targetSysauth = sysauth ?? this.sysauth ?? '';
    final targetHttps = useHttps ?? router?.useHttps ?? false;

    if (targetIp == null || targetIp.isEmpty) {
      Logger.error('uciApply failed: no target IP address');
      return false;
    }

    final routerId = router?.id ?? targetIp;

    return operationQueue.runLocked(
      routerId: routerId,
      domain: 'uci',
      timeout: Duration(seconds: timeout + 15),
      action: () async {
        if (_apiService == null) return false;
        return await _apiService!.uciApply(
          targetIp,
          targetSysauth,
          targetHttps,
          rollback: rollback,
          timeout: timeout,
        );
      },
    );
  }

  Future<bool> uciConfirm({
    String? ipAddress,
    String? sysauth,
    bool? useHttps,
  }) async {
    final router = selectedRouter;
    final targetIp = ipAddress ?? router?.ipAddress;
    final targetSysauth = sysauth ?? this.sysauth ?? '';
    final targetHttps = useHttps ?? router?.useHttps ?? false;

    if (targetIp == null || targetIp.isEmpty) {
      Logger.error('uciConfirm failed: no target IP address');
      return false;
    }

    final routerId = router?.id ?? targetIp;

    return operationQueue.runLocked(
      routerId: routerId,
      domain: 'uci',
      action: () async {
        if (_apiService == null) return false;
        return await _apiService!.uciConfirm(
          targetIp,
          targetSysauth,
          targetHttps,
        );
      },
    );
  }

  Future<ChangePasswordResult> changeRouterPassword({
    required String currentPassword,
    required String newPassword,
    void Function(ChangePasswordStatus status)? onProgress,
  }) async {
    if (_sessionController == null) {
      return const ChangePasswordResult.failed(
        'Session controller unavailable',
      );
    }
    return await _sessionController!.changeRouterPassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
      onProgress: onProgress,
    );
  }

  Future<bool> retrySaveRouterPassword(model.Router router) async {
    if (_sessionController == null) return false;
    return await _sessionController!.retrySaveRouterPassword(router);
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void setError(String? error) {
    if (error == null || error.trim().isEmpty) {
      _errorMessage = null;
    } else {
      _errorMessage = error;
    }
    notifyListeners();
  }

  Map<String, dynamic>? get dashboardData =>
      _dashboardController?.dashboardData;
  List<double> get rxHistory => _throughputController?.rxHistory ?? [];
  List<double> get txHistory => _throughputController?.txHistory ?? [];
  double get currentRxRate => _throughputController?.currentRxRate ?? 0.0;
  double get currentTxRate => _throughputController?.currentTxRate ?? 0.0;
  bool get isDashboardLoading =>
      _dashboardController?.isDashboardLoading ?? false;
  String? get dashboardError => _dashboardController?.dashboardError;

  String? get publicIpv4 => _sessionController?.publicIpv4;
  String? get publicIpv6 => _sessionController?.publicIpv6;
  bool get isFetchingPublicIps =>
      _sessionController?.isFetchingPublicIps ?? false;

  Future<void> fetchPublicIps({BuildContext? context}) =>
      _sessionController!.fetchPublicIps(context: context);

  List<double> getRxHistoryForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getRxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getTxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  double getCurrentRxRateForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getCurrentRxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    final deviceName = getDeviceNameForInterface(interface);
    return _throughputController?.getCurrentTxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  Future<void> loadRouters({bool notify = true}) =>
      _sessionController!.loadRouters(notify: notify);

  Future<void> addRouter(model.Router router) =>
      _sessionController!.addRouter(router);

  Future<void> removeRouter(String id) => _sessionController!.removeRouter(id);

  Future<void> selectRouter(
    String id, {
    BuildContext? context,
    bool force = false,
  }) async {
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController!.selectRouter(id, context: context, force: force);
    await loadSpeedLimitsForRouter(id);
  }

  Future<void> updateRouter(model.Router router, {String? oldId}) =>
      _sessionController!.updateRouter(router, oldId: oldId);

  Future<void> updateRouterName(String id, String? name) =>
      _sessionController!.updateRouterName(id, name);

  Future<FileSaveResult?> exportRouterProfiles() =>
      _sessionController!.exportRouterProfiles();

  Future<RouterImportResult> importRouterProfilesFromFile() =>
      _sessionController!.importRouterProfilesFromFile();

  Future<RouterImportResult> importRoutersFromJson(String jsonContent) =>
      _sessionController!.importRoutersFromJson(jsonContent);

  LoginFailure get lastLoginFailure =>
      _sessionController?.lastLoginFailure ?? LoginFailure.none;

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? routerName,
    BuildContext? context,
  }) => _sessionController!.login(
    ip,
    user,
    pass,
    useHttps,
    fromRouter: fromRouter,
    routerName: routerName,
    context: context,
  );

  Future<void> logout() async {
    _customGuestSections.clear();
    _excludedGuestSections.clear();
    ParentalControlsController.instance.reset();
    _clientController?.resetState();
    _networkActionsController?.resetState();
    _throughputController?.cancelAndClear();
    invalidateStaticLeasesCache();
    await _sessionController!.logout();
    _markSessionDataReady();
  }

  Future<void> redetectCapabilities() async {
    await _dashboardController?.redetectCapabilities();
  }

  void updatePackageEngine(PackageManagerEngine engine) {
    _dashboardController?.updatePackageEngine(engine);
  }

  Future<RouterCapabilities> probeRouterCapabilities({
    bool forceRefresh = false,
  }) async {
    return await _dashboardController?.probeRouterCapabilities(
          forceRefresh: forceRefresh,
        ) ??
        RouterCapabilities.conservative('unknown');
  }

  Completer<void>? _activeSessionDataCompleter;
  bool _isActiveSessionDataReady = false;

  bool get isActiveSessionDataReady => _isActiveSessionDataReady;

  Future<void> ensureActiveSessionDataReady() {
    if (_isActiveSessionDataReady) {
      return Future.value();
    }
    if (_activeSessionDataCompleter != null) {
      return _activeSessionDataCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          _markSessionDataReady();
        },
      );
    }
    return fetchDashboardData();
  }

  void _markSessionDataLoading() {
    _isActiveSessionDataReady = false;
    if (_activeSessionDataCompleter == null ||
        _activeSessionDataCompleter!.isCompleted) {
      _activeSessionDataCompleter = Completer<void>();
    }
  }

  void _markSessionDataReady() {
    _isActiveSessionDataReady = true;
    if (_activeSessionDataCompleter != null &&
        !_activeSessionDataCompleter!.isCompleted) {
      _activeSessionDataCompleter!.complete();
    }
    _activeSessionDataCompleter = null;
  }

  Future<void> fetchDashboardData({bool force = false}) async {
    final completer = _activeSessionDataCompleter ?? Completer<void>();
    _activeSessionDataCompleter = completer;
    if (force) unawaited(refreshInstalledFeatures());
    try {
      final firstLoad = dashboardData == null;
      final clients = fetchClientsForSelectedRouter();
      await _dashboardController?.fetchDashboardData(force: force);
      await clients;
      if (firstLoad && dashboardData != null) {
        await fetchClientsForSelectedRouter();
      }
    } finally {
      _markSessionDataReady();
    }
  }

  Future<RpcResult<List<OpenWrtPackage>>> fetchInstalledPackages() =>
      _packageController!.fetchInstalledPackages();

  Future<RpcResult<dynamic>> fetchPackagesDataResult() =>
      _packageController!.fetchPackagesDataResult();

  Future<RpcResult<List<OpenWrtPackage>>> fetchAvailablePackages() =>
      _packageController!.fetchAvailablePackages();

  Future<RpcResult<PackageManagerOverview>> fetchPackageManagerOverview() =>
      _packageController!.fetchPackageManagerOverview();

  Future<RpcResult<dynamic>> fetchAvailablePackagesDataResult() =>
      _packageController!.fetchAvailablePackagesDataResult();

  Future<RpcResult<NetworkTopology>> fetchNetworkTopologyResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    final model = capabilities?.networkModel ?? NetworkModel.unknown;
    if (model == NetworkModel.unknown) {
      return RpcResult.methodNotFound(
        'Network model is unknown or in conservative fallback mode',
      );
    }

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'network'},
      );

      final rpcRes = RpcResult.fromUbusResponse<NetworkTopology>(rawRpc, (
        data,
      ) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          if (model == NetworkModel.dsa) {
            return DsaTopologyParser.parse(map, null);
          } else {
            return SwconfigTopologyParser.parse(
              map,
              null,
              boardJson:
                  dashboardData?['boardJson'] as Map<String, dynamic>? ??
                  capabilities?.boardJson,
            );
          }
        }
        return NetworkTopology.unavailable(
          model,
          'Invalid network config payload format',
        );
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Network topology fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching switch topology: $e',
      );
    }
  }

  Future<RpcResult<FirewallOverview>> fetchFirewallOverviewResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final backend = capabilities?.firewallBackend ?? FirewallBackend.fw4;
    final routerId = _routerService?.selectedRouter?.id;

    unawaited(
      _apiService!
          .discoverManagementPorts(ip, _authService!.sysauth!, useHttps)
          .then((ports) {
            if (routerId != null) {
              SelfDeviceGuard.setDiscoveredManagementPorts(routerId, ports);
            }
          })
          .catchError((_) {}),
    );

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
      );

      final rpcRes = RpcResult.fromUbusResponse<FirewallOverview>(rawRpc, (
        data,
      ) {
        if (data is Map) {
          final map = Map<String, dynamic>.from(data);
          return FirewallOverview.fromUciData(
            map,
            backend: backend,
            isReviewerMode: reviewerModeEnabled,
          );
        }
        return FirewallOverview.unavailable(
          backend,
          'Invalid firewall config payload format',
        );
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Firewall config fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching firewall overview: $e',
      );
    }
  }

  Future<RpcResult<WirelessOverview>> fetchWirelessOverviewResult() async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) {
      return RpcResult.networkError('No active router session');
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    try {
      final rawRpc = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        params: {},
      );

      final rpcRes = RpcResult.fromUbusResponse<WirelessOverview>(rawRpc, (
        data,
      ) {
        return WirelessOverview.fromDashboardData({
          'wireless': data,
        }, isReviewerMode: reviewerModeEnabled);
      });

      if (rpcRes.status == RpcCallStatus.methodNotFound) {
        Logger.warning(
          'Wireless devices fetch returned methodNotFound. Triggering background capability re-probe.',
        );
        unawaited(redetectCapabilities());
      }

      return rpcRes;
    } catch (e) {
      return RpcResult.networkError(
        'Network error fetching wireless overview: $e',
      );
    }
  }

  Future<RpcResult<String>> managePackageResult({
    required String packageName,
    required String action,
  }) => _packageController!.managePackageResult(
    packageName: packageName,
    action: action,
  );

  Future<bool> managePackage({
    required String packageName,
    required String action,
  }) => _packageController!.managePackage(
    packageName: packageName,
    action: action,
  );

  Future<int?> getFreeDiskSpace() {
    if (_hasFreeDiskSpaceOverride) {
      return Future.value(_freeDiskSpaceOverrideForTesting);
    }
    return _packageController?.getFreeDiskSpace() ?? Future.value(null);
  }

  Future<RpcResult<String>> updatePackageLists() =>
      _packageController!.updatePackageLists();

  Future<RpcResult<String>> installPackage(String packageName) =>
      _packageController!.installPackage(packageName);

  Future<RpcResult<String>> removePackage(String packageName) =>
      _packageController!.removePackage(packageName);

  Future<RpcResult<String>> upgradePackage(String packageName) =>
      _packageController!.upgradePackage(packageName);

  Future<RpcResult<String>> installCustomPackage(String target) =>
      _packageController!.installCustomPackage(target);

  Future<RpcResult<List<OpenWrtPackage>>> fetchUpgradablePackagesResult() =>
      _packageController!.fetchUpgradablePackagesResult();

  Future<List<OpenWrtPackage>> fetchUpgradablePackages() =>
      _packageController!.fetchUpgradablePackages();

  Future<dynamic> callRpc(
    String object,
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        selectedRouter == null ||
        _authService?.sysauth == null) {
      return null;
    }
    return await _apiService!.call(
      selectedRouter!.ipAddress,
      _authService!.sysauth!,
      selectedRouter!.useHttps,
      object: object,
      method: method,
      params: params,
    );
  }

  Future<bool> executeRouterCommand(String command, List<String> args) async {
    final router = selectedRouter ?? _routerService?.selectedRouter;
    final ip = router?.ipAddress;
    final auth = _authService?.sysauth ?? sysauth;
    if (ip == null || auth == null) return false;
    final useHttps = router?.useHttps ?? false;

    final normalized = _normalizeRouterCommand(command, args);
    final execCommand = normalized.command;
    final execArgs = normalized.args;

    if (execCommand.startsWith('/etc/init.d/') && execArgs.isNotEmpty) {
      final serviceName = execCommand.replaceFirst('/etc/init.d/', '').trim();
      final action = execArgs[0].trim();
      if (serviceName.isNotEmpty && action.isNotEmpty) {
        final ok = await manageServiceAction(serviceName, action);
        if (ok) return true;
      }
    }

    final isShellCmd =
        execCommand == 'sh' ||
        execCommand == '/bin/sh' ||
        execCommand == 'ash' ||
        execCommand == '/bin/ash';
    final cmdStr = isShellCmd && execArgs.length >= 2 && execArgs[0] == '-c'
        ? execArgs[1]
        : ([execCommand, ...execArgs]).join(' ');

    try {
      final res = await _apiService!.call(
        ip,
        auth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': execCommand, 'params': execArgs, 'args': execArgs},
      );
      if (_isSuccessResponse(res)) return true;
    } catch (e) {
      if (execCommand == '/sbin/firstboot' || execCommand == '/sbin/reboot') {
        Logger.info(
          'Router command $execCommand initiated reboot; connection terminated: $e',
        );
        return true;
      }
    }

    try {
      final res = await _apiService!.call(
        ip,
        auth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      if (_isSuccessResponse(res)) return true;
    } catch (e) {
      if (execCommand == '/sbin/firstboot' || execCommand == '/sbin/reboot') {
        return true;
      }
    }

    try {
      final res = await _apiService!.call(
        ip,
        auth,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      if (_isSuccessResponse(res)) return true;
    } catch (e) {
      if (execCommand == '/sbin/firstboot' || execCommand == '/sbin/reboot') {
        return true;
      }
    }

    if (_sshService != null &&
        (execCommand == '/sbin/firstboot' || execCommand == '/sbin/reboot')) {
      final ip = selectedRouter?.ipAddress;
      final username = selectedRouter?.username ?? 'root';
      String? password = selectedRouter?.password;
      if (password == null || password.isEmpty) {
        try {
          final creds = await _secureStorageService.getCredentials();
          password = creds['password'];
        } catch (_) {}
      }
      if (ip != null && password != null && password.isNotEmpty) {
        try {
          final sshCmd = '$execCommand ${execArgs.join(' ')}'.trim();
          final sshRes = await _sshService!.executeCommand(
            host: ip,
            username: username,
            password: password,
            command: sshCmd,
          );
          if (sshRes.success) return true;
        } catch (_) {
          return true;
        }
      }
    }

    return false;
  }

  bool _isSuccessResponse(dynamic res) {
    return RpcResult.fromUbusResponse<dynamic>(res, (data) => data).isSuccess;
  }

  String? _extractStdout(dynamic res) {
    if (res == null) return null;
    if (res is String) return res;

    if (res is List) {
      if (res.isEmpty) return null;
      for (final item in res) {
        if (item is Map) {
          final out = item['stdout'] ?? item['data'] ?? item['out'];
          if (out != null) return out.toString();
        } else if (item is String && item.isNotEmpty && item != '0') {
          return item;
        }
      }
    } else if (res is Map) {
      final out = res['stdout'] ?? res['data'] ?? res['out'];
      if (out != null) return out.toString();
      final result = res['result'];
      if (result != null) return _extractStdout(result);
    }
    return null;
  }

  Future<String?> executeRouterCommandOutput(
    String command,
    List<String> args,
  ) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    if (ip == null || _authService?.sysauth == null) return null;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    final normalized = _normalizeRouterCommand(command, args);
    final execCommand = normalized.command;
    final execArgs = normalized.args;
    final isShellCmd =
        execCommand == 'sh' ||
        execCommand == '/bin/sh' ||
        execCommand == 'ash' ||
        execCommand == '/bin/ash';
    final cmdStr = isShellCmd && execArgs.length >= 2 && execArgs[0] == '-c'
        ? execArgs[1]
        : ([execCommand, ...execArgs]).join(' ');

    final readPath = _readPathForCommand(execCommand, execArgs);
    if (readPath != null) {
      try {
        final readRes = await _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': readPath},
        );
        final out = _extractStdout(readRes);
        if (out != null && out.trim().isNotEmpty) return out;
      } catch (_) {}
    }

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {'command': execCommand, 'params': execArgs, 'args': execArgs},
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': '/bin/sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    try {
      final res = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': 'sh',
          'params': ['-c', cmdStr],
          'args': ['-c', cmdStr],
        },
      );
      final out = _extractStdout(res);
      if (out != null && out.trim().isNotEmpty) return out;
    } catch (_) {}

    if (execCommand == 'cat' && execArgs.isNotEmpty) {
      try {
        final readRes = await _apiService!.call(
          ip,
          _authService!.sysauth!,
          useHttps,
          object: 'file',
          method: 'read',
          params: {'path': execArgs.last},
        );
        final out = _extractStdout(readRes);
        if (out != null && out.trim().isNotEmpty) return out;
      } catch (_) {}
    }

    return null;
  }

  _RouterCommand _normalizeRouterCommand(String command, List<String> args) {
    if (command == 'sh' || command == 'ash' || command == 'bash') {
      return _RouterCommand('/bin/sh', args);
    }
    if (command == 'cat') {
      return _RouterCommand('/bin/cat', args);
    }
    if (command == 'ip' || command == '/sbin/ip') {
      if (args.contains('-4') || args.contains('-6')) {
        return _RouterCommand('/sbin/ip', args);
      }
      if (args.isEmpty || args[0] == 'neigh') {
        final remaining = args.isNotEmpty ? args.sublist(1) : <String>[];
        return _RouterCommand('/sbin/ip', ['-4', 'neigh', ...remaining]);
      }
      return _RouterCommand('/sbin/ip', args);
    }
    if (command == 'bridge' || command == '/sbin/bridge') {
      return _RouterCommand('/sbin/bridge', args);
    }
    if (command == 'sysupgrade' || command == '/sbin/sysupgrade') {
      if (args.contains('-l') || args.contains('--list-backup')) {
        return const _RouterCommand('/sbin/sysupgrade', ['--list-backup']);
      }
      final normalizedArgs = args.map((a) {
        if (a == '-F') return '--force';
        if (a == '/tmp/sysupgrade_firmware.bin') return '/tmp/firmware.bin';
        return a;
      }).toList();
      return _RouterCommand('/sbin/sysupgrade', normalizedArgs);
    }
    if (command == 'wifi') {
      return _RouterCommand('/sbin/wifi', args);
    }
    if (command == 'reboot' || command == '/sbin/reboot') {
      return const _RouterCommand('/sbin/reboot', []);
    }
    if (command == 'firstboot' || command == '/sbin/firstboot') {
      return const _RouterCommand('/sbin/firstboot', ['-r', '-y']);
    }
    return _RouterCommand(command, args);
  }

  String? _readPathForCommand(String command, List<String> args) {
    if (args.isEmpty) return null;
    if (command == 'cat' || command == '/bin/cat') {
      return args.last;
    }
    return null;
  }

  Map<String, dynamic> _processDhcpLeases(Map<String, dynamic> rawDhcpData) {
    final rawStr =
        rawDhcpData['data']?.toString() ??
        rawDhcpData['stdout']?.toString() ??
        '';
    final leases = <Map<String, dynamic>>[];

    for (final line in rawStr.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final timestamp = int.tryParse(parts[0]) ?? 0;
        final macAddress = parts[1];
        final ipAddress = parts[2];
        final hostname = parts[3] == '*' ? 'Unknown' : parts[3];

        leases.add({
          'expires': timestamp,
          'macaddr': macAddress,
          'ipaddr': ipAddress,
          'hostname': hostname,
          'activetime': 0,
          'leasetime': timestamp,
        });
      }
    }

    return {'dhcp_leases': leases, 'leases': leases};
  }

  String? getDeviceNameForInterface(String interfaceName) =>
      _dashboardController?.getDeviceNameForInterface(interfaceName) ??
      interfaceName;

  void setThroughputInterval(int seconds) {
    final shouldRun = isThroughputPollingActive && hasActiveSession;
    _throughputController?.setInterval(
      seconds,
      isRebooting: _isRebooting || !shouldRun,
      onTick: _updateThroughputOnly,
      immediateTick: shouldRun,
    );
    if (!shouldRun) {
      _throughputController?.pauseTimer();
    }
    notifyListeners();
  }

  bool _isDashboardTabActive = true;
  int _realtimeTelemetryConsumers = 0;

  bool get isDashboardTabActive => _isDashboardTabActive;

  bool get isThroughputPollingActive =>
      _isDashboardTabActive || _realtimeTelemetryConsumers > 0;

  void acquireRealtimeTelemetry() {
    _realtimeTelemetryConsumers++;
    if (_realtimeTelemetryConsumers == 1) {
      if (_throughputController?.isPaused ?? false) {
        resumeThroughputTimer(immediateTick: true);
      } else {
        _startThroughputTimer(immediateTick: true);
      }
    }
  }

  void releaseRealtimeTelemetry() {
    if (_realtimeTelemetryConsumers > 0) {
      _realtimeTelemetryConsumers--;
      if (_realtimeTelemetryConsumers == 0) {
        if (!_isDashboardTabActive) {
          pauseThroughputTimer();
        } else {
          setThroughputInterval(2);
        }
      }
    }
  }

  void setDashboardTabActive(bool active) {
    if (_isDashboardTabActive == active) return;
    _isDashboardTabActive = active;
    if (active) {
      if (_realtimeTelemetryConsumers == 0) {
        setThroughputInterval(2);
      } else {
        resumeThroughputTimer(immediateTick: true);
      }
    } else if (_realtimeTelemetryConsumers == 0) {
      pauseThroughputTimer();
    }
  }

  void _startThroughputTimer({bool immediateTick = true}) {
    if (!isThroughputPollingActive || !hasActiveSession) return;
    if (_isDashboardTabActive && _realtimeTelemetryConsumers == 0) {
      _throughputController?.setInterval(
        2,
        isRebooting: _isRebooting,
        onTick: _updateThroughputOnly,
        immediateTick: false,
      );
    } else {
      _throughputController?.startTimer(
        isRebooting: _isRebooting,
        onTick: _updateThroughputOnly,
      );
    }
    if (immediateTick && !_isRebooting) {
      Future.microtask(_updateThroughputOnly);
    }
  }

  bool _isUserScrolling = false;
  bool _pendingNotificationWhileScrolling = false;

  bool get isUserScrolling => _isUserScrolling;

  void setScrollState(bool isScrolling) {
    if (_isUserScrolling == isScrolling) return;
    _isUserScrolling = isScrolling;
    if (!isScrolling && _pendingNotificationWhileScrolling) {
      _pendingNotificationWhileScrolling = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isUserScrolling) {
          notifyListeners();
        }
      });
    }
  }

  void notifyListenersDeferrable() {
    if (_isUserScrolling) {
      _pendingNotificationWhileScrolling = true;
    } else if (isThroughputPollingActive) {
      _pendingNotificationWhileScrolling = false;
      notifyListeners();
    }
  }

  bool _isHeavyTaskRunning = false;
  bool get isHeavyTaskRunning => _isHeavyTaskRunning;
  void setHeavyTaskRunning(bool running) {
    _isHeavyTaskRunning = running;
  }

  bool _isUpdatingThroughput = false;

  Future<void> _updateThroughputOnly() async {
    if (_isRebooting || _isHeavyTaskRunning || _isUpdatingThroughput) {
      return;
    }
    _isUpdatingThroughput = true;
    try {
      if (reviewerModeEnabled) {
        try {
          final results = await Future.wait([
            _apiService!.callSimple('network', 'device', {}),
            _apiService!.callSimple('system', 'info', {}),
          ]);
          final rawNet = results[0][1];
          final networkData = rawNet is Map
              ? Map<String, dynamic>.from(rawNet)
              : null;
          final rawSys = results[1][1];
          final sysInfoData = rawSys is Map
              ? Map<String, dynamic>.from(rawSys)
              : null;
          if (sysInfoData != null) {
            _dashboardController?.updateSysInfo(sysInfoData);
          }

          final wanDeviceNames = {'eth0'};

          final specificInterface =
              ThroughputController.resolveSpecificInterface(
                dashboardPreferences,
                deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
              );

          _throughputController?.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
          notifyListenersDeferrable();
        } catch (_) {}
        return;
      }

      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return;
      }

      final ip = _routerService!.selectedRouter!.ipAddress;
      final useHttps = _routerService!.selectedRouter!.useHttps;

      try {
        final results = await Future.wait([
          _apiService!.call(
            ip,
            _authService!.sysauth!,
            useHttps,
            object: 'luci-rpc',
            method: 'getNetworkDevices',
            params: {},
          ),
          _apiService!.call(
            ip,
            _authService!.sysauth!,
            useHttps,
            object: 'system',
            method: 'info',
            params: {},
          ),
        ]);

        final netResult = results[0];
        final sysResult = results[1];

        if (sysResult is List && sysResult.length > 1 && sysResult[0] == 0) {
          final rawSys = sysResult[1];
          final sysInfoData = rawSys is Map
              ? Map<String, dynamic>.from(rawSys)
              : null;
          if (sysInfoData != null) {
            _dashboardController?.updateSysInfo(sysInfoData);
          }
        }

        dynamic netDataResult = netResult;
        if (netDataResult is! List ||
            netDataResult.length <= 1 ||
            netDataResult[0] != 0) {
          try {
            netDataResult = await _apiService!.call(
              ip,
              _authService!.sysauth!,
              useHttps,
              object: 'network.device',
              method: 'status',
              params: {},
            );
          } catch (_) {}
        }

        final bool hadNetUpdate =
            netDataResult is List &&
            netDataResult.length > 1 &&
            netDataResult[0] == 0;
        final bool hadSysUpdate =
            sysResult is List && sysResult.length > 1 && sysResult[0] == 0;

        if (hadNetUpdate) {
          final rawNet = netDataResult[1];
          final networkData = rawNet is Map
              ? Map<String, dynamic>.from(rawNet)
              : null;

          if (networkData != null) {
            _dashboardController?.updateNetworkDevices(networkData);
          }

          final rawDump = dashboardData?['interfaceDump'];
          final interfaceDump = rawDump is Map
              ? Map<String, dynamic>.from(rawDump)
              : null;
          final wanDeviceNames =
              ThroughputController.resolveThroughputDeviceNames(interfaceDump);

          final specificInterface =
              ThroughputController.resolveSpecificInterface(
                dashboardPreferences,
                deviceNameResolver: (iface) => getDeviceNameForInterface(iface),
              );

          _throughputController?.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
        }

        if (hadNetUpdate || hadSysUpdate) {
          notifyListenersDeferrable();
        }
      } catch (_) {}
    } finally {
      _isUpdatingThroughput = false;
    }
  }

  void startThroughputTimer() {
    _startThroughputTimer();
  }

  void cancelThroughputTimer() {
    _throughputController?.cancelAndClear();
  }

  void pauseThroughputTimer() {
    _throughputController?.pauseTimer();
  }

  void resumeThroughputTimer({bool immediateTick = false}) {
    if (isThroughputPollingActive && hasActiveSession && !_isRebooting) {
      if (_isDashboardTabActive && _realtimeTelemetryConsumers == 0) {
        _throughputController?.setInterval(
          2,
          isRebooting: _isRebooting,
          onTick: _updateThroughputOnly,
          immediateTick: immediateTick,
        );
      } else {
        _throughputController?.resumeTimer(
          isRebooting: _isRebooting,
          onTick: _updateThroughputOnly,
          immediateTick: immediateTick,
        );
      }
    }
  }

  void _cancelThroughputTimer() {
    cancelThroughputTimer();
  }

  Future<bool> reboot({BuildContext? context}) async {
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    _cancelThroughputTimer();

    _isRebooting = true;
    notifyListeners();

    try {
      final result = await _apiService!.reboot(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        context: context,
      );
      Future.delayed(const Duration(seconds: 30), () {
        _pollRouterAvailability();
      });
      return result;
    } catch (e) {
      _isRebooting = false;
      notifyListeners();
      return false;
    }
  }

  void _pollRouterAvailability() {
    _pollAttempts = 0;
    _pollingTimer?.cancel();

    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    if (_pollAttempts >= _maxPollAttempts) {
      _isRebooting = false;
      notifyListeners();

      _notifyRouterBackOnline(success: false);
      return;
    }

    int delaySeconds;
    if (_pollAttempts < 2) {
      delaySeconds = 3;
    } else if (_pollAttempts < 4) {
      delaySeconds = 5;
    } else if (_pollAttempts < 6) {
      delaySeconds = 8;
    } else if (_pollAttempts < 8) {
      delaySeconds = 12;
    } else if (_pollAttempts < 10) {
      delaySeconds = 18;
    } else {
      delaySeconds = 20;
    }

    _pollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      _pollAttempts++;
      final available = await _pingRouter();

      if (available) {
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _isRebooting = false;
        _pollAttempts = 0;
        notifyListeners();

        _notifyRouterBackOnline(success: true);

        if (_routerService?.selectedRouter != null) {
          await login(
            _routerService!.selectedRouter!.ipAddress,
            _routerService!.selectedRouter!.username,
            _routerService!.selectedRouter!.password,
            _routerService!.selectedRouter!.useHttps,
          );
        }
      } else {
        _scheduleNextPoll();
      }
    });
  }

  Future<bool> _pingRouter() async {
    if (_authService?.ipAddress == null) return false;

    if (_pollAttempts == 0) {
      _httpClientManager.disposeClient(
        _authService!.ipAddress!,
        _authService!.useHttps,
      );
    }

    final scheme = _authService!.useHttps ? 'https' : 'http';
    final endpoints = ['/', '/cgi-bin/luci/', '/cgi-bin/luci/admin'];

    for (final endpoint in endpoints) {
      try {
        final url = '$scheme://${_authService!.ipAddress}$endpoint';

        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
            followRedirects: false,
            validateStatus: (code) => code != null && code >= 200 && code < 500,
          ),
        );

        if (_authService!.useHttps) {
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            final httpClient = HttpClient();
            httpClient.connectionTimeout = const Duration(seconds: 15);
            httpClient.badCertificateCallback = (cert, host, port) => true;
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }

        final response = await dio.get(url);

        final isAlive =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 500;

        if (isAlive) {
          if (_pollAttempts > 5) {
            await Future.delayed(const Duration(seconds: 10));
          }
          return true;
        }
      } catch (e) {
        if (endpoint == endpoints.last) {
          if (e is SocketException) {
          } else if (e is HandshakeException) {}
        }
      }
    }

    return false;
  }

  Future<bool> checkRouterAvailability() async {
    if (reviewerModeEnabled || _authService?.ipAddress == null) {
      return reviewerModeEnabled;
    }
    return await _authService!.checkRouterAvailability(
      _authService!.ipAddress!,
      _authService!.useHttps,
    );
  }

  Set<String> get pausedInternetMacs {
    final result = <String>{
      ...(_networkActionsController?.pausedInternetMacs ?? {}),
    };
    final rawFirewall = dashboardData?['uciFirewallConfig'];
    if (rawFirewall is Map) {
      final overview = FirewallOverview.fromUciData(
        Map<String, dynamic>.from(rawFirewall),
        backend: capabilities?.firewallBackend ?? FirewallBackend.fw4,
        isReviewerMode: reviewerModeEnabled,
      );
      for (final rule in overview.customRules) {
        if (!rule.enabled) continue;
        final target = rule.target.toUpperCase();
        if (target != 'DROP' && target != 'REJECT' && target != 'STOP') {
          continue;
        }
        for (final m in rule.srcMac) {
          final norm = ClientNamingHelper.normalizeMac(m);
          if (norm.isNotEmpty) {
            result.add(norm);
          }
        }
      }
    }
    for (final profile in ParentalControlsStore.instance.profiles) {
      if (ParentalControlsStore.instance.isProfileCurrentlyBlocked(profile)) {
        for (final m in profile.macAddresses) {
          final norm = ClientNamingHelper.normalizeMac(m);
          if (norm.isNotEmpty) {
            result.add(norm);
          }
        }
      }
    }
    return result;
  }

  Set<String> get bannedWirelessMacs =>
      _networkActionsController?.bannedWirelessMacs ?? {};

  bool isInternetPaused(String mac) =>
      getDeviceNetworkAccessPolicy(mac).isEffectivelyBlocked;

  bool isWirelessBanned(String mac) =>
      _networkActionsController?.isWirelessBanned(mac) ?? false;

  bool isRestrictedOrBanned(String mac) =>
      isInternetPaused(mac) || isWirelessBanned(mac);

  Future<bool> disconnectWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) => _networkActionsController!.disconnectWirelessClient(
    macAddress,
    iface: iface,
    banTimeSeconds: banTimeSeconds,
    context: context,
  );

  Future<bool> pauseClientInternet(
    String macAddress, {
    required bool pause,
    BuildContext? context,
  }) {
    final normMac = ClientNamingHelper.normalizeMac(macAddress);
    final policy = pause
        ? NetworkAccessPolicy.blocked(normMac)
        : NetworkAccessPolicy.unrestricted(normMac);
    return setDeviceNetworkAccessPolicy(policy: policy, context: context);
  }

  Future<bool> applyParentalProfileDns({
    required String profileId,
    required List<String> macAddresses,
    required List<String>? dnsServers,
    BuildContext? context,
  }) => _networkActionsController!.applyParentalProfileDns(
    profileId: profileId,
    macAddresses: macAddresses,
    dnsServers: dnsServers,
    context: context,
  );

  Future<List<ParentalProfile>?> fetchParentalProfiles({
    BuildContext? context,
  }) => _networkActionsController!.fetchParentalProfiles(context: context);

  Future<bool> saveParentalProfile({
    required ParentalProfile profile,
    BuildContext? context,
  }) => _networkActionsController!.saveParentalProfile(
    profile: profile,
    context: context,
  );

  Future<bool> deleteParentalProfile({
    required String profileId,
    BuildContext? context,
  }) => _networkActionsController!.deleteParentalProfile(
    profileId: profileId,
    context: context,
  );

  Future<bool> addStaticLease({
    required String macAddress,
    required String targetIp,
    required String hostname,
    String? targetIp6,
    String? duid,
    String? leaseTime,
    BuildContext? context,
  }) async {
    final res = await _networkActionsController!.addStaticLease(
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      targetIp6: targetIp6,
      duid: duid,
      leaseTime: leaseTime,
      context: context,
    );
    if (res) {
      invalidateStaticLeasesCache();
      unawaited(fetchDashboardData());
      unawaited(fetchClientsForSelectedRouter());
    }
    return res;
  }

  Future<bool> deleteStaticLease({
    required String macAddress,
    String? targetIp,
    String? hostname,
    String? duid,
    BuildContext? context,
  }) async {
    invalidateStaticLeasesCache();
    final res = await _networkActionsController!.deleteStaticLease(
      macAddress: macAddress,
      targetIp: targetIp,
      hostname: hostname,
      duid: duid,
      context: context,
    );
    invalidateStaticLeasesCache();
    if (res) {
      unawaited(fetchDashboardData());
      unawaited(fetchClientsForSelectedRouter());
    }
    return res;
  }

  Future<bool> forceRefreshDhcpLeases({BuildContext? context}) async {
    final res = await _networkActionsController!.forceRefreshDhcpLeases(
      context: context,
    );
    await fetchClientsForSelectedRouter();
    await fetchDashboardData();

    if (dashboardData != null) {
      dashboardData!['forcePurged'] = true;
      dashboardData!['forcePurgedAt'] = DateTime.now().millisecondsSinceEpoch;
      if (clients.isNotEmpty) {
        dashboardData!['clients'] = clients
            .map(
              (c) => {
                'macAddress': c.macAddress,
                'ipAddress': c.ipAddress,
                'hostname': c.hostname,
                'isConnected': c.isConnected,
                'isOnline': c.isConnected,
                'isStaticLease': c.isStaticLease,
              },
            )
            .toList();
      }
    }

    notifyListenersDeferrable();
    return res;
  }

  Future<bool> refreshClientConnection({
    required String macAddress,
    BuildContext? context,
  }) => _networkActionsController!.refreshClientConnection(
    macAddress: macAddress,
    context: context,
  );

  Future<bool> updateRouterHostname(
    String newHostname, {
    BuildContext? context,
  }) => _networkActionsController!.updateRouterHostname(
    newHostname,
    context: context,
  );

  Future<int> flushUnusedDhcpLeases({
    List<Client>? clients,
    List<String>? macsToFlush,
    BuildContext? context,
  }) => _networkActionsController!.flushUnusedDhcpLeases(
    clients: clients,
    macsToFlush: macsToFlush,
    context: context,
  );

  Future<bool> banWirelessClient(
    String macAddress, {
    String? iface,
    int banTimeSeconds = 300,
    BuildContext? context,
  }) => _networkActionsController!.banWirelessClient(
    macAddress,
    iface: iface,
    banTimeSeconds: banTimeSeconds,
    context: context,
  );

  Future<bool> unbanWirelessClient(
    String macAddress, {
    BuildContext? context,
  }) => _networkActionsController!.unbanWirelessClient(
    macAddress,
    context: context,
  );

  Future<Map<String, List<Map<String, dynamic>>>>
  fetchRestrictedAndBannedClientsLive({BuildContext? context}) async {
    if (reviewerModeEnabled) {
      return {
        'restricted': [
          {
            'mac': '11:22:33:44:55:66',
            'name': 'Restricted-Tablet',
            'ip': '192.168.1.150',
            'type': 'restricted',
          },
        ],
        'banned': [
          {
            'mac': '99:88:77:66:55:44',
            'name': 'Banned-Guest-Phone',
            'ip': 'N/A',
            'type': 'banned',
          },
        ],
      };
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return {'restricted': [], 'banned': []};
    }
    final data = await _apiService!.fetchRestrictedAndBannedClientsLive(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      context: context,
    );

    data['restricted'] ??= [];
    data['banned'] ??= [];

    final bannedSet = data['banned']!
        .map((e) => e['mac']?.toString().toUpperCase() ?? '')
        .where((m) => m.isNotEmpty)
        .toSet();

    for (final mac in bannedWirelessMacs) {
      if (!bannedSet.contains(mac)) {
        bannedSet.add(mac);
        data['banned']!.add({
          'mac': mac,
          'name': mac,
          'ip': 'N/A',
          'type': 'banned',
          'source': 'Wi-Fi Access Control (Banned)',
        });
      }
    }

    final restrictedSet = data['restricted']!
        .map((e) => e['mac']?.toString().toUpperCase() ?? '')
        .where((m) => m.isNotEmpty)
        .toSet();

    for (final mac in pausedInternetMacs) {
      if (!restrictedSet.contains(mac)) {
        restrictedSet.add(mac);
        data['restricted']!.add({
          'mac': mac,
          'name': mac,
          'ip': 'N/A',
          'type': 'restricted',
          'source': 'Internet Access Paused',
        });
      }
    }

    final clientMap = {
      for (final c in clients)
        c.macAddress.toUpperCase().replaceAll('-', ':'): c,
    };

    for (final listKey in ['restricted', 'banned']) {
      for (final item in data[listKey]!) {
        final mac =
            item['mac']?.toString().toUpperCase().replaceAll('-', ':') ?? '';
        final client = clientMap[mac];
        if (client != null) {
          if (item['name'] == null || item['name'] == mac) {
            item['name'] = client.displayName;
          }
          if (item['ip'] == null || item['ip'] == 'N/A') {
            item['ip'] = client.ipAddress;
          }
        }
      }
    }

    _networkActionsController?.updatePausedInternetMacs(restrictedSet);
    _networkActionsController?.updateBannedWirelessMacs(bannedSet);

    return data;
  }

  void _safeSetMapEntry(Map target, dynamic key, dynamic value) {
    try {
      target[key] = value;
    } catch (_) {
      try {
        if (value is bool) {
          target[key] = value ? '1' : '0';
        } else if (value is String) {
          if (value == '1') {
            target[key] = true;
          } else if (value == '0') {
            target[key] = false;
          }
        }
      } catch (_) {}
    }
  }

  void _mutateWirelessRadioInMemory(String radioName, bool enable) {
    if (dashboardData != null) {
      if (dashboardData!['uciWirelessConfig'] is Map) {
        final uci = dashboardData!['uciWirelessConfig'] as Map;
        final uciValues = (uci['values'] is Map) ? (uci['values'] as Map) : uci;
        if (uciValues[radioName] is Map) {
          _safeSetMapEntry(
            uciValues[radioName] as Map,
            'disabled',
            enable ? '0' : '1',
          );
        } else {
          uciValues[radioName] = {'disabled': enable ? '0' : '1'};
        }
      }
      if (dashboardData!['wireless'] is Map) {
        final wMap = dashboardData!['wireless'] as Map;
        if (wMap[radioName] is Map) {
          final r = wMap[radioName] as Map;
          _safeSetMapEntry(r, 'up', enable);
          _safeSetMapEntry(r, 'disabled', !enable);
          if (r['config'] is Map) {
            _safeSetMapEntry(r['config'] as Map, 'disabled', !enable);
          }
        }
      }
    }
  }

  void _mutateSsidInMemory(String ifaceSection, bool enabled) {
    if (dashboardData != null) {
      if (dashboardData!['uciWirelessConfig'] is Map) {
        final uci = dashboardData!['uciWirelessConfig'] as Map;
        final uciValues = (uci['values'] is Map) ? (uci['values'] as Map) : uci;
        if (uciValues[ifaceSection] is Map) {
          _safeSetMapEntry(
            uciValues[ifaceSection] as Map,
            'disabled',
            enabled ? '0' : '1',
          );
        } else {
          uciValues[ifaceSection] = {'disabled': enabled ? '0' : '1'};
        }
      }
      if (dashboardData!['wireless'] is Map) {
        final wMap = dashboardData!['wireless'] as Map;
        for (final r in wMap.values) {
          if (r is Map && r['interfaces'] is List) {
            for (final iface in (r['interfaces'] as List)) {
              if (iface is Map &&
                  (iface['section'] == ifaceSection ||
                      iface['ifname'] == ifaceSection)) {
                _safeSetMapEntry(iface, 'disabled', !enabled);
                _safeSetMapEntry(iface, 'up', enabled);
                if (iface['config'] is Map) {
                  _safeSetMapEntry(
                    iface['config'] as Map,
                    'disabled',
                    enabled ? '0' : '1',
                  );
                }
              }
            }
          }
        }
      }
    }
  }

  Future<bool> setSsidEnabled(
    String ifaceSection,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 300));
      _mutateSsidInMemory(ifaceSection, enabled);
      invalidateInFlightDashboardFetches();
      notifyListeners();
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }
    final res = await _apiService!.setSsidEnabled(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      ifaceSection: ifaceSection,
      enabled: enabled,
      context: context,
    );
    if (res) {
      _mutateSsidInMemory(ifaceSection, enabled);
      invalidateInFlightDashboardFetches();
      notifyListeners();
      unawaited(fetchDashboardData());
    }
    return res;
  }

  Future<bool> toggleWirelessRadio(
    String radioName,
    bool enable, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 300));
      _mutateWirelessRadioInMemory(radioName, enable);
      invalidateInFlightDashboardFetches();
      notifyListeners();
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }
    final res = await _apiService!.toggleWirelessRadio(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      radioName: radioName,
      enabled: enable,
      context: context,
    );
    if (res) {
      _mutateWirelessRadioInMemory(radioName, enable);
      invalidateInFlightDashboardFetches();
      notifyListeners();
      unawaited(fetchDashboardData());
    }
    return res;
  }

  static const String _wifiAccessControlPendingKey =
      'wifi_access_control_pending_revert';

  Future<void> _saveAccessControlPendingState(int startTimeMs) async {
    try {
      final payload = {
        'timestamp': startTimeMs,
        'priorMaclist': _networkActionsController?.priorMaclistSnapshot ?? {},
        'priorMacfilter':
            _networkActionsController?.priorMacfilterSnapshot ?? {},
      };
      await _secureStorageService.writeValue(
        _wifiAccessControlPendingKey,
        jsonEncode(payload),
      );
    } catch (e, stack) {
      Logger.exception('Failed to save access control pending state', e, stack);
    }
  }

  Future<void> _clearAccessControlPendingState() async {
    try {
      await _secureStorageService.deleteValue(_wifiAccessControlPendingKey);
    } catch (e, stack) {
      Logger.exception(
        'Failed to clear access control pending state',
        e,
        stack,
      );
    }
  }

  Future<void> _loadPendingAccessControlState() async {
    try {
      final jsonStr = await _secureStorageService.readValue(
        _wifiAccessControlPendingKey,
      );
      if (jsonStr == null || jsonStr.isEmpty) return;
      await _clearAccessControlPendingState();
    } catch (e, stack) {
      Logger.exception('Failed to load pending access control state', e, stack);
    }
  }

  Future<bool> applyWifiAccessControl({
    required Map<String, List<String>> newMaclistByIface,
    required Map<String, String> newMacfilterByIface,
    required Map<String, List<String>> priorMaclistSnapshot,
    required Map<String, String> priorMacfilterSnapshot,
    BuildContext? context,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final success = await _networkActionsController!.applyWifiAccessControl(
      newMaclistByIface: newMaclistByIface,
      newMacfilterByIface: newMacfilterByIface,
      priorMaclistSnapshot: priorMaclistSnapshot,
      priorMacfilterSnapshot: priorMacfilterSnapshot,
      context: context,
    );

    if (success) {
      await _saveAccessControlPendingState(nowMs);
    } else {
      await _clearAccessControlPendingState();
    }
    return success;
  }

  Future<bool> confirmWifiAccessControlChanges() async {
    await _clearAccessControlPendingState();
    return await _networkActionsController!.confirmWifiAccessControlChanges();
  }

  Future<bool> revertWifiAccessControlChanges({BuildContext? context}) async {
    await _clearAccessControlPendingState();
    return await _networkActionsController!.revertWifiAccessControlChanges(
      context: (context != null && context.mounted) ? context : null,
    );
  }

  Future<bool> autoFixPermissions({BuildContext? context}) async {
    final freshCaps = await probeRouterCapabilities(forceRefresh: true);
    if (freshCaps.isRpcComplete) {
      Logger.info(
        'autoFixPermissions: Router permissions and RPC packages are already verified and complete. Skipping redundant fix script.',
      );
      notifyListeners();
      return true;
    }

    if (context != null && context.mounted) {
      final rpcSuccess = await _networkActionsController!.autoFixPermissions(
        context: context,
      );
      if (rpcSuccess) return true;
    } else {
      final rpcSuccess = await _networkActionsController!.autoFixPermissions();
      if (rpcSuccess) return true;
    }

    final ip = selectedRouter?.ipAddress;
    final username = selectedRouter?.username ?? 'root';
    String? password = selectedRouter?.password;
    if (password == null || password.isEmpty) {
      final creds = await _secureStorageService.getCredentials();
      password = creds['password'];
    }

    if (ip != null &&
        password != null &&
        password.isNotEmpty &&
        _sshService != null) {
      Logger.info(
        'HTTP RPC autoFixPermissions restricted. Falling back to SSH for $username@$ip...',
      );
      final fixScript = ApiService.getPermissionsFixScript();

      final res = await _sshService!.executeCommand(
        host: ip,
        username: username,
        password: password,
        command: fixScript,
        timeout: const Duration(seconds: 60),
      );

      if (res.success) {
        Logger.info('Automated SSH autoFixPermissions succeeded on $ip');
        await redetectCapabilities();
        await fetchDashboardData();
        notifyListeners();
        return true;
      }
    }

    return false;
  }

  Future<bool> installNativeTemperatureHandler({BuildContext? context}) async {
    final ip = selectedRouter?.ipAddress;
    final auth = sysauth;
    final useHttps = selectedRouter?.useHttps ?? false;
    if (ip == null) return false;

    if (auth != null) {
      try {
        final rpcSuccess = await _apiService!.installNativeTemperatureHandler(
          ip,
          auth,
          useHttps,
          context: context,
        );
        if (rpcSuccess) {
          await fetchDashboardData();
          return true;
        }
      } catch (e) {
        Logger.warning('HTTP RPC install attempt failed: $e');
      }
    }

    final router = selectedRouter;
    final username = router?.username ?? 'root';
    String? password = router?.password;
    if (password == null || password.isEmpty) {
      final creds = await _secureStorageService.getCredentials();
      password = creds['password'];
    }

    if (password != null && password.isNotEmpty && _sshService != null) {
      Logger.info(
        'HTTP RPC installation was restricted. Falling back to SSH installation for $username@$ip...',
      );
      const installScript =
          'mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d && '
          'cat << \'EOF\' > /usr/libexec/rpcd/luci.temp-status\n'
          '#!/bin/sh\n'
          'case "\$1" in\n'
          'list) echo \'{"getSensors":{}}\' ;;\n'
          'call) case "\$2" in getSensors)\n'
          'hw=""; for h in /sys/class/hwmon/hwmon*; do [ -d "\$h" ] || continue; n=\$(cat "\$h/name" 2>/dev/null || echo hwmon); s=""; for t in "\$h"/temp*_input; do [ -f "\$t" ] || continue; v=\$(cat "\$t" 2>/dev/null); [ -n "\$v" ] || continue; l=\$(cat "\${t%_input}_label" 2>/dev/null); i="\${t##*/}"; [ -n "\$s" ] && s="\$s," || true; s="\$s{\\"item\\":\\"\$i\\",\\"label\\":\\"\$l\\",\\"temp\\":\$v}"; done; [ -n "\$s" ] && { [ -n "\$hw" ] && hw="\$hw," || true; hw="\$hw{\\"title\\":\\"\$n\\",\\"item\\":\\"\${h##*/}\\",\\"sources\\":[\$s]}"; }; done\n'
          'tz=""; for z in /sys/class/thermal/thermal_zone*; do [ -d "\$z" ] || continue; v=\$(cat "\$z/temp" 2>/dev/null); [ -n "\$v" ] || continue; y=\$(cat "\$z/type" 2>/dev/null || echo tz); [ -n "\$tz" ] && tz="\$tz," || true; tz="\$tz{\\"title\\":\\"\$y\\",\\"item\\":\\"\${z##*/}\\",\\"sources\\":[{\\"item\\":\\"temp\\",\\"label\\":\\"\$y\\",\\"temp\\":\$v}]}"; done\n'
          'printf \'{"sensors":{"0":[%s],"1":[%s]}}\\n\' "\$hw" "\$tz" ;; esac ;; esac\n'
          'EOF\n'
          'chmod +x /usr/libexec/rpcd/luci.temp-status && '
          'cat << \'EOF\' > /usr/share/rpcd/acl.d/luci-app-temp-status.json\n'
          '{"luci-app-temp-status":{"description":"Native Temperature RPC Handler","read":{"ubus":{"luci.temp-status":["getSensors"]}}}}\n'
          'EOF\n'
          '(/etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true)';

      final res = await _sshService!.executeCommand(
        host: ip,
        username: username,
        password: password,
        command: installScript,
      );

      if (res.success) {
        Logger.info('Automated SSH temperature installation succeeded on $ip');
        await fetchDashboardData();
        return true;
      } else {
        Logger.warning(
          'Automated SSH temperature installation failed: ${res.errorMessage ?? res.stderr}',
        );
      }
    }

    return false;
  }

  Future<bool> manageServiceAction(
    String serviceName,
    String action, {
    BuildContext? context,
  }) => _networkActionsController!.manageServiceAction(
    serviceName,
    action,
    context: context,
  );

  Future<String?> routerPassword() async {
    final saved = selectedRouter?.password;
    if (saved != null && saved.isNotEmpty) return saved;
    try {
      final p = (await _secureStorageService.getCredentials())['password'];
      return (p == null || p.isEmpty) ? null : p;
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveCronJobs(
    List<String> cronLines, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['cronJobs'] = List<String>.from(cronLines);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveCronJobs(
      ip,
      sysauth!,
      useHttps,
      cronLines: cronLines,
      context: context,
    );

    if (success) {
      if (dashboardData != null) {
        dashboardData!['cronJobs'] = List<String>.from(cronLines);
      }
      notifyListeners();
    }

    return success;
  }

  Future<bool> saveDdnsInstance(
    DdnsInstance instance, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        final overview = DdnsOverview.fromDashboardData(
          dashboardData,
          isReviewerMode: true,
        );
        final list = List<DdnsInstance>.from(overview.instances);
        final existingIdx = list.indexWhere((i) => i.name == instance.name);
        if (existingIdx >= 0) {
          list[existingIdx] = instance;
        } else {
          list.add(instance);
        }
        dashboardData!['ddns'] = {
          'global': {'is_enabled': '1'},
          for (final item in list)
            item.name: item.toUciParams()..['.type'] = 'service',
        };
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveDdnsInstance(
      ip,
      sysauth!,
      useHttps,
      instance: instance,
      context: context,
    );

    if (success) {
      if (dashboardData != null && dashboardData!['ddns'] is Map) {
        dashboardData!['ddns'][instance.name] = instance.toUciParams()
          ..['.type'] = 'service';
      }
      notifyListeners();
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> deleteDdnsInstance(
    String instanceName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null && dashboardData!['ddns'] is Map) {
        (dashboardData!['ddns'] as Map).remove(instanceName);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.deleteDdnsInstance(
      ip,
      sysauth!,
      useHttps,
      instanceName: instanceName,
      context: context,
    );

    if (success) {
      if (dashboardData != null && dashboardData!['ddns'] is Map) {
        (dashboardData!['ddns'] as Map).remove(instanceName);
      }
      notifyListeners();
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<DdnsValidationResult> testDdnsConfiguration(
    DdnsInstance instance, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      return _apiService!.testDdnsConfiguration(
        '',
        '',
        false,
        instance: instance,
        context: context,
      );
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) {
      return const DdnsValidationResult(
        isValid: false,
        errorMessage: 'No active router session',
      );
    }
    final useHttps = selectedRouter?.useHttps ?? false;

    return _apiService!.testDdnsConfiguration(
      ip,
      sysauth!,
      useHttps,
      instance: instance,
      context: context,
    );
  }

  Future<bool> toggleGlobalDdns(bool enable, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['ddns'] ??= {};
        dashboardData!['ddns']['global'] = {'is_enabled': enable ? '1' : '0'};
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.toggleGlobalDdns(
      ip,
      sysauth!,
      useHttps,
      enable: enable,
      context: context,
    );

    if (success) {
      invalidateInFlightDashboardFetches();
      if (dashboardData != null) {
        dashboardData!['ddns'] ??= {};
        dashboardData!['ddns']['global'] = {'is_enabled': enable ? '1' : '0'};
      }
      notifyListeners();
      unawaited(fetchDashboardData());
    }

    return success;
  }

  void invalidateInFlightDashboardFetches() {
    _dashboardController?.invalidateInFlightFetches();
  }

  Future<bool> saveSqmQueue(SqmQueue queue, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['sqm'] ??= {};
        dashboardData!['sqm'][queue.name] = queue.toUciParams();
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.saveSqmQueue(
      ip,
      sysauth!,
      useHttps,
      queue: queue,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> deleteSqmQueue(
    String sectionName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null && dashboardData!['sqm'] is Map) {
        (dashboardData!['sqm'] as Map).remove(sectionName);
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.deleteSqmQueue(
      ip,
      sysauth!,
      useHttps,
      sectionName: sectionName,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<bool> toggleSqmService(bool enable, {BuildContext? context}) async {
    if (reviewerModeEnabled) {
      if (dashboardData != null) {
        dashboardData!['initScripts'] ??= {};
        dashboardData!['initScripts']['sqm'] = {
          'enabled': enable,
          'running': enable,
        };
      }
      notifyListeners();
      return true;
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null) return false;
    final useHttps = selectedRouter?.useHttps ?? false;

    final success = await _apiService!.toggleSqmService(
      ip,
      sysauth!,
      useHttps,
      enable: enable,
      context: context,
    );

    if (success) {
      unawaited(fetchDashboardData());
    }

    return success;
  }

  Future<FlushDnsResult> flushDns({BuildContext? context}) async {
    if (reviewerModeEnabled) {
      return FlushDnsResult.success(
        flushedResolvers: const ['dnsmasq'],
        message: 'DNS cache flushed (simulated).',
      );
    }

    final ip = selectedRouter?.ipAddress;
    if (ip == null || sysauth == null || _apiService == null) {
      return FlushDnsResult.failure('No active router session');
    }
    final useHttps = selectedRouter?.useHttps ?? false;

    return _apiService!.flushDns(ip, sysauth!, useHttps, context: context);
  }

  Future<bool> updateFirewallCustomRuleStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateFirewallCustomRuleStatus(
    sectionKey,
    enabled,
    context: context,
  );

  Future<bool> updateFirewallFlowOffloading({
    required bool software,
    required bool hardware,
    String sectionKey = '@defaults[0]',
    BuildContext? context,
  }) => _networkActionsController!.updateFirewallFlowOffloading(
    software: software,
    hardware: hardware,
    sectionKey: sectionKey,
    context: context,
  );

  Future<void> refreshFirewallState() async {
    final ip =
        _routerService?.selectedRouter?.ipAddress ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? '192.168.1.1'
            : null);
    final token =
        _authService?.sysauth ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? 'mock_sysauth'
            : null);
    if (ip == null || token == null || _apiService == null) return;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    try {
      final rawRpc = await _apiService!.call(
        ip,
        token,
        useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'firewall'},
      );
      if (rawRpc is List && rawRpc.length > 1 && rawRpc[1] is Map) {
        if (dashboardData != null) {
          dashboardData!['uciFirewallConfig'] =
              rawRpc[1]['values'] ?? rawRpc[1];
        }
        notifyListeners();
      }
    } catch (e, stack) {
      Logger.exception('refreshFirewallState failed', e, stack);
    }
  }

  Future<bool> addFirewallPortForward(
    FirewallPortForwarding portForward, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.addFirewallPortForward(
      ip,
      token,
      useHttps,
      portForward: portForward,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> updateFirewallPortForward(
    FirewallPortForwarding portForward, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.updateFirewallPortForward(
      ip,
      token,
      useHttps,
      portForward: portForward,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> deleteFirewallPortForward(
    String sectionKey, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.deleteFirewallPortForward(
      ip,
      token,
      useHttps,
      sectionKey: sectionKey,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> addFirewallCustomRule(
    FirewallCustomRule rule, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.addFirewallCustomRule(
      ip,
      token,
      useHttps,
      rule: rule,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> updateFirewallCustomRule(
    FirewallCustomRule rule, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.updateFirewallCustomRule(
      ip,
      token,
      useHttps,
      rule: rule,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> deleteFirewallCustomRule(
    String sectionKey, {
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.deleteFirewallCustomRule(
      ip,
      token,
      useHttps,
      sectionKey: sectionKey,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> reorderFirewallCustomRules({
    required String targetSectionKey,
    required String siblingSectionKey,
    required List<String> expectedRuleOrder,
    BuildContext? context,
  }) async {
    final ip = _routerService?.selectedRouter?.ipAddress;
    final token = _authService?.sysauth;
    if (ip == null || token == null || _apiService == null) return false;
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.reorderFirewallCustomRules(
      ip,
      token,
      useHttps,
      targetSectionKey: targetSectionKey,
      siblingSectionKey: siblingSectionKey,
      expectedRuleOrder: expectedRuleOrder,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  Future<bool> applyPerDeviceNetworkAccessPolicy({
    required NetworkAccessPolicy policy,
    BuildContext? context,
  }) async {
    final ip =
        _routerService?.selectedRouter?.ipAddress ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? '192.168.1.1'
            : null);
    final token =
        _authService?.sysauth ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? 'mock_sysauth'
            : null);
    final caps =
        capabilities ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? RouterCapabilities.mock()
            : null);
    if (ip == null || token == null || caps == null || _apiService == null) {
      return false;
    }
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;
    final success = await _apiService!.applyPerDeviceNetworkAccessPolicy(
      ip,
      token,
      useHttps,
      policy: policy,
      capabilities: caps,
      context: context,
    );
    if (success) {
      await refreshFirewallState();
    }
    return success;
  }

  NetworkAccessPolicy getDeviceNetworkAccessPolicy(String mac) {
    final normMac = ClientNamingHelper.normalizeMac(mac);
    final expiry = ClientPolicyScheduleService.instance.getExpiry(normMac);

    if (expiry != null && DateTime.now().isAfter(expiry)) {
      return NetworkAccessPolicy.unrestricted(normMac);
    }

    if (reviewerModeEnabled || _apiService is MockApiService) {
      final mockP = MockApiService.getMockPolicy(normMac);
      if (mockP != null) {
        return mockP.copyWith(scheduleExpiry: expiry);
      }
    }

    final rawFirewall = dashboardData?['uciFirewallConfig'];
    if (rawFirewall is Map) {
      final overview = FirewallOverview.fromUciData(
        Map<String, dynamic>.from(rawFirewall),
        backend: capabilities?.firewallBackend ?? FirewallBackend.fw4,
        isReviewerMode: reviewerModeEnabled,
      );
      final recognized = FirewallPolicyTranslator.recognizePolicy(
        targetMac: normMac,
        rules: overview.customRules,
      );
      if (recognized.hasActiveBlock) {
        return recognized.policy.copyWith(scheduleExpiry: expiry);
      }
    }

    if (_networkActionsController?.isInternetPaused(normMac) ?? false) {
      return NetworkAccessPolicy.blocked(normMac, scheduleExpiry: expiry);
    }

    if (ParentalControlsStore.instance.isMacPaused(normMac)) {
      return NetworkAccessPolicy.blocked(normMac, scheduleExpiry: expiry);
    }

    return NetworkAccessPolicy.unrestricted(normMac);
  }

  Future<bool> setDeviceNetworkAccessPolicy({
    required NetworkAccessPolicy policy,
    BuildContext? context,
  }) async {
    final normMac = ClientNamingHelper.normalizeMac(policy.targetMac);
    final normalizedPolicy = policy.copyWith(targetMac: normMac);

    if (normalizedPolicy.isEffectivelyBlocked) {
      if (context != null && context.mounted) {
        final safe = await SelfDeviceGuard.checkSelfActionGuardrail(
          context,
          actionName: 'Block Internet Access',
          targetMac: normMac,
        );
        if (!safe) return false;
      } else {
        final isSelf = await SelfDeviceGuard.isSelfDevice(normMac);
        if (isSelf) {
          Logger.warning(
            'SelfDeviceGuard aborted: cannot block managing device ($normMac)',
          );
          return false;
        }
      }
    }

    final success = await applyPerDeviceNetworkAccessPolicy(
      policy: normalizedPolicy,
    );

    if (success) {
      if (normalizedPolicy.scheduleExpiry != null &&
          normalizedPolicy.isEffectivelyBlocked) {
        await ClientPolicyScheduleService.instance.saveSchedule(
          policy: normalizedPolicy,
        );
      } else {
        await ClientPolicyScheduleService.instance.clearSchedule(normMac);
      }

      _networkActionsController?.setInternetPausedLocally(
        normMac,
        normalizedPolicy.isEffectivelyBlocked,
      );

      if (!normalizedPolicy.isEffectivelyBlocked) {
        final parentalProfiles = ParentalControlsStore.instance.profilesForMac(
          normMac,
        );
        for (final p in parentalProfiles) {
          if (p.isPaused) {
            await ParentalControlsController.instance.resumeProfile(
              p,
              appState: this,
            );
          } else if (ParentalControlsStore.instance.isProfileCurrentlyBlocked(
            p,
          )) {
            ParentalControlsStore.instance.toggleProfileEnabled(
              p.id,
              enabled: false,
            );
            await saveParentalProfile(profile: p.copyWith(isEnabled: false));
          }
        }
      }

      notifyListeners();
    }
    return success;
  }

  Future<void> checkExpiredDevicePolicies() async {
    final expiredSchedules = ClientPolicyScheduleService.instance
        .getExpiredSchedules();
    if (expiredSchedules.isEmpty) return;

    for (final schedule in expiredSchedules) {
      final normMac = schedule.targetMac;
      final currentExpiry = ClientPolicyScheduleService.instance.getExpiry(
        normMac,
      );
      if (currentExpiry == null || currentExpiry != schedule.scheduleExpiry) {
        continue;
      }

      Logger.info('Expiring scheduled network block for $normMac');
      await setDeviceNetworkAccessPolicy(
        policy: NetworkAccessPolicy.unrestricted(normMac),
      );
      await ClientPolicyScheduleService.instance.clearSchedule(normMac);
    }
    notifyListeners();
  }

  final Map<String, Map<String, ClientSpeedLimit>> _speedLimitsByRouter = {};

  String _getEffectiveSpeedLimitRouterKey(String? routerId) {
    return routerId ?? selectedRouter?.id ?? 'default';
  }

  ClientSpeedLimit? getClientSpeedLimit(String mac, {String? routerId}) {
    final rKey = _getEffectiveSpeedLimitRouterKey(routerId);
    final normMac = ClientNamingHelper.normalizeMac(mac);

    if (_speedLimitsByRouter.containsKey(rKey)) {
      return _speedLimitsByRouter[rKey]?[normMac];
    }

    if (reviewerModeEnabled || _apiService is MockApiService) {
      final mock = MockApiService.getMockSpeedLimit(normMac, routerId: rKey);
      if (mock != null) return mock;
    }

    return null;
  }

  List<ClientSpeedLimit> getActiveSpeedLimitsForRouter({String? routerId}) {
    final rKey = _getEffectiveSpeedLimitRouterKey(routerId);

    if (_speedLimitsByRouter.containsKey(rKey)) {
      final limits = _speedLimitsByRouter[rKey]?.values.toList() ?? [];
      return limits.where((l) => l.isEffectivelyRestricted).toList();
    }

    if (reviewerModeEnabled || _apiService is MockApiService) {
      final mockLimits = MockApiService.getMockSpeedLimitsForRouter(rKey);
      if (mockLimits.isNotEmpty) {
        return mockLimits.values
            .where((l) => l.isEffectivelyRestricted)
            .toList();
      }
      return MockApiService.allMockSpeedLimits.values
          .where((l) => l.isEffectivelyRestricted)
          .toList();
    }

    return [];
  }

  Future<void> loadSpeedLimitsForRouter(String routerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('router_${routerId}_speed_limits');
      final map = <String, ClientSpeedLimit>{};
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is Map<String, dynamic>) {
            map[ClientNamingHelper.normalizeMac(key)] =
                ClientSpeedLimit.fromJson(val);
          }
        });
      }
      _speedLimitsByRouter[routerId] = map;
      notifyListeners();
    } catch (e) {
      Logger.warning('loadSpeedLimitsForRouter error: $e');
    }
  }

  Future<void> _persistSpeedLimitsForRouter(String routerId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _speedLimitsByRouter[routerId] ?? {};
      final jsonMap = <String, dynamic>{};
      map.forEach((k, v) => jsonMap[k] = v.toJson());
      await prefs.setString(
        'router_${routerId}_speed_limits',
        jsonEncode(jsonMap),
      );
    } catch (e) {
      Logger.warning('_persistSpeedLimitsForRouter error: $e');
    }
  }

  Future<bool> setClientSpeedLimit({
    required ClientSpeedLimit speedLimit,
    String? routerId,
    BuildContext? context,
  }) async {
    final rKey = _getEffectiveSpeedLimitRouterKey(routerId);
    final normMac = ClientNamingHelper.normalizeMac(speedLimit.targetMac);
    final normalizedLimit = speedLimit.copyWith(targetMac: normMac);

    if (!_speedLimitsByRouter.containsKey(rKey)) {
      _speedLimitsByRouter[rKey] = {};
    }

    if (normalizedLimit.isEffectivelyRestricted) {
      _speedLimitsByRouter[rKey]![normMac] = normalizedLimit;
    } else {
      _speedLimitsByRouter[rKey]!.remove(normMac);
    }

    final allLimits = _speedLimitsByRouter[rKey]!.values.toList();

    final ip =
        _routerService?.selectedRouter?.ipAddress ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? '192.168.1.1'
            : null);
    final token =
        _authService?.sysauth ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? 'mock_sysauth'
            : null);
    final caps =
        capabilities ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? RouterCapabilities.mock()
            : null);
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    if (_apiService != null && ip != null && token != null && caps != null) {
      final success = await _apiService!.applyClientSpeedLimits(
        ip,
        token,
        useHttps,
        limits: allLimits,
        capabilities: caps,
        context: context,
      );

      if (!success) {
        return false;
      }
    }

    await _persistSpeedLimitsForRouter(rKey);
    notifyListeners();
    return true;
  }

  Future<bool> removeClientSpeedLimit(
    String mac, {
    String? routerId,
    BuildContext? context,
  }) async {
    final rKey = _getEffectiveSpeedLimitRouterKey(routerId);
    final normMac = ClientNamingHelper.normalizeMac(mac);

    if (!_speedLimitsByRouter.containsKey(rKey) ||
        !_speedLimitsByRouter[rKey]!.containsKey(normMac)) {
      return true;
    }

    _speedLimitsByRouter[rKey]!.remove(normMac);
    final allLimits = _speedLimitsByRouter[rKey]!.values.toList();

    final ip =
        _routerService?.selectedRouter?.ipAddress ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? '192.168.1.1'
            : null);
    final token =
        _authService?.sysauth ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? 'mock_sysauth'
            : null);
    final caps =
        capabilities ??
        (reviewerModeEnabled || _apiService is MockApiService
            ? RouterCapabilities.mock()
            : null);
    final useHttps = _routerService?.selectedRouter?.useHttps ?? false;

    if (_apiService != null && ip != null && token != null && caps != null) {
      final success = await _apiService!.applyClientSpeedLimits(
        ip,
        token,
        useHttps,
        limits: allLimits,
        capabilities: caps,
        context: context,
      );

      if (!success) {
        return false;
      }
    }

    await _persistSpeedLimitsForRouter(rKey);
    notifyListeners();
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchThrottledClients({
    String? routerId,
  }) async {
    final rKey = _getEffectiveSpeedLimitRouterKey(routerId);
    if (!_speedLimitsByRouter.containsKey(rKey)) {
      await loadSpeedLimitsForRouter(rKey);
    }

    final activeLimits = getActiveSpeedLimitsForRouter(routerId: rKey);
    if (activeLimits.isEmpty) return [];

    List<Client> currentClients = [];
    try {
      currentClients = await fetchClientsForSelectedRouter();
    } catch (_) {
      currentClients = List<Client>.from(clients);
    }

    final clientByMac = <String, Client>{};
    for (final c in currentClients) {
      clientByMac[ClientNamingHelper.normalizeMac(c.macAddress)] = c;
    }

    final result = <Map<String, dynamic>>[];
    for (final limit in activeLimits) {
      final mac = ClientNamingHelper.normalizeMac(limit.targetMac);
      final client = clientByMac[mac];
      result.add({
        'limit': limit,
        'client': client,
        'targetMac': mac,
        'displayName': client?.displayName ?? limit.hostname ?? mac,
        'ipAddress': client?.ipAddress ?? limit.ipAddress,
        'isConnected': client?.isConnected ?? false,
        'connectionType': client?.connectionType ?? ConnectionType.unknown,
      });
    }

    return result;
  }

  Future<bool> updateWiredInterfaceStatus(
    String interfaceName,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateWiredInterfaceStatus(
    interfaceName,
    enabled,
    context: context,
  );

  Future<bool> updateWirelessInterfaceStatus(
    String sectionKey,
    bool enabled, {
    BuildContext? context,
  }) => _networkActionsController!.updateWirelessInterfaceStatus(
    sectionKey,
    enabled,
    context: context,
  );

  Future<bool> restartWiredInterface(
    String interfaceName, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final ip = _authService!.ipAddress!;
      final sysauth = _authService!.sysauth!;
      final useHttps = _authService!.useHttps;
      final ctx = (context != null && context.mounted) ? context : null;

      bool success = false;

      try {
        final downRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/ifdown',
            'params': [interfaceName],
          },
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        await Future.delayed(const Duration(milliseconds: 400));
        final upRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {
            'command': '/sbin/ifup',
            'params': [interfaceName],
          },
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(upRes) ||
            _apiService!.execSucceeded(downRes)) {
          success = true;
        }
      } catch (_) {}

      if (!success) {
        try {
          final downRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.interface.$interfaceName',
            method: 'down',
            params: {},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 400));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.interface.$interfaceName',
            method: 'up',
            params: {},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if ((downRes is List && downRes.isNotEmpty && downRes[0] == 0) ||
              (upRes is List && upRes.isNotEmpty && upRes[0] == 0)) {
            success = true;
          }
        } catch (_) {}
      }

      if (!success) {
        final execRes = await _apiService!.systemExec(
          ip,
          sysauth,
          useHttps,
          command:
              'ifdown $interfaceName 2>/dev/null; sleep 1; ifup $interfaceName 2>/dev/null',
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(execRes)) {
          success = true;
        }
      }

      return success;
    } catch (e, stack) {
      Logger.exception(
        'restartWiredInterface failed for $interfaceName',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> restartWirelessInterface(
    String sectionKey, {
    String? radioName,
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      return true;
    }
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final ip = _authService!.ipAddress!;
      final sysauth = _authService!.sysauth!;
      final useHttps = _authService!.useHttps;
      final ctx = (context != null && context.mounted) ? context : null;

      bool success = false;

      final wifiReloadArgs = (radioName != null && radioName.isNotEmpty)
          ? ['reload', radioName]
          : ['reload'];
      try {
        final reloadRes = await _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'file',
          method: 'exec',
          params: {'command': '/sbin/wifi', 'params': wifiReloadArgs},
          context: ctx,
        );
        if (_apiService!.execSucceeded(reloadRes)) {
          success = true;
        }
      } catch (e) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains('socket') ||
            errStr.contains('connection reset') ||
            errStr.contains('broken pipe') ||
            errStr.contains('connection closed') ||
            errStr.contains('clientexception')) {
          success = true;
        }
      }

      if (!success) {
        final wifiDownArgs = (radioName != null && radioName.isNotEmpty)
            ? ['down', radioName]
            : ['down'];
        final wifiUpArgs = (radioName != null && radioName.isNotEmpty)
            ? ['up', radioName]
            : ['up'];
        try {
          await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/wifi', 'params': wifiDownArgs},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 500));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'file',
            method: 'exec',
            params: {'command': '/sbin/wifi', 'params': wifiUpArgs},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if (_apiService!.execSucceeded(upRes)) {
            success = true;
          }
        } catch (_) {}
      }

      if (!success && radioName != null && radioName.isNotEmpty) {
        try {
          final downRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.wireless',
            method: 'down',
            params: {'device': radioName},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          await Future.delayed(const Duration(milliseconds: 400));
          final upRes = await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: 'network.wireless',
            method: 'up',
            params: {'device': radioName},
            context: (ctx != null && ctx.mounted) ? ctx : null,
          );
          if ((downRes is List && downRes.isNotEmpty && downRes[0] == 0) ||
              (upRes is List && upRes.isNotEmpty && upRes[0] == 0)) {
            success = true;
          }
        } catch (_) {}
      }

      if (!success) {
        final rName = (radioName != null && radioName.isNotEmpty)
            ? radioName
            : '';
        final cmd = rName.isNotEmpty
            ? 'wifi reload $rName 2>/dev/null || (wifi down $rName 2>/dev/null; sleep 1; wifi up $rName 2>/dev/null) || wifi reload'
            : 'wifi reload 2>/dev/null || (wifi down 2>/dev/null; sleep 1; wifi up 2>/dev/null)';

        final execRes = await _apiService!.systemExec(
          ip,
          sysauth,
          useHttps,
          command: cmd,
          context: (ctx != null && ctx.mounted) ? ctx : null,
        );
        if (_apiService!.execSucceeded(execRes)) {
          success = true;
        }
      }

      return success;
    } catch (e, stack) {
      Logger.exception(
        'restartWirelessInterface failed for $sectionKey',
        e,
        stack,
      );
      return false;
    }
  }

  Future<bool> setWirelessRadioState(
    String device,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: device,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );

      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );

      await _apiService!.systemExec(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        command: 'wifi reload',
        context: context?.mounted == true ? context : null,
      );

      await fetchDashboardData();

      return true;
    } catch (e) {
      _errorMessage = 'Failed to toggle Wi-Fi: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchWirelessSectionConfig(
    String sectionName,
  ) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return null;
    }
    try {
      final rawRpc = await _apiService!.call(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless', 'section': sectionName},
      );
      if (rawRpc is List && rawRpc.length > 1 && rawRpc[0] == 0) {
        final values = rawRpc[1];
        if (values is Map<String, dynamic>) {
          final valuesMap = values['values'] ?? values;
          if (valuesMap is Map) {
            return Map<String, dynamic>.from(valuesMap);
          }
        }
      }
    } catch (e) {
      Logger.debug(
        'fetchWirelessSectionConfig failed for section $sectionName: $e',
      );
    }
    return null;
  }

  Future<int> migrateAnonymousWirelessSections() async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return 0;
    }
    return _apiService!.migrateAnonymousWirelessSections(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
    );
  }

  Future<Map<String, List<Map<String, String>>>>
  fetchWirelessHardwareCapabilities({
    required String sectionName,
    String? radioName,
    BuildContext? context,
  }) async {
    if (reviewerModeEnabled ||
        _apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return _fallbackHardwareCapabilities();
    }

    return _apiService!.fetchWirelessHardwareCapabilities(
      sectionName: sectionName,
      radioName: radioName,
      ipAddress: _authService!.ipAddress!,
      sysauth: _authService!.sysauth!,
      useHttps: _authService!.useHttps,
      context: context,
    );
  }

  Future<Map<String, dynamic>> fetchWirelessRadioCapabilities({
    required String radioName,
    BuildContext? context,
  }) async {
    if (_apiService == null ||
        _authService?.sysauth == null ||
        _authService?.ipAddress == null) {
      return {};
    }

    return _apiService!.fetchWirelessRadioCapabilities(
      radioName: radioName,
      ipAddress: _authService!.ipAddress!,
      sysauth: _authService!.sysauth!,
      useHttps: _authService!.useHttps,
      context: context,
    );
  }

  Map<String, List<Map<String, String>>> _fallbackHardwareCapabilities() {
    return {'encryptions': fallbackEncryptions, 'ciphers': fallbackCiphers};
  }

  List<Map<String, String>> get fallbackEncryptions => [
    {'value': 'sae', 'label': 'WPA3-SAE (Personal / Strict)'},
    {'value': 'sae-mixed', 'label': 'WPA2/WPA3 Mixed (Transitional)'},
    {'value': 'psk2', 'label': 'WPA2-PSK (CCMP / AES)'},
    {'value': 'psk', 'label': 'WPA-PSK (Legacy / WPA1)'},
    {'value': 'owe', 'label': 'Enhanced Open (OWE)'},
    {'value': 'none', 'label': 'Open / No Encryption'},
  ];

  List<Map<String, String>> get fallbackCiphers => [
    {'value': 'auto', 'label': 'Auto (Hardware Default)'},
    {'value': 'ccmp', 'label': 'CCMP (AES)'},
    {'value': 'gcmp256', 'label': 'GCMP-256 (High Security)'},
    {'value': 'gcmp128', 'label': 'GCMP-128'},
    {'value': 'tkip', 'label': 'TKIP (Legacy)'},
  ];

  Future<bool> tryAutoLogin({
    bool force = false,
    bool fetchDashboard = true,
    BuildContext? context,
  }) => _sessionController!.tryAutoLogin(
    force: force,
    fetchDashboard: fetchDashboard,
    context: context,
  );

  Future<void> handleAppResume() async {
    await _sessionController?.handleAppResume();
    if (!reviewerModeEnabled && selectedRouter != null) {
      unawaited(fetchPublicIps());
      unawaited(refreshInstalledFeatures());
    }
  }

  Future<void> refreshInstalledFeatures() async {
    await _dashboardController?.refreshInstalledFeatures();
  }

  Future<void> refreshDynamicColors() async {
    await _sessionController?.refreshDynamicColors();
  }

  Future<Set<String>> fetchAllAssociatedWirelessMacs() async {
    if (reviewerModeEnabled) {
      final stationsMap = await _apiService!.fetchAssociatedStations();
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    } else {
      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return {};
      }

      final ip = _routerService!.selectedRouter!.ipAddress;
      final useHttps = _routerService!.selectedRouter!.useHttps;

      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
          );
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });

      final wirelessConfig =
          dashboardData?['uciWirelessConfig'] ?? dashboardData?['wireless'];
      if (wirelessConfig is Map<String, dynamic>) {
        wirelessConfig.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            final maclist = v['maclist'] ?? v['config']?['maclist'];
            if (maclist is List) {
              for (final item in maclist) {
                if (item != null && item.toString().isNotEmpty) {
                  macs.add(item.toString().toLowerCase());
                }
              }
            }
          }
        });
      }

      return macs;
    }
  }

  @override
  void dispose() {
    if (identical(this, _instance)) {
      return;
    }
    _throughputController?.dispose();
    _networkActionsController?.dispose();
    _accessControlTimerLifecycleManager?.dispose();
    _throughputTimer?.cancel();
    _pollingTimer?.cancel();
    _pollAttempts = 0;
    _isRebooting = false;
    super.dispose();
  }

  Future<List<Client>> fetchAggregatedClients({
    void Function(List<Client> clients)? onIncrementalUpdate,
  }) async {
    if (!_isActiveSessionDataReady) {
      await ensureActiveSessionDataReady();
    }
    return _clientController?.fetchAggregatedClients(
          onIncrementalUpdate: onIncrementalUpdate,
        ) ??
        Future.value(<Client>[]);
  }

  bool get isClientsLoading => _clientController?.isFetchingClients ?? false;
  bool get hasFetchedClients => _clientController?.hasFetchedClients ?? false;

  bool get hasDumbAp =>
      (_clientController?.hasDumbAp ?? false) ||
      clients.any((c) => c.isDumbApClient) ||
      routers.length > 1;

  List<Client> get dumbApClients =>
      clients.where((c) => c.isDumbApClient).toList();

  int get dumbApClientsCount => dumbApClients.length;

  Future<List<Client>> fetchClientsForSelectedRouter() =>
      _clientController!.fetchClientsForSelectedRouter();

  @visibleForTesting
  set clientControllerForTesting(ClientController? controller) {
    _clientController = controller;
  }

  @visibleForTesting
  ClientController? get clientControllerForTesting => _clientController;

  set clients(List<Client> clientList) {
    _clientController?.lastFetchedClients = clientList;
  }

  List<Client> get clients {
    if (_clientController?.lastFetchedClients != null &&
        _clientController!.lastFetchedClients!.isNotEmpty) {
      return _clientController!.lastFetchedClients!;
    }

    final clientList = <Client>[];
    final data = dashboardData;
    final rawHostHints = data?['hostHints'];
    final hostHints = rawHostHints is Map
        ? Map<String, dynamic>.from(rawHostHints)
        : const <String, dynamic>{};

    dynamic rawLeases =
        data?['dhcpLeases'] ?? data?['dhcp_leases'] ?? data?['leases'];
    if (rawLeases is Map && rawLeases['dhcp_leases'] is List) {
      rawLeases = rawLeases['dhcp_leases'];
    }

    final rawStations = data?['wirelessStations'];
    final wirelessStations = rawStations is Map
        ? Map<String, dynamic>.from(rawStations)
        : const <String, dynamic>{};
    final associated = <String>{};
    wirelessStations.forEach((iface, list) {
      if (list is List) {
        for (final item in list) {
          if (item is Map && item['mac'] != null) {
            associated.add(
              item['mac'].toString().toUpperCase().replaceAll('-', ':'),
            );
          } else if (item is String) {
            associated.add(item.toUpperCase().replaceAll('-', ':'));
          }
        }
      }
    });
    final wirelessMacs = <String>{
      ...(_clientController?.knownWirelessMacs.keys ?? {}),
      ...associated,
    };

    if (rawLeases is List) {
      for (final l in rawLeases) {
        if (l is Map) {
          final c = Client.fromLease(l.cast<String, dynamic>());
          final normMac = c.macAddress.toUpperCase().replaceAll('-', ':');
          final isWireless = wirelessMacs.contains(normMac);
          final hint = hostHints[normMac];
          final staticName = hint?['staticLeaseName']?.toString();
          final isStatic = hint?['isStaticLease'] == true;

          clientList.add(
            c.copyWith(
              connectionType: isWireless
                  ? ConnectionType.wireless
                  : (c.connectionType == ConnectionType.unknown
                        ? ConnectionType.wired
                        : c.connectionType),
              isConnected: associated.contains(normMac),
              staticLeaseName: staticName,
              isStaticLease: isStatic,
            ),
          );
        }
      }
    }

    hostHints.forEach((mac, info) {
      final normMac = mac.toUpperCase().replaceAll('-', ':');
      if (!clientList.any(
        (c) => c.macAddress.toUpperCase().replaceAll('-', ':') == normMac,
      )) {
        final hintName =
            info['name']?.toString() ??
            info['staticLeaseName']?.toString() ??
            normMac;
        final ipaddrs = info['ipaddrs'] as List?;
        final ip = (ipaddrs != null && ipaddrs.isNotEmpty)
            ? ipaddrs.first.toString()
            : (info['staticLeaseIp']?.toString() ?? 'N/A');
        final isStatic = info['isStaticLease'] == true;
        final isWireless = wirelessMacs.contains(normMac);
        clientList.add(
          Client(
            ipAddress: ip,
            macAddress: normMac,
            hostname: hintName,
            isConnected: associated.contains(normMac),
            connectionType: isWireless
                ? ConnectionType.wireless
                : ConnectionType.unknown,
            isStaticLease: isStatic,
            staticLeaseName: info['staticLeaseName']?.toString(),
          ),
        );
      }
    });

    return clientList;
  }

  Client? findClientByMac(String macAddress) {
    if (macAddress.trim().isEmpty) return null;
    final norm = macAddress
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');
    for (final c in clients) {
      final cNorm = c.macAddress
          .toUpperCase()
          .replaceAll('-', ':')
          .split(':')
          .map((b) => b.length == 1 ? '0$b' : b)
          .join(':');
      if (cNorm == norm) return c;
    }
    return null;
  }

  Map<String, dynamic>? _lastDashboardDataForStaticLeases;
  Map<String, DhcpStaticMapping>? _cachedStaticMappingsByMac;
  Set<String>? _cachedStaticLeaseMacs;

  void _ensureStaticLeasesCache() {
    final currentData = dashboardData;
    if (_cachedStaticMappingsByMac != null &&
        identical(_lastDashboardDataForStaticLeases, currentData)) {
      return;
    }
    _lastDashboardDataForStaticLeases = currentData;
    final mappingMap = <String, DhcpStaticMapping>{};
    final macSet = <String>{};

    if (currentData != null) {
      final dhcpOverview = DhcpDnsOverview.fromDashboardData(
        currentData,
        isReviewerMode: reviewerModeEnabled,
      );
      for (final mapping in dhcpOverview.staticMappings) {
        final macs = mapping.macAddress
            .toUpperCase()
            .replaceAll('-', ':')
            .split(',')
            .map((m) => m.trim())
            .map(
              (b) => b
                  .split(':')
                  .map((part) => part.length == 1 ? '0$part' : part)
                  .join(':'),
            );
        for (final m in macs) {
          if (m.isNotEmpty) {
            mappingMap[m] = mapping;
            macSet.add(m);
          }
        }
      }
    }
    _cachedStaticMappingsByMac = mappingMap;
    _cachedStaticLeaseMacs = macSet;
  }

  void invalidateStaticLeasesCache() {
    _cachedStaticMappingsByMac = null;
    _cachedStaticLeaseMacs = null;
    _lastDashboardDataForStaticLeases = null;
    notifyListenersDeferrable();
  }

  Set<String> get configuredStaticLeaseMacs {
    _ensureStaticLeasesCache();
    return _cachedStaticLeaseMacs ?? const {};
  }

  DhcpStaticMapping? findStaticLeaseByMac(String macAddress) {
    if (macAddress.trim().isEmpty) return null;
    final normMac = macAddress
        .toUpperCase()
        .replaceAll('-', ':')
        .split(':')
        .map((b) => b.length == 1 ? '0$b' : b)
        .join(':');

    _ensureStaticLeasesCache();
    return _cachedStaticMappingsByMac?[normMac];
  }

  Future<Set<String>> fetchAllAssociatedWirelessMacsAggregated() =>
      _clientController!.fetchAllAssociatedWirelessMacsAggregated();

  Future<List<Map<String, dynamic>>> fetchAggregatedDhcpLeases() =>
      _clientController!.fetchAggregatedDhcpLeases();

  Future<bool> toggleOpenVpnInstance(String name, bool enable) =>
      _networkActionsController!.toggleOpenVpnInstance(name, enable);

  Future<bool> toggleTailscale(bool enable) =>
      _networkActionsController!.toggleTailscale(enable);

  Future<bool> toggleNextDns(bool enable) =>
      _networkActionsController!.toggleNextDns(enable);

  Future<bool> toggleCloudflared(bool enable) =>
      _networkActionsController!.toggleCloudflared(enable);

  Future<bool> toggleWireguardInterface(String ifaceName, bool bringUp) =>
      _networkActionsController!.toggleWireguardInterface(ifaceName, bringUp);

  Future<bool> restartVpnService(String serviceName) =>
      _networkActionsController!.restartVpnService(serviceName);

  String? get pendingSectionName =>
      _networkActionsController?.pendingSectionName;
  String? get pendingTargetType => _networkActionsController?.pendingTargetType;
  dynamic get pendingTargetRadio =>
      _networkActionsController?.pendingTargetRadio;
  dynamic get pendingTargetInterface =>
      _networkActionsController?.pendingTargetInterface;

  Future<bool> applyWirelessInterfaceConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    List<String>? deleteOptions,
    dynamic targetRadio,
    dynamic targetInterface,
    BuildContext? context,
  }) => _networkActionsController!.applyWirelessInterfaceConfig(
    sectionName: sectionName,
    newValues: newValues,
    priorValuesSnapshot: priorValuesSnapshot,
    deleteOptions: deleteOptions,
    targetRadio: targetRadio,
    targetInterface: targetInterface,
    context: context,
  );

  Future<bool> applyWirelessRadioConfig({
    required String sectionName,
    required Map<String, String> newValues,
    required Map<String, String> priorValuesSnapshot,
    List<String>? deleteOptions,
    dynamic targetRadio,
    BuildContext? context,
  }) => _networkActionsController!.applyWirelessRadioConfig(
    sectionName: sectionName,
    newValues: newValues,
    priorValuesSnapshot: priorValuesSnapshot,
    deleteOptions: deleteOptions,
    targetRadio: targetRadio,
    context: context,
  );

  Future<bool> addWirelessInterface({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    required String network,
    Map<String, String>? extraOptions,
    BuildContext? context,
  }) => _networkActionsController!.addWirelessInterface(
    radioName: radioName,
    ssid: ssid,
    encryption: encryption,
    key: key,
    network: network,
    extraOptions: extraOptions,
    context: context,
  );

  Future<bool> deleteWirelessInterface({
    required String sectionName,
    BuildContext? context,
  }) => _networkActionsController!.deleteWirelessInterface(
    sectionName: sectionName,
    context: context,
  );

  Future<bool> updateInterfaceDhcpConfig({
    required String interface,
    required Map<String, dynamic> values,
    BuildContext? context,
  }) => _networkActionsController!.updateInterfaceDhcpConfig(
    interface: interface,
    values: values,
    context: context,
  );

  Future<bool> provisionGuestNetwork({
    required String radioName,
    required String ssid,
    required String encryption,
    required String key,
    String guestIp = '192.168.2.1',
    bool isolateClients = true,
    String network = 'guest',
    String? country,
    String? channel,
    String? htMode,
    String? txPower,
    bool ieee80211r = false,
    bool ftOverDs = false,
    bool ftPskGenerateLocal = false,
    String? mobilityDomain,
    bool wmm = true,
    bool hidden = false,
    int? dtimPeriod,
    int? gtkRekey,
    int? inactivityLimit,
    int? maxListenInterval,
    bool disassocLowAck = true,
    bool multicastToUnicast = false,
    bool wds = false,
    String? macfilter,
    List<String>? maclist,
    BuildContext? context,
  }) => _networkActionsController!.provisionGuestNetwork(
    radioName: radioName,
    ssid: ssid,
    encryption: encryption,
    key: key,
    guestIp: guestIp,
    isolateClients: isolateClients,
    network: network,
    country: country,
    channel: channel,
    htMode: htMode,
    txPower: txPower,
    ieee80211r: ieee80211r,
    ftOverDs: ftOverDs,
    ftPskGenerateLocal: ftPskGenerateLocal,
    mobilityDomain: mobilityDomain,
    wmm: wmm,
    hidden: hidden,
    dtimPeriod: dtimPeriod,
    gtkRekey: gtkRekey,
    inactivityLimit: inactivityLimit,
    maxListenInterval: maxListenInterval,
    disassocLowAck: disassocLowAck,
    multicastToUnicast: multicastToUnicast,
    wds: wds,
    macfilter: macfilter,
    maclist: maclist,
    context: context,
  );

  Future<List<String>> fetchNetworkInterfaces({BuildContext? context}) =>
      _networkActionsController!.fetchNetworkInterfaces(context: context);

  String get sessionUsername =>
      _routerService?.selectedRouter?.username ?? 'root';

  bool get isAdministrativeUser {
    final caps = capabilities;
    if (caps != null) {
      return caps.hasUciWriteAccess;
    }
    final user = sessionUsername.trim().toLowerCase();
    return user == 'root' || user == 'admin' || user.isNotEmpty;
  }
}

String normalizeMac(String mac) => mac
    .trim()
    .toUpperCase()
    .replaceAll('-', ':')
    .split(':')
    .map((b) => b.length == 1 ? '0$b' : b)
    .join(':');

Set<String> recentFdbMacs(String out, {int maxIdle = 60}) {
  final mac = RegExp(r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})');
  final used = RegExp(r'used (\d+)/');
  final macs = <String>{};
  for (final line in out.split('\n')) {
    final lower = line.toLowerCase();
    if (lower.contains('self') || lower.contains('permanent')) continue;
    final m = mac.firstMatch(line);
    if (m == null) continue;
    final parts = line.trim().split(RegExp(r'\s+'));
    final brctl = parts.length == 4 && (parts[2] == 'yes' || parts[2] == 'no');
    if (brctl && parts[2] == 'yes') continue;
    final idle =
        int.tryParse(used.firstMatch(line)?.group(1) ?? '') ??
        (brctl ? double.tryParse(parts[3])?.floor() : null);
    if (idle != null && idle > maxIdle) continue;
    macs.add(normalizeMac(m.group(0)!));
  }
  return macs;
}

const Duration kNeighborProbeInterval = Duration(seconds: 30);

const int kNeighborProbeMaxBatch = 10;

List<String> selectNeighborProbeTargets(
  List<Map<String, dynamic>> dhcp4Leases,
  Set<String> normalizedWireless,
  List<Map<String, dynamic>> neighClients, {
  String routerIp = '',
  int maxBatch = kNeighborProbeMaxBatch,
}) {
  String normMac(String mac) => normalizeMac(mac);

  final normWireless = normalizedWireless.map(normMac).toSet();

  final candidateIps = <String>{};
  for (final l in dhcp4Leases) {
    final macRaw = l['macaddr']?.toString() ?? l['mac']?.toString() ?? '';
    final ipRaw = l['ipaddr']?.toString() ?? l['ip']?.toString() ?? '';
    final macN = normMac(macRaw);
    if (macN.isNotEmpty &&
        !normWireless.contains(macN) &&
        ipRaw.isNotEmpty &&
        ipRaw != 'N/A' &&
        ipRaw != routerIp) {
      candidateIps.add(ipRaw);
    }
  }

  final missingWiredIps = candidateIps.where((ip) {
    final Map<String, dynamic>? entry = neighClients
        .cast<Map<String, dynamic>?>()
        .firstWhere((n) => n?['ipaddr'] == ip, orElse: () => null);
    if (entry == null) return true;
    final nud = (entry['nud_state']?.toString() ?? '').toUpperCase();
    return nud == 'INCOMPLETE' || nud == 'FAILED';
  }).toList();

  return missingWiredIps.take(maxBatch).toList();
}
