import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/screens/network/network_screen.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/core/luci_module.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/noobwrt/addons/addons.dart';
import 'package:yet_another_luci_app/modules/noobwrt/addons/addons_screen.dart';
import 'package:yet_another_luci_app/screens/routers/routers_sheet.dart';
import 'package:yet_another_luci_app/screens/more/about_screen.dart';
import 'package:yet_another_luci_app/screens/more/appearance_view.dart';
import 'package:yet_another_luci_app/screens/more/customise_home_screen.dart';
import 'package:yet_another_luci_app/services/app_update.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:yet_another_luci_app/screens/more/more_view.dart';
import 'package:yet_another_luci_app/screens/router/router_screen.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_help_screen.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/screens/speed/speed_screen.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/widgets/change_router_password_dialog.dart';

bool isInstalledFeature(LuciModule m) =>
    m.id.startsWith('noobwrt_') ||
    m.requiredUbus.isNotEmpty ||
    m.requiredConfigs.isNotEmpty;

class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ValueListenableBuilder<AppUpdate?>(
        valueListenable: AppUpdateChecker.instance.available,
        builder: (context, update, _) => ValueListenableBuilder(
          valueListenable: addonUpdates,
          builder: (context, _, _) => _build(context, ref, update),
        ),
      );

  Widget _build(BuildContext context, WidgetRef ref, AppUpdate? update) {
    final app = ref.watch(appStateProvider);
    final modules =
        LuciModuleRegistry.instance
            .enabledModulesFor(app.capabilities)
            .where((m) => !m.showInBottomNav)
            .toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    void open(Widget Function(BuildContext) b) =>
        Navigator.of(context).push(MaterialPageRoute(builder: b));
    MoreItem module(LuciModule m) => MoreItem(
      m.icon,
      m.name,
      m.description,
      () => open((c) => m.buildScreen(c)),
    );
    final addons = addonUpdatesFor(app.selectedRouter?.id);
    final name = routerDisplayName(app.selectedRouter);
    final reviewer = app.reviewerModeEnabled;
    final canChangePassword = app.capabilities?.hasSetPasswordRpc ?? false;

    Future<void> signOut() async {
      final ks = context.ks;
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: ks.sheet,
          title: Text(
            reviewer ? 'Leave the demo?' : 'Sign out?',
            style: KeystoneType.sheetTitle(ks.tx),
          ),
          content: Text(
            reviewer
                ? 'The demo data goes away and you sign in to a real router.'
                : 'Keystone forgets this session. The router keeps running.',
            style: KeystoneType.body(ks.tx2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                reviewer ? 'Leave' : 'Sign out',
                style: TextStyle(color: ks.bad),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (reviewer) {
        await app.setReviewerMode(false);
      } else {
        await app.logout();
        await HttpClientManager().clearAcceptedCertificates();
      }
      if (context.mounted) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }

    return MoreView(
      signOutLabel: reviewer ? 'Leave the demo' : 'Sign out',
      onSignOut: signOut,
      routerName: name,
      onRouterMenu: () => showRoutersSheet(context),
      sections: [
        (
          'On this router',
          [for (final m in modules.where(isInstalledFeature)) module(m)],
        ),
        (
          'Router settings',
          [
            MoreItem(
              Icons.router_outlined,
              'Your router',
              'Lights, health, storage, logs, restart',
              () => open((_) => const RouterScreen()),
            ),
            MoreItem(
              Icons.speed_rounded,
              'Speed test',
              'Test your internet from the router',
              () => open((_) => const SpeedScreen()),
            ),
            if (canChangePassword)
              MoreItem(
                Icons.lock_outline_rounded,
                'Router password',
                'The one you use to sign in',
                () => ChangeRouterPasswordDialog.show(context),
              ),
            MoreItem(
              Icons.hub_outlined,
              'Network',
              'Internet and home network connections',
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const NetworkScreen())),
            ),
            for (final m in modules.where((m) => !isInstalledFeature(m)))
              module(m),
          ],
        ),
        (
          'Keystone',
          [
            MoreItem(
              Icons.swap_horiz_rounded,
              'Routers',
              'Switch, add or edit routers',
              () => showRoutersSheet(context),
            ),
            MoreItem(
              Icons.palette_outlined,
              'Customise',
              'Theme, font and Home',
              () => open((_) => const CustomiseScreen()),
            ),
            MoreItem(
              Icons.extension_outlined,
              'Add-ons',
              addonsLine(addons),
              () => open((_) => AddonsScreen(app: app)),
              highlight: addons > 0,
            ),
            MoreItem(
              Icons.help_outline_rounded,
              'Help',
              'Common fixes and what everything means',
              () => open(
                (_) => SignInHelpScreen(
                  routerLabel: name == 'Your router' ? 'router' : name,
                  address: app.currentRouterIp ?? '192.168.1.1',
                ),
              ),
            ),
            MoreItem(
              Icons.info_outline_rounded,
              'About and licences',
              'Version, credits, GPL-3.0',
              () => open((_) => const AboutScreen()),
            ),
            MoreItem(
              Icons.system_update_outlined,
              'Check for updates',
              update == null
                  ? 'Looks for a newer Keystone on GitHub'
                  : 'Keystone ${update.version} is out',
              () => checkForUpdate(context),
              highlight: update != null,
            ),
          ],
        ),
      ],
    );
  }
}

