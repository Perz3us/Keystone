// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_installer.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/helper_sheet.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_data.dart';
import 'package:yet_another_luci_app/modules/noobwrt/history/history_screen.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

class _FakeApp extends Fake implements AppState {}

class _Installer extends Fake implements HelperInstaller {
  _Installer({
    this.have,
    this.rel = const HelperRelease(
      version: '0.1.0',
      ipkUrl: 'https://x/a.ipk',
      apkUrl: 'https://x/a.apk',
    ),
    this.offline = false,
    this.state = const InstallState(InstallPhase.idle),
    this.statusError,
  });
  String? have;
  HelperRelease? rel;
  bool offline;
  InstallState state;
  Object? statusError;
  Map<String, dynamic>? infoMap;
  Object? keepError;
  Future<void>? infoGate;
  int infoCalls = 0;
  final kept = <int>[];
  Completer<void>? job;
  Object? jobError;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>?> info() async {
    infoCalls++;
    await infoGate;
    return infoMap;
  }

  @override
  Future<void> setKeep(int days) async {
    if (keepError != null) throw keepError!;
    kept.add(days);
  }

  @override
  Future<String?> installed() async => have;

  @override
  Future<HelperRelease?> latestRelease() async {
    if (offline) throw Exception('no net');
    return rel;
  }

  @override
  Future<InstallState> status() async {
    if (statusError != null) throw statusError!;
    return state;
  }

  Future<void> _job(String op) async {
    calls.add(op);
    final was = state;
    if (was.phase == InstallPhase.done) {
      state = const InstallState(InstallPhase.idle);
      if (was.code != 0) throw NoobRpcError(was.log);
      have = op == 'install' ? rel?.version : null;
      return;
    }
    job = Completer<void>();
    await job!.future;
    state = const InstallState(InstallPhase.idle);
    if (jobError != null) throw jobError!;
    have = op == 'install' ? rel?.version : null;
  }

  @override
  Future<void> install() => _job('install');

  @override
  Future<void> remove() => _job('remove');
}

class _Src implements HistorySource {
  _Src(this.d, {this.error});
  final HistoryData? d;
  final Object? error;
  int loads = 0;
  @override
  Future<HistoryData?> load(DateTime from, DateTime to) async {
    loads++;
    if (error != null) throw error!;
    return d;
  }
}

const _body =
    'Adds a small background service to the router that keeps 7 days of '
    'signal, line ping and data history. About 4 KB. You can remove it here '
    'any time.';

