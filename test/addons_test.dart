// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/modules/noobwrt/addons/addons.dart';
import 'package:yet_another_luci_app/modules/noobwrt/addons/experimental.dart';
import 'package:yet_another_luci_app/modules/noobwrt/addons/addons_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_installer.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_sheet.dart';
import 'package:yet_another_luci_app/services/app_update.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _App extends Fake implements AppState {
  _App([this.id = 'r1']);
  final String id;
  @override
  model.Router? get selectedRouter => model.Router(
    id: id,
    ipAddress: '192.168.1.1',
    username: 'root',
    password: '',
    useHttps: false,
  );
  @override
  bool get reviewerModeEnabled => false;
}

HelperRelease _rel(String v) =>
    HelperRelease(version: v, ipkUrl: 'https://x/a.ipk', apkUrl: 'https://x/a');

class _Helper extends Fake implements HelperInstaller {
  _Helper(this.have, this.latest, {this.offline = false});
  String? have;
  final String? latest;
  final bool offline;
  int back = 0;

  @override
  Future<String?> installed() async => have;
  @override
  Future<HelperRelease?> latestRelease() async => offline
      ? throw Exception('no net')
      : (latest == null ? null : _rel(latest!));
  @override
  Future<HelperRelease?> stableRelease() async => _rel('0.2.0');
  @override
  Future<InstallState> status() async => const InstallState(InstallPhase.idle);
  @override
  Future<Map<String, dynamic>?> info() async => null;
  @override
  Future<void> goBack() async {
    back++;
    have = '0.2.0';
  }
}