class CustomiseScreen extends StatelessWidget {
  const CustomiseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget page) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return KsPage(
      title: 'Customise',
      back: 'More',
      children: [
        KsRow(
          leading: const Icon(Icons.contrast_rounded),
          title: 'Appearance',
          subtitle: 'Theme and font',
          onTap: () => open(const AppearanceScreen()),
        ),
        KsRow(
          leading: const Icon(Icons.home_outlined),
          title: 'Home',
          subtitle: 'Layout, devices shown and sections',
          onTap: () => open(const CustomiseHomeScreen()),
        ),
      ],
    );
  }
}

class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Customise', style: KeystoneType.body(ks.mu)),
      ),
      body: AppearanceView(themeMode: app.themeMode, onTheme: app.setThemeMode),
    );
  }
}

Future<void> checkForUpdate(BuildContext context) async {
  ksSay(context, 'Checking for updates…');
  AppUpdate? u;
  try {
    u = await AppUpdateChecker.instance.check();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ksSay(context, "Couldn't reach GitHub. Check this phone's internet.");
    }
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  if (u == null) {
    ksSay(context, 'You have the latest Keystone.');
    return;
  }
  final update = u;
  final apk = canSelfUpdate
      ? pickApk(update.apks, await deviceAbis().catchError((_) => <String>[]))
      : null;
  if (!context.mounted) return;
  final get = await ksConfirm(
    context,
    title: 'Keystone ${update.version} is out',
    body: [
      if (update.notes case final n? when n.isNotEmpty)
        n.length > 400 ? '${n.substring(0, 400)}…' : n,
      apk != null
          ? 'Keystone downloads it and Android asks you to install it. '
                'Your routers and settings stay.'
          : 'Download the APK from the release page and install it over this '
                'one. Your routers and settings stay.',
    ].join('\n\n'),
    action: apk != null ? 'Download and install' : 'Open the release',
  );
  if (!get || !context.mounted) return;
  if (apk == null || !await _downloadAndInstall(context, apk)) {
    await launchUrlString(update.url, mode: LaunchMode.externalApplication);
  }
}

/// False when it failed and the release page should open instead.
Future<bool> _downloadAndInstall(BuildContext context, UpdateApk apk) async {
  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  final ks = context.ks;
  final nav = Navigator.of(context);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text('Downloading', style: KeystoneType.sheetTitle(ks.tx)),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: p > 0 ? p : null),
              const SizedBox(height: 12),
              Text(
                '${(p * apk.size / 1048576).toStringAsFixed(1)} of '
                '${(apk.size / 1048576).toStringAsFixed(1)} MB',
                style: KeystoneType.body(ks.tx2),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(c);
            },
            child: Text('Cancel', style: KeystoneType.body(ks.tx)),
          ),
        ],
      ),
    ),
  );
  try {
    final file = await downloadApk(
      apk,
      (p) => progress.value = p,
      () => cancelled,
    );
    if (cancelled || file == null) return true;
    nav.pop();
    await installApk(file, apk.sha256);
    return true;
  } catch (e) {
    if (!cancelled) nav.pop();
    if (context.mounted) {
      ksSay(
        context,
        e is PlatformException && e.code == 'BAD_HASH'
            ? 'The download was damaged. Opening the release page instead.'
            : "Couldn't download the update. Opening the release page instead.",
      );
    }
    return false;
  } finally {
    progress.dispose();
  }
}
