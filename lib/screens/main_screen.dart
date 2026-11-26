// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/background/notifier.dart';
import 'package:yet_another_luci_app/modules/noobwrt/alerts/alerts_screen.dart';
import 'package:yet_another_luci_app/utils/error_words.dart';
import 'package:yet_another_luci_app/modules/noobwrt/addons/addons.dart';
import 'package:yet_another_luci_app/services/app_update.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/home/home_tab.dart';
import 'package:yet_another_luci_app/screens/devices/devices_tab.dart';
import 'package:yet_another_luci_app/screens/more/more_tab.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_tab.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/widgets/scroll_jitter_guard.dart';
import 'package:yet_another_luci_app/design/breakpoints.dart';
import 'package:yet_another_luci_app/utils/gateway_utils.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/utils/os_platform_integration.dart';
import 'package:yet_another_luci_app/l10n/app_localizations.dart';

class MainScreen extends ConsumerStatefulWidget {
  final int? initialTab;
  const MainScreen({super.key, this.initialTab});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final Set<int> _activatedTabs = {0};
  final List<int> _tabHistory = [0];
  bool _isRedirectingToLogin = false;

  late final PageController _pages = PageController(
    initialPage: _dockTabs.contains(_selectedIndex)
        ? _dockTabs.indexOf(_selectedIndex)
        : 0,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdateChecker.instance.checkDaily();
    alertTaps.addListener(_openAlerts);
    if (alertTaps.value > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openAlerts());
    }
    if (widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
    }
    _activatedTabs.add(_selectedIndex);
    _tabHistory.clear();
    _tabHistory.add(_selectedIndex);
    if (_selectedIndex != 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(appStateProvider).setDashboardTabActive(false);
        }
      });
    }
  }

  AppState? _appState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newAppState = ref.read(appStateProvider);
    if (_appState != newAppState) {
      _appState?.removeRouterBackOnlineListener(_handleRouterBackOnline);
      _appState = newAppState;
      _appState?.addRouterBackOnlineListener(_handleRouterBackOnline);
    }
  }

  void _openAlerts() {
    if (!mounted || ref.read(appStateProvider).reviewerModeEnabled) return;
    openAlerts(context, ref.read(appStateProvider));
  }

  @override
  void dispose() {
    alertTaps.removeListener(_openAlerts);
    _appState?.removeRouterBackOnlineListener(_handleRouterBackOnline);
    WidgetsBinding.instance.removeObserver(this);
    _appState?.pauseThroughputTimer();
    _pages.dispose();
    super.dispose();
  }

  void _handleRouterBackOnline(bool success) {
    if (!mounted) return;
    if (success) {
      ksSay(context, 'The router is back. Reconnecting…');
    } else {
      ksSay(context, 'The router hasn\'t come back yet. Check it has power.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final appState = ref.read(appStateProvider);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      appState.pauseThroughputTimer();
    } else if (state == AppLifecycleState.resumed) {
      appState.handleAppResume();
      if (_selectedIndex == 0) {
        appState.resumeThroughputTimer(immediateTick: true);
      } else {
        appState.setDashboardTabActive(false);
      }
    }
  }

  @override
  void didUpdateWidget(MainScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _selectedIndex = widget.initialTab!.clamp(0, 4);
      _activatedTabs.add(_selectedIndex);
      _tabHistory.remove(_selectedIndex);
      _tabHistory.add(_selectedIndex);
    }
  }

  void _syncPage() {
    final page = _dockTabs.indexOf(_selectedIndex);
    if (page < 0 || !_pages.hasClients) return;
    final at = _pages.page;
    if (at == null || (at - page).abs() < 0.01) return;
    if ((at - page).abs() > 1.01 || MediaQuery.of(context).disableAnimations) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(
        page,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _onPageChanged(int page) {
    final index = _dockTabs[page];
    if (index == _selectedIndex) return;
    _onItemTapped(index);
  }

  void _onItemTapped(int index) {
    FocusScope.of(context).unfocus();
    final safeIndex = index.clamp(0, 4);
    if (_selectedIndex == safeIndex) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _selectedIndex = safeIndex;
      _activatedTabs.add(safeIndex);
      _tabHistory.remove(safeIndex);
      _tabHistory.add(safeIndex);
    });

    ref.read(appStateProvider).setDashboardTabActive(safeIndex == 0);
  }

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        icon: Icon(
          Icons.exit_to_app_rounded,
          color: colorScheme.primary,
          size: 28,
        ),
        title: Text(
          l10n?.exitDialogTitle ?? 'Exit Keystone?',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            l10n?.exitDialogMessage ??
                'Are you sure you want to exit the application?',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.actionExit ?? 'Exit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);

    if (appState.hasActiveSession) {
      _isRedirectingToLogin = false;
      unawaited(checkAddons(appState));
    } else if (!appState.isLoading && !_isRedirectingToLogin) {
      _isRedirectingToLogin = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted &&
            !ref.read(appStateProvider).hasActiveSession &&
            !ref.read(appStateProvider).isLoading) {
          final creds = await SecureStorageService().getCredentials();
          final detectedGateway = await GatewayUtils.detectGatewayIp();

          if (!mounted) return;
          final currentState = ref.read(appStateProvider);
          if (currentState.hasActiveSession || currentState.isLoading) {
            _isRedirectingToLogin = false;
            return;
          }

          final effectiveIp =
              (creds['ipAddress'] != null && creds['ipAddress']!.isNotEmpty)
              ? creds['ipAddress']
              : detectedGateway;

          if (!mounted || !context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => SignInScreen(
                initialIp: effectiveIp,
                initialUsername: creds['username'],
                initialPassword: creds['password'],
              ),
            ),
            (route) => false,
          );
        } else {
          _isRedirectingToLogin = false;
        }
      });
    }

    if (appState.requestedTab != null &&
        appState.requestedTab != _selectedIndex) {
      final safeRequestedTab = appState.requestedTab!.clamp(0, 4);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).unfocus();
        setState(() {
          _selectedIndex = safeRequestedTab;
          _activatedTabs.add(safeRequestedTab);
          _tabHistory.remove(safeRequestedTab);
          _tabHistory.add(safeRequestedTab);
        });
        ref.read(appStateProvider).setDashboardTabActive(safeRequestedTab == 0);
        appState.requestedTab = null;
      });
    }

    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAndShowReviewerNotice();
      });
    }

    final isRebooting = appState.isRebooting;
    final connectionStatus = appState.connectionStatus;
    final colorScheme = Theme.of(context).colorScheme;
    final isTablet = KsBreakpoints.isTablet(context);
    final l10n = AppLocalizations.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPage();
    });
    Widget tab(int index) {
      _activatedTabs.add(index);
      return switch (index) {
        0 => HomeTab(isTabActive: _selectedIndex == 0),
        2 => DevicesTab(isTabActive: _selectedIndex == 2),
        3 => WifiTab(isTabActive: _selectedIndex == 3),
        _ => const MoreTab(),
      };
    }

    final body = ScrollJitterGuard(
      child: PageView.builder(
        controller: _pages,
        itemCount: _dockTabs.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (_, page) => _KeepTab(child: tab(_dockTabs[page])),
      ),
    );

    final showConnectivityBanner =
        connectionStatus != RouterConnectionStatus.connected && !isRebooting;

    final topOffset = MediaQuery.paddingOf(context).top + kToolbarHeight;

    final contentWithBanner = Stack(
      children: [
        Positioned.fill(child: body),
        Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: !showConnectivityBanner,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              offset: showConnectivityBanner
                  ? Offset.zero
                  : const Offset(0, -0.6),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                opacity: showConnectivityBanner ? 1.0 : 0.0,
                child: showConnectivityBanner
                    ? _buildConnectivityBanner(
                        context,
                        connectionStatus,
                        isDynamic: appState.useDynamicTheme,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_tabHistory.length > 1) {
          setState(() {
            _tabHistory.removeLast();
            final previousTab = _tabHistory.last;
            _selectedIndex = previousTab;
          });
          ref.read(appStateProvider).setDashboardTabActive(_selectedIndex == 0);
          return;
        } else if (_selectedIndex != 0) {
          setState(() {
            _selectedIndex = 0;
            _tabHistory.clear();
            _tabHistory.add(0);
          });
          ref.read(appStateProvider).setDashboardTabActive(true);
          return;
        }

        final shouldExit = await _showExitConfirmationDialog(context);
        if (shouldExit == true && context.mounted) {
          await OsPlatformIntegration.exitApp(context: context);
        }
      },
      child: isTablet
          ? Scaffold(
              body: Row(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            selectedIndex: _dockTabs.contains(_selectedIndex)
                                ? _dockTabs.indexOf(_selectedIndex)
                                : null,
                            onDestinationSelected: isRebooting
                                ? null
                                : (i) => _onItemTapped(_dockTabs[i]),
                            labelType: NavigationRailLabelType.all,
                            useIndicator: true,
                            indicatorColor: colorScheme.primaryContainer,
                            selectedIconTheme: IconThemeData(
                              color: colorScheme.onPrimaryContainer,
                            ),
                            unselectedIconTheme: IconThemeData(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            selectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                            unselectedLabelTextStyle: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            backgroundColor: colorScheme.surfaceContainer,
                            destinations: [
                              NavigationRailDestination(
                                icon: const Icon(
                                  Icons.space_dashboard_outlined,
                                ),
                                selectedIcon: const Icon(
                                  Icons.space_dashboard_rounded,
                                ),
                                label: Text(l10n?.navDashboard ?? 'Home'),
                              ),
                              NavigationRailDestination(
                                icon: _countBadge(
                                  appState,
                                  Icons.devices_other_outlined,
                                ),
                                selectedIcon: _countBadge(
                                  appState,
                                  Icons.devices_other_rounded,
                                ),
                                label: Text(l10n?.navClients ?? 'Devices'),
                              ),
                              NavigationRailDestination(
                                icon: const Icon(Icons.wifi_outlined),
                                selectedIcon: const Icon(Icons.wifi),
                                label: Text(l10n?.navWireless ?? 'Wi-Fi'),
                              ),
                              NavigationRailDestination(
                                icon: _updateDot(
                                  const Icon(Icons.grid_view_outlined),
                                ),
                                selectedIcon: _updateDot(
                                  const Icon(Icons.grid_view_rounded),
                                ),
                                label: Text(l10n?.navMore ?? 'More'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                  Expanded(child: contentWithBanner),
                ],
              ),
            )
          : Scaffold(
              body: contentWithBanner,
              bottomNavigationBar: _buildDock(appState, isRebooting, l10n),
            ),
    );
  }

  Widget _countBadge(AppState app, IconData icon) {
    final n = app.clients.where((c) => c.isConnected).length;
    return Badge(
      isLabelVisible: n > 0,
      label: Text(n > 99 ? '99+' : '$n'),
      child: Icon(icon),
    );
  }

  Widget _updateDot(Widget icon) => ListenableBuilder(
    listenable: Listenable.merge([
      AppUpdateChecker.instance.available,
      addonUpdates,
    ]),
    builder: (context, child) => Badge(
      isLabelVisible:
          AppUpdateChecker.instance.available.value != null ||
          addonUpdatesFor(_appState?.selectedRouter?.id) > 0,
      smallSize: 7,
      backgroundColor: context.ks.ac,
      child: child,
    ),
    child: icon,
  );

  static const _dockTabs = [0, 2, 3, 4];

  Widget _buildDock(
    AppState appState,
    bool isRebooting,
    AppLocalizations? l10n,
  ) {
    final ks = context.ks;
    final items = [
      (
        0,
        l10n?.navDashboard ?? 'Home',
        Icons.home_outlined,
        Icons.home_rounded,
      ),
      (
        2,
        l10n?.navClients ?? 'Devices',
        Icons.devices_outlined,
        Icons.devices_rounded,
      ),
      (3, l10n?.navWireless ?? 'Wi-Fi', Icons.wifi_rounded, Icons.wifi_rounded),
      (
        4,
        l10n?.navMore ?? 'More',
        Icons.grid_view_outlined,
        Icons.grid_view_rounded,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ks.bg,
        border: Border(top: BorderSide(color: ks.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              for (final (i, (index, label, icon, selectedIcon))
                  in items.indexed)
                _dockItem(
                  index: index,
                  position: i + 1,
                  label: label,
                  icon: icon,
                  selectedIcon: selectedIcon,
                  disabled: isRebooting && index != 4,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dockItem({
    required int index,
    required int position,
    required String label,
    required IconData icon,
    required IconData selectedIcon,
    required bool disabled,
  }) {
    final ks = context.ks;
    final selected = _selectedIndex == index;
    final color = disabled
        ? ks.mu.withValues(alpha: 0.5)
        : (selected ? ks.tx : ks.mu);

    return Expanded(
      child: Semantics(
        selected: selected,
        button: true,
        label: '$label, tab $position of 4',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : () => _onItemTapped(index),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: const Cubic(0.25, 1, 0.5, 1),
                  width: 52,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? ks.acSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: index == 4
                      ? _updateDot(
                          Icon(
                            selected ? selectedIcon : icon,
                            color: color,
                            size: 20,
                          ),
                        )
                      : Icon(
                          selected ? selectedIcon : icon,
                          color: color,
                          size: 20,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KeystoneType.caption(color).copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _checkAndShowReviewerNotice() {
    if (!mounted) return;
    final appState = ref.read(appStateProvider);
    if (appState.reviewerModeEnabled &&
        !appState.hasShownReviewerNotice &&
        !appState.isDashboardLoading &&
        appState.dashboardData != null) {
      appState.markReviewerNoticeShown();
      _showReviewerInfoDialog(context);
    }
  }

  void _showReviewerInfoDialog(BuildContext context) =>
      ksSay(context, 'This is the demo. Leave it from More.');

  Widget _buildConnectivityBanner(
    BuildContext context,
    RouterConnectionStatus status, {
    bool isDynamic = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isReconnecting = status == RouterConnectionStatus.reconnecting;

    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color accentColor;

    if (isReconnecting) {
      if (isDynamic) {
        bgColor = colorScheme.primaryContainer.withValues(
          alpha: isDark ? 0.90 : 0.95,
        );
        borderColor = colorScheme.primary.withValues(alpha: 0.35);
        textColor = colorScheme.onPrimaryContainer;
        accentColor = colorScheme.primary;
      } else {
        bgColor = colorScheme.tertiaryContainer.withValues(
          alpha: isDark ? 0.90 : 0.95,
        );
        borderColor = colorScheme.tertiary.withValues(alpha: 0.35);
        textColor = colorScheme.onTertiaryContainer;
        accentColor = colorScheme.tertiary;
      }
    } else {
      bgColor = isDark && isDynamic
          ? Color.alphaBlend(
              colorScheme.error.withValues(alpha: 0.20),
              colorScheme.surfaceContainerHigh,
            ).withValues(alpha: 0.95)
          : colorScheme.errorContainer.withValues(alpha: isDark ? 0.90 : 0.95);
      borderColor = colorScheme.error.withValues(alpha: 0.35);
      textColor = colorScheme.onErrorContainer;
      accentColor = colorScheme.error;
    }

    final label = isReconnecting
        ? 'Reconnecting to router...'
        : 'Router disconnected';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 7.0,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: borderColor, width: 1.0),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isReconnecting
                        ? Icons.sync_rounded
                        : Icons.wifi_off_rounded,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isReconnecting) ...[
                    const SizedBox(width: 10),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          if (ActionRateLimiter.isRateLimited(
                            'retry_connection',
                            cooldown: const Duration(seconds: 1),
                          )) {
                            return;
                          }
                          ref
                              .read(appStateProvider)
                              .fetchDashboardData(force: true);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9.0,
                            vertical: 3.5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surface.withValues(
                              alpha: isDark ? 0.35 : 0.85,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outline.withValues(
                                alpha: 0.30,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                size: 13,
                                color: textColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Retry',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepTab extends StatefulWidget {
  const _KeepTab({required this.child});
  final Widget child;

  @override
  State<_KeepTab> createState() => _KeepTabState();
}

class _KeepTabState extends State<_KeepTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