Future<void> _open(
  WidgetTester t,
  _Installer h, {
  bool settle = true,
  AddonText text = signalHistoryText,
  List<(String, HelperInstaller)> dependents = const [],
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                showHelperSheet(c, h, text: text, dependents: dependents),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  settle ? await t.pumpAndSettle() : await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

void main() {
  testWidgets('not installed offers Install', (t) async {
    await _open(t, _Installer());
    expect(find.text('Signal history'), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(_button('Install'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets('installing shows progress, then says it worked', (t) async {
    final h = _Installer();
    await _open(t, h);
    await t.tap(_button('Install'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Installing'), findsOneWidget);
    expect(_button('Install'), findsNothing);
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Signal history installed.'), findsOneWidget);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('a failed install shows the router words', (t) async {
    final h = _Installer()..jobError = const NoobRpcError('bad package');
    await _open(t, h);
    await t.tap(_button('Install'));
    await t.pump();
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('bad package'), findsOneWidget);
    expect(_button('Install'), findsOneWidget);
  });

  testWidgets('any other failure is said in plain words', (t) async {
    final h = _Installer()..jobError = TimeoutException('slow');
    await _open(t, h);
    await t.tap(_button('Install'));
    await t.pump();
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the router"), findsOneWidget);
    expect(find.textContaining('TimeoutException'), findsNothing);
  });

  testWidgets('installed and up to date shows the version and a red Remove', (
    t,
  ) async {
    final h = _Installer(have: '0.1.0');
    await _open(t, h);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    final remove = t.widget<Text>(find.text('Remove'));
    final ctx = t.element(find.text('Remove'));
    expect(remove.style?.color, ctx.ks.bad);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.text('Remove signal history?'), findsOneWidget);
    expect(
      find.text('History older than the last router restart will be lost.'),
      findsOneWidget,
    );
    await t.tap(find.text('Remove').last);
    await t.pump();
    expect(h.calls, ['remove']);
    expect(find.textContaining('Removing'), findsOneWidget);
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Signal history removed.'), findsOneWidget);
    expect(_button('Install'), findsOneWidget);
  });

  testWidgets('another add-on uses its own words and has no retention', (
    t,
  ) async {
    final h = _Installer(have: '0.1.0')..infoMap = {'keep_days': 7};
    await _open(t, h, text: alertsText);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text(alertsText.about), findsOneWidget);
    expect(find.text('Keep history for'), findsNothing);
    expect(h.infoCalls, 0);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(find.text('Remove alerts?'), findsOneWidget);
    await t.tap(find.text('Remove').last);
    await t.pump();
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Alerts removed.'), findsOneWidget);
  });

  testWidgets('signal history stays while another add-on needs it', (t) async {
    final h = _Installer(have: '0.3.0');
    await _open(
      t,
      h,
      dependents: [
        ('Alerts', _Installer(have: '0.1.0')),
        ('Data per device', _Installer()),
      ],
    );
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    expect(
      find.text('Remove Alerts first. It needs signal history.'),
      findsOneWidget,
    );
    expect(find.text('Remove signal history?'), findsNothing);
    expect(h.calls, isEmpty);
  });

  testWidgets('cancelling the confirm removes nothing', (t) async {
    final h = _Installer(have: '0.1.0');
    await _open(t, h);
    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(h.calls, isEmpty);
  });

  testWidgets('a newer release offers the update', (t) async {
    final h = _Installer(
      have: '0.1.0',
      rel: const HelperRelease(version: '0.2.0', ipkUrl: 'u', apkUrl: 'u'),
    );
    await _open(t, h);
    expect(_button('Update to 0.2.0'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    await t.tap(_button('Update to 0.2.0'));
    await t.pump();
    expect(h.calls, ['install']);
  });

  testWidgets('nothing published disables Install', (t) async {
    await _open(t, _Installer(rel: null));
    expect(find.text("Signal history isn't published yet."), findsOneWidget);
    final b = t.widget<FilledButton>(_button('Install'));
    expect(b.onPressed, isNull);
  });

  testWidgets('no GitHub hides Install and offers Try again', (t) async {
    final h = _Installer(offline: true);
    await _open(t, h);
    expect(find.text("Couldn't reach GitHub"), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    h.offline = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(_button('Install'), findsOneWidget);
  });

  testWidgets('a router that does not answer says so', (t) async {
    final h = _Installer(statusError: const NoobRpcError('Not logged in'));
    await _open(t, h);
    expect(find.text('Not logged in'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    h.statusError = TimeoutException('slow');
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the router"), findsOneWidget);
    h.statusError = null;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(_button('Install'), findsOneWidget);
  });

  testWidgets('a running install is picked up on open', (t) async {
    final h = _Installer(
      state: const InstallState(InstallPhase.running, op: 'install'),
    );
    await _open(t, h, settle: false);
    expect(h.calls, ['install']);
    expect(find.textContaining('Installing'), findsOneWidget);
    expect(find.text('Install'), findsNothing);
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Signal history installed.'), findsOneWidget);
  });

  testWidgets('a running remove is picked up on open', (t) async {
    final h = _Installer(
      have: '0.1.0',
      state: const InstallState(InstallPhase.running, op: 'remove'),
    );
    await _open(t, h, settle: false);
    expect(h.calls, ['remove']);
    expect(find.textContaining('Removing'), findsOneWidget);
    h.job!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('an install that finished while away is reported', (t) async {
    final h = _Installer(
      state: const InstallState(InstallPhase.done, op: 'install'),
    );
    await _open(t, h);
    expect(h.calls, ['install']);
    expect(find.text('Version 0.1.0'), findsOneWidget);
    expect(find.text('Signal history installed.'), findsOneWidget);
    expect(_button('Install'), findsNothing);
  });

  testWidgets('an install that failed while away shows why', (t) async {
    final h = _Installer(
      state: const InstallState(
        InstallPhase.done,
        op: 'install',
        code: 1,
        log: 'bad package',
      ),
    );
    await _open(t, h);
    expect(find.text('bad package'), findsOneWidget);
    await t.tap(_button('Install'));
    await t.pump();
    expect(h.calls, ['install', 'install']);
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Version 0.1.0'), findsOneWidget);
  });

  testWidgets('raw router words become plain words', (t) async {
    await _open(
      t,
      _Installer(statusError: const NoobRpcError('Permission denied')),
    );
    expect(
      find.text(
        "Your router login can't do this. Sign in again or use an admin "
        'login.',
      ),
      findsOneWidget,
    );
    expect(find.text('Permission denied'), findsNothing);
  });

  testWidgets('closing mid-install leaves the job running', (t) async {
    final h = _Installer();
    await _open(t, h);
    await t.tap(_button('Install'));
    await t.pump();
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(find.text(_body), findsNothing);
    h.job!.complete();
    await t.pumpAndSettle();
    expect(find.text('Signal history installed.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('HistoryScreen helper row', () {
    Future<void> pump(WidgetTester t, _Installer h) async {
      await t.pumpWidget(
        MaterialApp(
          theme: KeystoneTheme.buildLightTheme(),
          home: HistoryScreen(load: (_, _) async => null, helper: h),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('shows the installed version and opens the sheet', (t) async {
      final h = _Installer(have: '0.1.0');
      await pump(t, h);
      expect(find.text('Signal history on the router'), findsOneWidget);
      expect(find.text('Version 0.1.0'), findsOneWidget);
      await t.tap(find.text('Signal history on the router'));
      await t.pumpAndSettle();
      expect(find.text(signalHistoryText.about), findsOneWidget);
    });

    testWidgets('says Not installed', (t) async {
      await pump(t, _Installer());
      expect(find.text('Not installed'), findsOneWidget);
    });
  });

  group('HistoryRow', () {
    Future<void> pump(
      WidgetTester t,
      List<HistorySource> sources, {
      _Installer? helper,
      bool settle = true,
    }) async {
      await t.pumpWidget(
        MaterialApp(
          theme: KeystoneTheme.buildLightTheme(),
          home: Scaffold(
            body: HistoryRow(
              app: _FakeApp(),
              sources: sources,
              helper: helper ?? _Installer(),
            ),
          ),
        ),
      );
      await t.tap(find.text('History'));
      settle ? await t.pumpAndSettle() : await t.pump();
    }

    testWidgets('opens the History screen with one load', (t) async {
      final a = _Src(null),
          b = _Src(const HistoryData(points: [], traffic: []));
      await pump(t, [a, b]);
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text(_body), findsNothing);
      expect(a.loads, 1);
      expect(b.loads, 1);
    });

    testWidgets('passes the kept days to the screen', (t) async {
      final src = [_Src(const HistoryData(points: [], traffic: []))];
      await pump(
        t,
        src,
        helper: _Installer(have: '0.2.0')..infoMap = {'keep_days': 30},
      );
      expect(t.widget<HistoryScreen>(find.byType(HistoryScreen)).maxDays, 30);
    });

    testWidgets('a second tap while loading does not open a second screen', (
      t,
    ) async {
      final gate = Completer<void>();
      final h = _Installer(have: '0.2.0')
        ..infoMap = {'keep_days': 14}
        ..infoGate = gate.future;
      await pump(
        t,
        [_Src(const HistoryData(points: [], traffic: []))],
        helper: h,
        settle: false,
      );
      await t.tap(find.text('History'), warnIfMissed: false);
      await t.pump();
      gate.complete();
      await t.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(h.infoCalls, 1);
    });

    testWidgets('keeps 7 days without keep_days', (t) async {
      await pump(t, [_Src(const HistoryData(points: [], traffic: []))]);
      expect(t.widget<HistoryScreen>(find.byType(HistoryScreen)).maxDays, 7);
    });

    testWidgets('a denied load opens the sheet', (t) async {
      await pump(t, [
        _Src(null, error: const NoobRpcError('Permission denied')),
        _Src(null),
      ]);
      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.text(_body), findsOneWidget);
    });

    testWidgets('opens the sheet when no source has data', (t) async {
      await pump(t, [_Src(null), _Src(null)]);
      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.text(_body), findsOneWidget);
    });

    testWidgets('has the subtitle', (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: KeystoneTheme.buildLightTheme(),
          home: Scaffold(body: HistoryRow(app: _FakeApp())),
        ),
      );
      expect(find.text('Signal, line ping and data over time'), findsOneWidget);
    });
  });

  group('retention', () {
    Future<_Installer> open7(WidgetTester t, {int keep = 7}) async {
      final h = _Installer(have: '0.2.0')
        ..infoMap = {'keep_days': keep, 'max_days': 30};
      await _open(t, h);
      return h;
    }

    testWidgets('hidden when the helper has no keep_days', (t) async {
      await _open(t, _Installer(have: '0.1.0')..infoMap = {'version': '0.1.0'});
      expect(find.text('Keep history for'), findsNothing);
    });

    testWidgets('shows the options, the current one and the space', (t) async {
      await open7(t, keep: 14);
      expect(find.text('Keep history for'), findsOneWidget);
      for (final d in ['7 days', '14 days', '30 days']) {
        expect(find.text(d), findsOneWidget);
      }
      expect(find.text('Up to 2.1 MB on the router'), findsOneWidget);
    });

    testWidgets('the intro leaves the days to the picker', (t) async {
      await open7(t);
      expect(find.text(_body), findsNothing);
      expect(
        find.text(
          'Adds a small background service to the router that keeps signal, '
          'line ping and data history. About 4 KB. You can remove it here '
          'any time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('only offers values up to max_days', (t) async {
      final h = _Installer(have: '0.2.0')
        ..infoMap = {'keep_days': 7, 'max_days': 14};
      await _open(t, h);
      expect(find.text('30 days'), findsNothing);
      expect(find.text('14 days'), findsOneWidget);
    });

    testWidgets('raising saves without asking', (t) async {
      final h = await open7(t);
      await t.tap(find.text('30 days'));
      await t.pumpAndSettle();
      expect(h.kept, [30]);
      expect(find.text('Up to 4 MB on the router'), findsOneWidget);
    });

    testWidgets('lowering asks first', (t) async {
      final h = await open7(t, keep: 30);
      await t.tap(find.text('14 days'));
      await t.pumpAndSettle();
      expect(find.text('Keep only 14 days?'), findsOneWidget);
      expect(
        find.text('Readings older than 14 days are deleted now.'),
        findsOneWidget,
      );
      await t.tap(find.text('Keep 14 days'));
      await t.pumpAndSettle();
      expect(h.kept, [14]);
    });

    testWidgets('cancelling the question saves nothing', (t) async {
      final h = await open7(t, keep: 30);
      await t.tap(find.text('7 days'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(h.kept, isEmpty);
      expect(find.text('Up to 4 MB on the router'), findsOneWidget);
    });

    testWidgets('a failed save says why and keeps the old value', (t) async {
      final h = await open7(t);
      h.keepError = const NoobRpcError('Disk is full');
      await t.tap(find.text('14 days'));
      await t.pumpAndSettle();
      expect(find.text('Disk is full'), findsOneWidget);
      expect(find.text('Up to 1 MB on the router'), findsOneWidget);
    });
  });
}