Future<void> _show(WidgetTester t, Widget w) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      home: Scaffold(body: w),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    addonUpdates.value = null;
  });

  test('app update picks the APK for the phone, else the universal one', () {
    UpdateApk a(String abi) => UpdateApk(
      name: 'keystone-v1.0.2-$abi.apk',
      url: 'https://x/$abi',
      size: 1,
    );
    final all = [a('armeabi-v7a'), a('arm64-v8a'), a('universal')];
    expect(pickApk(all, ['arm64-v8a', 'armeabi-v7a'])!.name, contains('arm64'));
    expect(pickApk(all, ['armeabi-v7a'])!.name, contains('armeabi-v7a'));
    expect(pickApk(all, ['riscv64'])!.name, contains('universal'));
    expect(pickApk([a('x86_64')], ['arm64-v8a']), isNull);
  });

  test('test versions sort below their stable version', () {
    expect(isNewerVersion('0.3.0', '0.3.0_beta1'), isTrue);
    expect(isNewerVersion('0.3.0_beta1', '0.3.0'), isFalse);
    expect(isNewerVersion('0.3.0-beta.1', '0.2.0'), isTrue);
    expect(isNewerVersion('0.3.0_beta10', '0.3.0_beta2'), isTrue);
    expect(isNewerVersion('0.3.0_rc1', '0.3.0_beta9'), isTrue);
    expect(isNewerVersion('0.3.0_beta1', '0.3.0_beta1'), isFalse);
    expect(isNewerVersion('1.0.0-r2', '1.0.0'), isFalse);
    expect(isPreRelease('0.3.0_beta1'), isTrue);
    expect(isPreRelease('0.3.0'), isFalse);
  });

  Map<String, dynamic> gh(String v, {bool draft = false}) => {
    'draft': draft,
    'assets': [
      {'browser_download_url': 'https://gh/keystone-history-$v.apk'},
      {'browser_download_url': 'https://gh/keystone-history_${v}_all.ipk'},
    ],
  };

  test('newest release is picked by version, not order', () {
    final r = newestRelease([
      gh('0.2.0'),
      gh('0.3.0_beta1'),
      gh('0.9.0', draft: true),
      gh('0.1.0'),
    ], 'keystone-history')!;
    expect(r.version, '0.3.0_beta1');
    expect(r.apkUrl, endsWith('0.3.0_beta1.apk'));
    expect(r.ipkUrl, endsWith('0.3.0_beta1_all.ipk'));
    expect(
      newestRelease([
        gh('0.3.0_beta1'),
        gh('0.3.0'),
      ], 'keystone-history')!.version,
      '0.3.0',
    );
    expect(newestRelease('nope', 'keystone-history'), isNull);
  });

  Addon add(String name, _Helper h) =>
      Addon(name: name, about: 'About', helper: h, open: showHelperSheet);

  Future<void> screen(WidgetTester t, List<Addon> addons) async {
    await t.pumpWidget(const SizedBox());
    await _show(t, AddonsScreen(app: _App(), addons: addons));
  }

  testWidgets('updates show under each name and are counted', (t) async {
    await screen(t, [
      add('One', _Helper('0.1.0', '0.2.0')),
      add('Two', _Helper('0.2.0', '0.2.0')),
      add('Three', _Helper('0.2.0', '0.3.0_beta1')),
      add('Four', _Helper(null, '0.2.0')),
    ]);
    expect(find.text('Update available · 0.1.0 → 0.2.0'), findsOneWidget);
    expect(find.text('Installed 0.2.0'), findsOneWidget);
    expect(
      find.text('Beta update available · 0.2.0 → 0.3.0_beta1'),
      findsOneWidget,
    );
    expect(find.text('About · Not installed'), findsOneWidget);
    expect(addonUpdatesFor('r1'), 2);
    expect(addonUpdatesFor('r2'), 0);
    expect(addonsLine(3), '3 updates available');
    expect(addonsLine(1), '1 update available');
  });

  testWidgets('unreleased add-ons stay hidden', (t) async {
    await screen(t, [add('Soon', _Helper(null, null))]);
    expect(find.text('Soon'), findsNothing);
    expect(find.text('No add-ons yet.'), findsOneWidget);
  });

  testWidgets('offline keeps the list and the last count', (t) async {
    addonUpdates.value = ('r1', 3);
    await screen(t, [add('One', _Helper('0.2.0', null, offline: true))]);
    expect(find.textContaining("couldn't check"), findsOneWidget);
    expect(addonUpdatesFor('r1'), 3);
  });

  test('another router does not clear the count', () {
    addonUpdates.value = ('r1', 2);
    noteAddons('r2', const [AddonStatus(have: '1.0.0')]);
    expect(addonUpdatesFor('r1'), 2);
    noteAddons('r1', const [AddonStatus(have: '1.0.0')]);
    expect(addonUpdatesFor('r1'), 0);
  });

  test('background check runs once per router', () async {
    final one = [add('One', _Helper('0.1.0', '0.2.0'))];
    await checkAddons(_App('bg'), addons: one);
    expect(addonUpdatesFor('bg'), 1);
    addonUpdates.value = null;
    await checkAddons(_App('bg'), addons: one);
    expect(addonUpdatesFor('bg'), 0);
  });

  testWidgets('going back to stable from a test version', (t) async {
    final h = _Helper('0.3.0_beta1', '0.3.0_beta1');
    await _show(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => showHelperSheet(c, h),
          child: const Text('open'),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Version 0.3.0_beta1 (beta)'), findsOneWidget);
    await t.tap(find.text('Go back to stable 0.2.0'));
    await t.pumpAndSettle();
    await t.tap(find.text('Go back'));
    await t.pumpAndSettle();
    expect(h.back, 1);
    expect(find.text('Version 0.2.0'), findsOneWidget);
    expect(find.textContaining('Go back to stable'), findsNothing);
  });

  testWidgets('betas need agreement and turns off freely', (t) async {
    await _show(
      t,
      AddonsScreen(
        app: _App(),
        addons: [add('One', _Helper('0.2.0', '0.2.0'))],
      ),
    );
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(await loadExperimental(), isFalse);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('I understand, show betas'));
    await t.pumpAndSettle();
    expect(await loadExperimental(), isTrue);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(await loadExperimental(), isFalse);
  });
}
