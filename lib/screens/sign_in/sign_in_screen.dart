import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/routers/routers_sheet.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/sign_in/password_sheet.dart';
import 'package:yet_another_luci_app/screens/sign_in/reviewer_mode_dialog.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_help_screen.dart';
import 'package:yet_another_luci_app/services/api_service.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';
import 'package:yet_another_luci_app/services/router_lights_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/utils/gateway_utils.dart';
import 'package:yet_another_luci_app/widgets/keystone/keystone_mark.dart';
import 'package:yet_another_luci_app/widgets/keystone/router_drawing.dart';

abstract class SignInBackend {
  model.Router? get savedRouter;
  Future<bool> login(String ip, String user, String password);
  LoginFailure get lastFailure;
  String? get errorMessage;
  Future<RouterLights> readLights();
  Future<String?> detectGatewayIp();
  Future<void> enableReviewerMode();
}

class AppStateSignInBackend implements SignInBackend {
  const AppStateSignInBackend();

  AppState get _app => AppState.instance;

  @override
  model.Router? get savedRouter => _app.selectedRouter;
  @override
  LoginFailure get lastFailure => _app.lastLoginFailure;
  @override
  String? get errorMessage => _app.errorMessage;
  @override
  Future<String?> detectGatewayIp() => GatewayUtils.detectGatewayIp();
  @override
  Future<void> enableReviewerMode() => _app.setReviewerMode(true);

  @override
  Future<bool> login(String ip, String user, String password) => _app.login(
    ip,
    user,
    password,
    savedRouter?.ipAddress == ip && (savedRouter?.useHttps ?? false),
  );

  @override
  Future<RouterLights> readLights() {
    final api = _app.apiService;
    final sid = _app.sysauth;
    final ip = _app.currentRouterIp ?? savedRouter?.ipAddress;
    if (api == null || sid == null || ip == null) {
      return Future.value(RouterLights.unlit);
    }
    final https = savedRouter?.useHttps ?? false;
    return RouterLightsService(
      (o, m, p) => api is RealApiService
          ? api.callWithContext(
              ip,
              sid,
              https,
              object: o,
              method: m,
              params: p,
              isRetry: true,
            )
          : api.call(ip, sid, https, object: o, method: m, params: p),
    ).read();
  }
}

String routerDisplayName(model.Router? r) {
  final own = r?.name?.trim();
  if (own != null && own.isNotEmpty) return own;
  final words = (r?.lastKnownModel ?? '').trim().split(RegExp(r'\s+'));
  final code = words.lastWhere(
    (w) => w.contains(RegExp(r'\d')),
    orElse: () => '',
  );
  if (code.isNotEmpty) return code;
  return 'Your router';
}

