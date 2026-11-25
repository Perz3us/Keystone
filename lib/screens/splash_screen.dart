// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/config/app_config.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/screens/sign_in/opening_animation.dart';
import 'package:yet_another_luci_app/screens/sign_in/sign_in_screen.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

import 'package:yet_another_luci_app/services/client_fingerprint_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _opened = Completer<void>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeAppSession();
    });
  }

  Future<void> _initializeAppSession() async {
    final appState = AppState.instance;

    try {
      final reviewerStorageFuture = SecureStorageService().readValue(
        AppConfig.reviewerModeKey,
      );
      final credsFuture = SecureStorageService().getCredentials();
      final fingerprintsFuture = ClientFingerprintService.instance.initialize();
      final appStateInitFuture = appState.initializationFuture;

      final results = await Future.wait([
        reviewerStorageFuture,
        credsFuture,
        fingerprintsFuture,
        appStateInitFuture,
        _opened.future,
      ]);

      final reviewerModeEnabled = results[0] as String?;
      final creds = results[1] as Map<String, String?>;

      if (!mounted) return;

      if (reviewerModeEnabled == 'true') {
        await appState.setReviewerMode(true);
        if (!mounted) return;
        _navigateToMainScreen();
        return;
      }

      final savedIp = creds['ipAddress'] ?? appState.selectedRouter?.ipAddress;
      final savedUser = creds['username'] ?? appState.selectedRouter?.username;
      final savedPass = creds['password'] ?? appState.selectedRouter?.password;

      _navigateToSignIn(
        initialIp: savedIp,
        initialUsername: savedUser,
        initialPassword: savedPass,
        autoConnect: savedIp != null && savedPass != null,
      );
    } catch (e, stack) {
      Logger.exception(
        'SplashScreen initialization failed, navigating to sign-in fallback',
        e,
        stack,
      );
      if (!mounted) return;
      _navigateToSignIn();
    }
  }

  void _navigateToMainScreen() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const MainScreen()),
      (route) => false,
    );
  }

  void _navigateToSignIn({
    String? initialIp,
    String? initialUsername,
    String? initialPassword,
    bool autoConnect = false,
  }) {
    if (!mounted) return;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SignInScreen(
          initialIp: initialIp,
          initialUsername: initialUsername,
          initialPassword: initialPassword,
          autoConnect: autoConnect,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            disableAnimations
            ? child
            : FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Cubic(0.25, 1, 0.5, 1),
                ),
                child: child,
              ),
        transitionDuration: disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OpeningAnimation(
      onHoldDone: () {
        if (!_opened.isCompleted) _opened.complete();
      },
    );
  }
}
