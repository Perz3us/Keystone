// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

abstract class IAuthService {
  Future<void> login(
    String ipAddress,
    String username,
    String password,
    bool useHttps, {
    BuildContext? context,
  });
  Future<bool> tryAutoLogin(
    String? ipAddress,
    String? username,
    String? password,
    bool? useHttps, {
    bool force = false,
    BuildContext? context,
  });
  Future<void> logout();
  Future<bool> checkRouterAvailability(
    String ipAddress,
    bool useHttps, {
    BuildContext? context,
  });

  String? get sysauth;
  String? get ipAddress;
  bool get useHttps;
  bool get isAuthenticated;

  int get authEpoch;

  int startPasswordTransition();

  void completePasswordTransition({
    required String newToken,
    required String newPassword,
    required String ipAddress,
    required bool useHttps,
  });

  void cancelPasswordTransition();

  void updateSessionToken(String? token);
}
