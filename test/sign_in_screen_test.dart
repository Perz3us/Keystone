import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/design/keystone_theme.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/widgets/keystone/keystone_mark.dart';

class _Backend implements SignInBackend {
  _Backend({this.router, this.failure = LoginFailure.none, this.error});

  model.Router? router;
  LoginFailure failure;
  String? error;
  final passwords = <String>[];
  Completer<bool>? hold;

  @override
  model.Router? get savedRouter => router;
  @override
  LoginFailure get lastFailure => failure;
  @override
  String? get errorMessage => error;
  String? gateway = '192.168.1.1';
  @override
  Future<String?> detectGatewayIp() async => gateway;
  @override
  Future<bool> login(String ip, String user, String password) async {
    passwords.add(password);
    if (hold != null) return hold!.future;
    return failure == LoginFailure.none;
  }

  var reviewer = 0;
  @override
  Future<void> enableReviewerMode() async => reviewer++;

  @override
  Future<RouterLights> readLights() async => const RouterLights([
    LightColor.green,
    LightColor.red,
    LightColor.green,
    LightColor.green,
    LightColor.green,
    LightColor.off,
  ]);
}

model.Router _router({String? model_, String? hostname, String? name}) =>
    model.Router(
      id: 'r',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: '',
      useHttps: false,
      lastKnownModel: model_,
      lastKnownHostname: hostname,
      name: name,
    );

Future<int> _pump(
  WidgetTester t,
  _Backend b, {
  bool autoConnect = false,
  double textScale = 1,
}) async {
  var signedIn = 0;
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: KeystoneTheme.buildLightTheme(),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(
          c,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SignInScreen(
        backend: b,
        autoConnect: autoConnect,
        lightStep: const Duration(milliseconds: 10),
        onSignedIn: (_) => signedIn++,
      ),
    ),
  );
  await t.pumpAndSettle();
  return signedIn;
}

