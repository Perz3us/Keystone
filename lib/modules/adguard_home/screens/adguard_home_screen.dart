// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import '../controllers/adguard_controller.dart';
import '../models/adguard_models.dart';
import '../utils/adguard_web_url_helper.dart';
import '../widgets/adguard_credentials_dialog.dart';
import '../widgets/adguard_custom_rules_dialog.dart';
import '../widgets/adguard_filter_lists_dialog.dart';
import '../widgets/adguard_pause_dialog.dart';
import '../widgets/adguard_profile_dialog.dart';
import '../widgets/adguard_top_lists_bottom_sheet.dart';
import '../widgets/configure_router_dns_dialog.dart';
import '../widgets/revert_router_dns_dialog.dart';

class AdGuardHomeScreen extends ConsumerStatefulWidget {
  final String? routerId;

  const AdGuardHomeScreen({super.key, this.routerId});

  @override
  ConsumerState<AdGuardHomeScreen> createState() => _AdGuardHomeScreenState();
}

String adguardStateLine(AdGuardState s) {
  if (s.isDiscoveryFailed) return 'Keystone can\'t reach AdGuard Home.';
  final st = s.status;
  if (st == null) return 'Checking AdGuard Home…';
  if (!st.running) return 'AdGuard Home is stopped, so nothing is blocked.';
  switch (st.protectionState) {
    case AdGuardProtectionState.paused:
      final m = (st.pauseDurationMs / 60000).ceil();
      return 'Paused. Blocking starts again in $m min.';
    case AdGuardProtectionState.disabled:
      return 'Ad blocking is off.';
    case AdGuardProtectionState.enabled:
      final stats = s.stats;
      if (stats == null || stats.numDnsQueries == 0) {
        return 'Blocking ads and trackers on every device.';
      }
      return 'Blocking ads and trackers. '
          '${stats.blockRatePercentage.toStringAsFixed(0)}% of lookups '
          'were blocked.';
  }
}

String _count(int n) => n >= 10000
    ? '${(n / 1000).toStringAsFixed(0)}k'
    : n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => ',');

class _AdGuardHomeScreenState extends ConsumerState<AdGuardHomeScreen> {
  AdGuardController? _controller;

  String get _routerId =>
      widget.routerId ??
      ref.read(appStateProvider).selectedRouter?.id ??
      'default';