enum _Phase { ready, signingIn, signedIn }

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({
    super.key,
    this.initialIp,
    this.initialUsername,
    this.initialPassword,
    this.autoConnect = false,
    this.lightStep = const Duration(milliseconds: 180),
    this.backend,
    this.onSignedIn,
  });

  final String? initialIp;
  final String? initialUsername;
  final String? initialPassword;
  final bool autoConnect;
  final Duration lightStep;
  final SignInBackend? backend;

  final void Function(BuildContext context)? onSignedIn;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  late final SignInBackend _backend =
      widget.backend ?? const AppStateSignInBackend();
  _Phase _phase = _Phase.ready;
  String? _error;
  String? _ip;
  String? _gateway;
  RouterLights _lights = RouterLights.unlit;
  int _shown = 0;
  int _attempt = 0;

  model.Router? get _router => _backend.savedRouter;
  String get _user => widget.initialUsername ?? _router?.username ?? 'root';
  String get _address => _ip ?? widget.initialIp ?? _router?.ipAddress ?? '';

  @override
  void initState() {
    super.initState();
    _backend.detectGatewayIp().then((ip) {
      if (!mounted || ip == null) return;
      setState(() {
        _gateway = ip;
        if (widget.initialIp == null && _router == null) _ip = ip;
      });
    });
    if (widget.autoConnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
    }
  }

  Future<bool?> _login(String? password) async {
    if (!await LocalNetworkPermissionService.requestWithRationale(context)) {
      if (mounted) {
        setState(
          () => _error =
              'Keystone needs local network access to reach the router. '
              'Allow it in Android Settings, Apps, Keystone, Permissions.',
        );
      }
      return null;
    }
    if (!mounted) return null;
    final attempt = ++_attempt;
    setState(() {
      _phase = _Phase.signingIn;
      _error = null;
    });
    final ok = await _backend.login(
      _address,
      _user,
      password ?? widget.initialPassword ?? _router?.password ?? '',
    );
    if (!mounted || attempt != _attempt) return null;
    setState(() => _phase = ok ? _Phase.signedIn : _Phase.ready);
    if (ok) unawaited(_finish());
    return ok;
  }

  Future<void> _finish() async {
    final attempt = _attempt;
    final lights = await _backend.readLights().timeout(
      const Duration(milliseconds: 1500),
      onTimeout: () => RouterLights.unlit,
    );
    if (!mounted || attempt != _attempt) return;
    setState(() => _lights = lights);
    if (!MediaQuery.of(context).disableAnimations) {
      for (var i = 1; i <= 6; i++) {
        await Future<void>.delayed(widget.lightStep);
        if (!mounted || attempt != _attempt) return;
        setState(() => _shown = i);
      }
    }
    if (!mounted) return;
    (widget.onSignedIn ?? _goHome)(context);
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, a, _) => const MainScreen(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ),
      (_) => false,
    );
  }

  Future<void> _connect() async {
    if (await _login(null) != false) return;
    if (_backend.lastFailure == LoginFailure.wrongPassword) {
      await _askPassword();
    } else {
      setState(() => _error = _backend.errorMessage);
    }
  }

  Future<void> _askPassword() => showPasswordSheet(
    context,
    user: _user,
    onSubmit: (password) async {
      final ok = await _login(password);
      if (ok != false || !mounted) return true;
      if (_backend.lastFailure == LoginFailure.wrongPassword) return false;
      setState(() => _error = _backend.errorMessage);
      return true;
    },
    onChangeUser: _otherRouter,
    onShowReset: () => _help(openReset: true),
  );

  Timer? _reviewerHold;

  void _holdLogo() =>
      _reviewerHold = Timer(AppConfig.reviewerModeActivationDuration, () async {
        if (!mounted || !await confirmReviewerMode(context)) return;
        await _backend.enableReviewerMode();
        if (mounted) (widget.onSignedIn ?? _goHome)(context);
      });

  @override
  void dispose() {
    _reviewerHold?.cancel();
    super.dispose();
  }

  void _cancel() => setState(() {
    _attempt++;
    _phase = _Phase.ready;
  });

  void _otherRouter() => showRoutersSheet(context, fromSignIn: true);

  void _help({bool openReset = false}) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SignInHelpScreen(
        routerLabel: routerDisplayName(_router) == 'Your router'
            ? 'router'
            : routerDisplayName(_router),
        address: _address.isEmpty ? '192.168.1.1' : _address,
        openReset: openReset,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final busy = _phase != _Phase.ready;
    final shownLights = RouterLights([
      for (var i = 0; i < 6; i++)
        i < _shown ? _lights.slots[i] : LightColor.off,
    ]);

    return Scaffold(
      backgroundColor: ks.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: SizedBox(
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onLongPressStart: (_) => _holdLogo(),
                            onLongPressEnd: (_) => _reviewerHold?.cancel(),
                            onLongPressCancel: () => _reviewerHold?.cancel(),
                            child: const Hero(
                              tag: 'keystone-mark',
                              child: KeystoneMark(width: 30),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Keystone',
                            style: KeystoneType.bodyStrong(
                              ks.tx,
                            ).copyWith(fontSize: 17),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _help,
                          icon: Icon(
                            Icons.help_outline_rounded,
                            size: 18,
                            color: ks.mu,
                          ),
                          label: Text('Help', style: KeystoneType.body(ks.mu)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final drawing = (box.maxHeight * 0.55 / 1.32).clamp(
                      90.0,
                      224.0,
                    );
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _Hero(
                              width: drawing,
                              child: RouterDrawing(
                                model: _router?.lastKnownModel,
                                lights: shownLights,
                                width: drawing,
                              ),
                            ),
                            const SizedBox(height: 26),
                            if (_error != null || _gateway == _address)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _error == null ? ks.ok : ks.bad,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _error == null
                                          ? 'On this Wi-Fi'
                                          : "Can't reach it",
                                      style: KeystoneType.secondary(
                                        ks.mu,
                                      ).copyWith(fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 10),
                            Text(
                              routerDisplayName(_router),
                              textAlign: TextAlign.center,
                              style: KeystoneType.headline(ks.tx),
                            ),
                            const SizedBox(height: 6),
                            if (_phase == _Phase.ready)
                              Text(_address, style: KeystoneType.address(ks.mu))
                            else
                              _Status(signedIn: _phase == _Phase.signedIn),
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: KeystoneType.body(ks.bad),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 50),
                child: FilledButton(
                  onPressed: busy ? null : _connect,
                  style: FilledButton.styleFrom(
                    backgroundColor: ks.tx,
                    foregroundColor: ks.bg,
                    disabledBackgroundColor: ks.tint,
                    disabledForegroundColor: ks.tx2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: busy
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ks.tx2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Connecting',
                              style: KeystoneType.bodyStrong(ks.tx2),
                            ),
                          ],
                        )
                      : Text('Connect', style: KeystoneType.bodyStrong(ks.bg)),
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: busy
                    ? Center(child: _Link('Cancel', onTap: _cancel))
                    : Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _Link('Use a password', onTap: _askPassword),
                          Text('·', style: KeystoneType.body(ks.line)),
                          _Link('Other router', onTap: _otherRouter),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          bottom: -6,
          child: Container(
            width: width * 1.35,
            height: width * 0.3,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  ks.tx.withValues(alpha: 0.06),
                  ks.tx.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    if (!signedIn) {
      return Text('Signing in', style: KeystoneType.body(ks.tx2));
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Signed in. ', style: KeystoneType.body(ks.tx2)),
          TextSpan(
            text: 'Checking the internet',
            style: KeystoneType.body(
              ks.ok,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Text(
        label,
        style: KeystoneType.body(ks.tx2).copyWith(
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
          decorationColor: ks.line,
        ),
      ),
    );
  }
}