void main() {
  testWidgets('Ready shows the router by its model', (t) async {
    await _pump(t, _Backend(router: _router(model_: 'Arcadyan AW1000')));
    expect(find.text('On this Wi-Fi'), findsOneWidget);
    expect(find.text('AW1000'), findsOneWidget);
    expect(find.text('192.168.1.1'), findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Use a password'), findsOneWidget);
    expect(find.text('Other router'), findsOneWidget);
  });

  testWidgets('a router away from this Wi-Fi is not called local', (t) async {
    await _pump(t, _Backend(router: _router())..gateway = '10.0.0.1');
    expect(find.text('On this Wi-Fi'), findsNothing);
  });

  testWidgets('a router that did not answer says so', (t) async {
    await _pump(
      t,
      _Backend(router: _router())
        ..failure = LoginFailure.unreachable
        ..error = 'No answer',
      autoConnect: true,
    );
    expect(find.text('On this Wi-Fi'), findsNothing);
    expect(find.text("Can't reach it"), findsOneWidget);
  });

  testWidgets('a firmware hostname is never the name', (t) async {
    await _pump(t, _Backend(router: _router(hostname: 'NoobWRT')));
    expect(find.text('Your router'), findsOneWidget);
    expect(find.text('NoobWRT'), findsNothing);
  });

  testWidgets('a name the user gave wins', (t) async {
    await _pump(
      t,
      _Backend(
        router: _router(model_: 'Arcadyan AW1000', name: 'Home'),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('Connect signs in, lights up, then goes home', (t) async {
    final b = _Backend(router: _router(model_: 'Arcadyan AW1000'));
    var home = 0;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    b.hold = Completer<bool>();
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: SignInScreen(
          backend: b,
          lightStep: const Duration(milliseconds: 10),
          onSignedIn: (_) => home++,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Connect'));
    await t.pump();
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Signing in'), findsOneWidget);
    b.hold!.complete(true);
    await t.pump();
    await t.pump();
    expect(find.text('Signed in. Checking the internet'), findsOneWidget);
    await t.pump(const Duration(milliseconds: 200));
    expect(home, 1);
    expect(b.passwords, ['']);
  });

  testWidgets('a wrong password opens the password sheet', (t) async {
    await _pump(
      t,
      _Backend(router: _router(), failure: LoginFailure.wrongPassword),
    );
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    expect(find.text('Router password'), findsOneWidget);
  });

  for (final f in [LoginFailure.unreachable, LoginFailure.notOpenWrt]) {
    testWidgets('$f shows the message, not the sheet', (t) async {
      await _pump(
        t,
        _Backend(router: _router(), failure: f, error: 'Nothing answered.'),
      );
      await t.tap(find.text('Connect'));
      await t.pumpAndSettle();
      expect(find.text('Nothing answered.'), findsOneWidget);
      expect(find.text('Router password'), findsNothing);
      expect(find.text('Connect'), findsOneWidget);
    });
  }

  testWidgets('Cancel goes back, and a late success is ignored', (t) async {
    final b = _Backend(router: _router())..hold = Completer<bool>();
    var home = 0;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: SignInScreen(backend: b, onSignedIn: (_) => home++),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Connect'));
    await t.pump();
    await t.tap(find.text('Cancel'));
    await t.pump();
    expect(find.text('Connect'), findsOneWidget);
    b.hold!.complete(true);
    await t.pumpAndSettle();
    expect(home, 0);
  });

  testWidgets('large text fits on a real phone', (t) async {
    await _pump(
      t,
      _Backend(router: _router(model_: 'Arcadyan AW1000')),
      textScale: 1.3,
    );
    expect(t.takeException(), isNull);
    await t.tap(find.text('Use a password'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('the button grows with the largest text', (t) async {
    final b = _Backend(router: _router())..hold = Completer<bool>();
    await _pump(t, b, textScale: 2.5);
    await t.tap(find.text('Connect'));
    await t.pump();
    final button = t.getSize(find.byType(FilledButton)).height;
    final label = t
        .renderObject<RenderBox>(find.text('Connecting'))
        .getMaxIntrinsicHeight(double.infinity);
    expect(button, greaterThanOrEqualTo(label + 16));
    b.hold!.complete(false);
    await t.pumpAndSettle();
  });

  testWidgets('closing the sheet mid sign-in still goes home', (t) async {
    final b = _Backend(router: _router(), failure: LoginFailure.wrongPassword);
    final home = <int>[];
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: SignInScreen(
          backend: b,
          lightStep: const Duration(milliseconds: 10),
          onSignedIn: (_) => home.add(1),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Connect'));
    await t.pumpAndSettle();
    b.hold = Completer<bool>();
    await t.enterText(find.byType(TextField), 'right');
    await t.tap(find.text('Sign in'));
    await t.pump();
    t.state<NavigatorState>(find.byType(Navigator)).pop();
    await t.pump(const Duration(milliseconds: 400));
    b.hold!.complete(true);
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
    expect(home, [1]);
  });

  testWidgets('a late wrong password after Cancel opens nothing', (t) async {
    final b = _Backend(router: _router(), failure: LoginFailure.wrongPassword)
      ..hold = Completer<bool>();
    await _pump(t, b);
    await t.tap(find.text('Connect'));
    await t.pump();
    await t.tap(find.text('Cancel'));
    await t.pump();
    b.hold!.complete(false);
    await t.pumpAndSettle();
    expect(find.text('Router password'), findsNothing);
  });

  testWidgets(
    'a failure that is not the password closes the sheet and says why',
    (t) async {
      final b = _Backend(
        router: _router(),
        failure: LoginFailure.wrongPassword,
      );
      await _pump(t, b);
      await t.tap(find.text('Connect'));
      await t.pumpAndSettle();
      b
        ..failure = LoginFailure.unreachable
        ..error = 'Nothing answered.';
      await t.enterText(find.byType(TextField), 'pw');
      await t.tap(find.text('Sign in'));
      await t.pumpAndSettle();
      expect(find.text('Router password'), findsNothing);
      expect(find.text('Nothing answered.'), findsOneWidget);
    },
  );

  testWidgets('back leaves the app', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (c) async {
        calls.add(c.method);
        return null;
      },
    );
    addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(t, _Backend(router: _router()));
    await t.binding.handlePopRoute();
    await t.pump();
    expect(calls, contains('SystemNavigator.pop'));
  });

  testWidgets('holding the logo 5 s opens the demo', (t) async {
    final b = _Backend(router: _router());
    var home = 0;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: SignInScreen(backend: b, onSignedIn: (_) => home++),
      ),
    );
    await t.pumpAndSettle();
    final hold = await t.startGesture(t.getCenter(find.byType(KeystoneMark)));
    await t.pump(const Duration(seconds: 6));
    await hold.up();
    await t.pumpAndSettle();
    expect(find.text('Open the demo?'), findsOneWidget);
    await t.tap(find.widgetWithText(TextButton, 'Open the demo'));
    await t.pumpAndSettle();
    expect(b.reviewer, 1);
    expect(home, 1);
  });

  testWidgets('a short hold does nothing', (t) async {
    final b = _Backend(router: _router());
    await _pump(t, b);
    final hold = await t.startGesture(t.getCenter(find.byType(KeystoneMark)));
    await t.pump(const Duration(seconds: 2));
    await hold.up();
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Activate'), findsNothing);
  });

  testWidgets('autoConnect starts straight away', (t) async {
    final b = _Backend(router: _router())..hold = Completer<bool>();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        theme: KeystoneTheme.buildLightTheme(),
        home: SignInScreen(backend: b, autoConnect: true, onSignedIn: (_) {}),
      ),
    );
    await t.pump();
    expect(find.text('Connecting'), findsOneWidget);
    b.hold!.complete(false);
    await t.pumpAndSettle();
  });
}