  void _start() {
    final c = ref.read(adguardControllerProvider(_routerId).notifier);
    _controller = c;
    c.loadProfiles();
    c.startPolling();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  @override
  void didUpdateWidget(covariant AdGuardHomeScreen old) {
    super.didUpdateWidget(old);
    if (old.routerId != widget.routerId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller?.stopPolling(updateState: false);
        _start();
      });
    }
  }

  @override
  void dispose() {
    _controller?.stopPolling(updateState: false);
    super.dispose();
  }

  Future<void> _pickInstance(AdGuardState s, AdGuardController c) async {
    final ks = context.ks;
    await ksSheet<void>(
      context,
      (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Which AdGuard Home', style: KeystoneType.sheetTitle(ks.tx)),
          const SizedBox(height: 8),
          for (final p in s.profiles)
            KsRow(
              key: Key('agh_profile_item_${p.id}'),
              title: p.name,
              subtitle: p.type == AdGuardInstanceType.externalHost
                  ? '${p.host}:${p.port}'
                  : 'On this router',
              trailing: s.activeProfile?.id == p.id
                  ? Icon(Icons.check_rounded, color: ks.ac)
                  : null,
              chevron: false,
              onTap: () {
                Navigator.pop(sheet);
                c.selectProfile(p);
              },
            ),
          KsRow(
            key: const Key('agh_add_external_profile_button'),
            title: 'Add one on another device',
            onTap: () {
              Navigator.pop(sheet);
              AdGuardProfileDialog.show(context, controller: c);
            },
          ),
          if (s.isExternal && s.activeProfile != null) ...[
            KsRow(
              key: const Key('agh_edit_active_profile_button'),
              title: 'Edit ${s.activeProfile!.name}',
              onTap: () {
                Navigator.pop(sheet);
                AdGuardProfileDialog.show(
                  context,
                  controller: c,
                  initialProfile: s.activeProfile,
                );
              },
            ),
            KsRow(
              key: const Key('agh_delete_active_profile_button'),
              title: 'Remove ${s.activeProfile!.name}',
              danger: true,
              chevron: false,
              onTap: () async {
                Navigator.pop(sheet);
                final p = s.activeProfile!;
                final go = await ksConfirm(
                  context,
                  title: 'Remove ${p.name}?',
                  body: 'Keystone forgets this AdGuard Home and its password.',
                  action: 'Remove',
                  danger: true,
                );
                if (!go) return;
                try {
                  await c.deleteExternalProfile(p.id);
                } catch (_) {
                  if (mounted) {
                    ksSay(context, 'Couldn\'t remove it. Try again.');
                  }
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _protection(AdGuardController c, bool on) async {
    if (on) {
      await c.setProtection(enabled: true);
      return;
    }
    final d = await AdGuardPauseDialog.show(context);
    if (d == null) return;
    await c.setProtection(
      enabled: false,
      duration: d == Duration.zero ? null : d,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final s = ref.watch(adguardControllerProvider(_routerId));
    final c = ref.read(adguardControllerProvider(_routerId).notifier);
    _controller = c;

    final host = s.isExternal
        ? (s.activeProfile?.host ?? '127.0.0.1')
        : (app.selectedRouter?.ipAddress ?? '192.168.1.1');
    final https = s.isExternal
        ? (s.activeProfile?.useHttps ?? false)
        : (app.selectedRouter?.useHttps ?? false);
    final port = s.isExternal
        ? (s.activeProfile?.port ?? 3000)
        : (s.status?.httpPort ?? s.capabilities.discoveredHttpPort);

    final st = s.status;
    final stats = s.stats;
    final f = s.filtering;
    final topo = s.topology;
    final forwarded =
        (topo.routingStatus ==
            AdGuardDnsRoutingStatus.routerForwardingVerified ||
        topo.routingStatus == AdGuardDnsRoutingStatus.clientUsageVerified);
    final err = switch (s.connectionStatus) {
      AdGuardConnectionStatus.invalidEndpoint =>
        'Something else answers on that port, not AdGuard Home.',
      AdGuardConnectionStatus.apiUnreachable =>
        'AdGuard Home isn\'t answering. Pull down to try again.',
      AdGuardConnectionStatus.degraded =>
        'Some numbers couldn\'t be read this time.',
      _ => s.generalError,
    };

    return KsPage(
      title: 'Ad blocking',
      subtitle: s.isInitialLoading
          ? 'Checking AdGuard Home…'
          : adguardStateLine(s),
      onRefresh: c.refresh,
      actions: [
        if (s.profiles.length > 1 || s.isExternal)
          TextButton(
            key: const Key('agh_profile_selector_button'),
            onPressed: () => _pickInstance(s, c),
            child: Text(
              s.activeProfile?.name ?? 'Switch',
              style: KeystoneType.body(ks.mu),
            ),
          ),
      ],
      children: [
        if (s.isInitialLoading)
          const Padding(
            key: Key('agh_initial_loading_view'),
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LinearProgressIndicator(),
          )
        else if (s.isDiscoveryFailed) ...[
          Text(
            s.isExternal
                ? 'Check the address and that the other device is on.'
                : 'Keystone works with AdGuard Home that is already set '
                      'up on the router. Make sure its service is running, '
                      'or add one that runs on another device.',
            key: const Key('agh_discovery_error_view'),
            style: KeystoneType.body(ks.tx2),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('agh_error_retry_button'),
            onPressed: c.refresh,
            child: const Text('Try again'),
          ),
          if (!s.isExternal)
            TextButton(
              key: const Key('agh_configure_external_button'),
              onPressed: () =>
                  AdGuardProfileDialog.show(context, controller: c),
              child: const Text('Add one on another device'),
            ),
        ] else ...[
          if (s.connectionStatus == AdGuardConnectionStatus.authRequired)
            KsNote(
              'AdGuard Home needs its own sign-in to show numbers and '
              'change settings.',
              key: const Key('agh_auth_required_banner'),
              action: 'Sign in',
              onAction: () =>
                  AdGuardCredentialsDialog.show(context, controller: c),
            )
          else if (err != null)
            KsBanner(
              err,
              bad: true,
              key: const Key('agh_general_error_banner'),
            ),
          if (s.isExternal)
            const KsNote(
              'This AdGuard Home runs on another device. Devices only use '
              'it if the router or the devices point to it.',
              key: Key('agh_external_topology_disclaimer'),
            ),
          if (st != null && st.running)
            KsSwitchRow(
              key: const Key('agh_protection_toggle_switch'),
              title: 'Block ads and trackers',
              subtitle: st.protectionState == AdGuardProtectionState.enabled
                  ? 'Turn off to pause it'
                  : null,
              value: st.protectionState == AdGuardProtectionState.enabled,
              busy: s.isMutatingProtection,
              onChanged: s.isMutatingProtection
                  ? null
                  : (on) => _protection(c, on),
            ),
          if (s.protectionActionError != null)
            KsBanner(
              s.protectionActionError!,
              bad: true,
              key: const Key('agh_protection_error_banner'),
            ),

          if (stats != null) ...[
            KsSection(
              'Lookups',
              trailing: TextButton(
                key: const Key('agh_stats_period_button'),
                onPressed: () => ksSheet<void>(
                  context,
                  (sheet) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (p, l) in const [
                        (AdGuardStatsPeriod.hours24, 'Last 24 hours'),
                        (AdGuardStatsPeriod.days7, 'Last 7 days'),
                        (AdGuardStatsPeriod.days30, 'Last 30 days'),
                        (AdGuardStatsPeriod.all, 'Everything kept'),
                      ])
                        KsRow(
                          title: l,
                          chevron: false,
                          trailing: s.statsPeriod == p
                              ? Icon(Icons.check_rounded, color: ks.ac)
                              : null,
                          onTap: () {
                            Navigator.pop(sheet);
                            c.setStatsPeriod(p);
                          },
                        ),
                    ],
                  ),
                ),
                child: Text(switch (s.statsPeriod) {
                  AdGuardStatsPeriod.hours24 => '24 hours',
                  AdGuardStatsPeriod.days7 => '7 days',
                  AdGuardStatsPeriod.days30 => '30 days',
                  AdGuardStatsPeriod.all => 'All',
                }),
              ),
            ),
            Text(
              '${_count(stats.numDnsQueries)} lookups, '
              '${_count(stats.numBlockedFiltering)} blocked, '
              '${stats.avgProcessingTime.toStringAsFixed(0)} ms each',
              style: KeystoneType.body(
                ks.tx,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (stats.topBlockedDomains.isNotEmpty)
              KsRow(
                key: const Key('agh_top_blocked_view_all_button'),
                title: 'Most blocked',
                subtitle: stats.topBlockedDomains
                    .take(2)
                    .map((e) => e.identifier)
                    .join(', '),
                onTap: () => AdGuardTopListsBottomSheet.show(
                  context,
                  stats: stats,
                  initialTabIndex: 1,
                ),
              ),
            if (stats.topClients.isNotEmpty)
              KsRow(
                title: 'Busiest devices',
                subtitle: stats.topClients
                    .take(2)
                    .map((e) => e.identifier)
                    .join(', '),
                onTap: () => AdGuardTopListsBottomSheet.show(
                  context,
                  stats: stats,
                  initialTabIndex: 2,
                ),
              ),
          ] else if (s.statsError != null)
            KsBanner(s.statsError!),

          const KsSection('What it blocks'),
          KsRow(
            key: const Key('agh_filtering_card'),
            title: 'Block lists',
            subtitle: f == null
                ? (s.filteringError ?? 'Reading…')
                : '${f.filterLists.where((l) => l.enabled).length} on, '
                      '${_count(f.totalRulesCount)} rules',
            onTap: () => AdGuardFilterListsDialog.show(context, controller: c),
          ),
          KsRow(
            key: const Key('agh_manage_user_rules_button'),
            title: 'Your own rules',
            subtitle: f == null || f.userRules.isEmpty
                ? 'Block or allow single sites'
                : '${f.userRules.length} rules',
            onTap: () => AdGuardCustomRulesDialog.show(
              context,
              controller: c,
              initialRules: f?.userRules,
            ),
          ),

          if (!s.isExternal) ...[
            const KsSection('Router'),
            KsRow(
              key: const Key('agh_configure_router_dns_btn'),
              title: forwarded
                  ? 'Every device uses it'
                  : 'Point the router at it',
              subtitle: forwarded
                  ? 'The router sends all lookups to AdGuard Home'
                  : 'Some devices may skip AdGuard Home',
              onTap: () => ConfigureRouterDnsDialog.show(
                context,
                controller: c,
                routerId: _routerId,
              ),
            ),
            if (forwarded || topo.forwarders.isNotEmpty)
              KsRow(
                key: const Key('agh_revert_router_dns_btn'),
                title: 'Stop sending lookups to it',
                danger: true,
                chevron: false,
                onTap: () => RevertRouterDnsDialog.show(
                  context,
                  controller: c,
                  routerId: _routerId,
                ),
              ),
          ],

          if (!s.isExternal && st != null) ...[
            const KsSection('Service'),
            Text(
              [
                st.running ? 'Running' : 'Stopped',
                if (st.version.isNotEmpty) st.version,
                if (s.processTelemetry?.estimatedRamMb != null)
                  '${s.processTelemetry!.estimatedRamMb!.toStringAsFixed(0)} MB memory',
              ].join(', '),
              style: KeystoneType.secondary(ks.mu),
            ),
          ],
          if (!s.isExternal && s.capabilities.isServiceManageable) ...[
            KsSwitchRow(
              title: 'Start with the router',
              value: s.capabilities.isServiceEnabled ?? false,
              onChanged: s.isManagingService ? null : c.setServiceAutostart,
            ),
            if (st?.running ?? false) ...[
              KsRow(
                title: 'Restart',
                chevron: false,
                onTap: s.isManagingService ? null : c.restartService,
              ),
              KsRow(
                key: const Key('agh_service_stop_button'),
                title: 'Stop',
                danger: true,
                chevron: false,
                onTap: s.isManagingService ? null : c.stopService,
              ),
            ] else
              KsRow(
                title: 'Start',
                chevron: false,
                onTap: s.isManagingService ? null : c.startService,
              ),
            if (s.serviceActionError != null)
              KsBanner(
                s.serviceActionError!,
                bad: true,
                key: const Key('agh_service_error_banner'),
              ),
          ],

          const KsSection('More'),
          KsRow(
            key: const Key('agh_appbar_web_ui_button'),
            title: 'Open AdGuard Home in the browser',
            onTap: () => AdGuardWebUrlHelper.launchWebInterface(
              context: context,
              isReviewerMode: app.reviewerModeEnabled,
              host: host,
              port: port,
              useHttps: https,
            ),
          ),
          KsChoice<AdGuardPollingInterval>(
            label: 'Update the numbers',
            value: s.pollingInterval,
            options: const [
              (AdGuardPollingInterval.off, 'Never'),
              (AdGuardPollingInterval.s5, 'Every 5 seconds'),
              (AdGuardPollingInterval.s10, 'Every 10 seconds'),
              (AdGuardPollingInterval.s30, 'Every 30 seconds'),
              (AdGuardPollingInterval.manual, 'Only when I pull down'),
            ],
            onChanged: c.setPollingInterval,
          ),
          if (s.profiles.length <= 1 && !s.isExternal)
            KsRow(
              key: const Key('agh_add_external_profile_button'),
              title: 'Use one on another device',
              onTap: () => AdGuardProfileDialog.show(context, controller: c),
            ),
        ],
      ],
    );
  }
}
